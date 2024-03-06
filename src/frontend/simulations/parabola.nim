import std/[math, jsffi, dom, jsconsole, enumerate, with, strformat]
import karax/[karax, karaxdsl, vdom, vstyles]

import ../../matter, ../utils, utils

const
  deltaTime = 16.666
  canvasWidth = 700
  canvasHeight = 500

let wrapObject = JsObject{min: JsObject{x: 0, y: 0}, max: JsObject{x: canvasWidth, y: canvasHeight}} # To avoid boilerplate

var
  engine*, mrender*, bullet, floor, ground*, runner*: JsObject
  constraint*, mconstraint*, mouse*: JsObject
  canvas*: Element
  trail = newSeq[JsVector]()
  mConstraintDragEnded*: bool

proc load*() = #canvasId: string, canvasWidth, canvasHeight: int, background: string) = 
  Matter.use("matter-wrap")
  loadAliases()

  engine = Engine.create()
  canvas = getElementById("canvas")
  mrender = Render.create(JsObject{
    canvas: canvas, 
    engine: engine,
    options: JsObject{
      width: canvasWidth,
      height: canvasHeight,
      showAngleIndicator: true,
      background: "rgb(20, 21, 31)",
    }
  })
  Render.run(mrender)

  runner = Runner.create(JsObject{delta: deltaTime})
  Runner.run(runner, engine)
  
  bullet = Bodies.circle(400, 300, 25, JsObject{isStatic: false, frictionAir: 0, friction: 1, mass: 2, plugin: JsObject{wrap: wrapObject}})

  Body.setInertia(bullet, infinity)
  Body.setAngle(bullet, degToRad(180d))

  # constraint = Constraint.create(JsObject{pointA: JsObject{x: 400, y: 300}, bodyB: bullet, length: 30, stiffness: 0.1})

  floor = Bodies.rectangle(350, 495, 800, 20, JsObject{isStatic: true})

  mouse = Mouse.create(canvas)
  mconstraint = MouseConstraint.create(engine, JsObject{mouse: mouse})

  Composite.add(engine.world, toJs [bullet, mconstraint, 
    # Walls
    Bodies.rectangle(350, 10, 800, 20, JsObject{isStatic: true}), # up
    # Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}), # right
    floor, # down
    # Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}), # left
    # Thingy
    Bodies.rectangle(400, 350, 20, 80, JsObject{isStatic: false, plugin: JsObject{wrap: wrapObject}})

  ])

  # Events.on(mconstraint, "enddrag", proc(event: JsObject) = 
  #   console.log event
  #   mConstraintDragEnded = true
  #   # discard setTimeOut(proc() = Composite.remove(engine.world, constraint), 10)
  # )

  # Events.on(engine, "afterUpdate", proc(event: JsObject) = 
  #   let d = distance(constraint.pointA, bullet.position)
  #   # if mConstraintDragEnded:
  #     # print d
  #   if mConstraintDragEnded and d.x.to(float64) < 30d and d.y.to(float64) < 30d:
  #     # print distance(constraint.pointA, bullet.position)
  #     # jsonPrint constraint, mconstraint
  #     Composite.remove(engine.world, constraint)
  #     mConstraintDragEnded = false
  # )

  # Seems like it's not needed anymore, since inertia = infinity
  # Events.on(engine, "collisionStart", proc (event: JsObject) = 
  #   if event.pairs[0].bodyA.id == bullet.id and event.pairs[0].bodyB.id == floor.id:
  #     Body.setVelocity(bullet, JsObject{x: 0, y: 0})
  #     Body.setAngularVelocity(bullet, 0) 
  # )

  Events.on(mrender, "afterRender", proc() =
    Render.startViewTransform(mrender)
    mrender.context.globalAlpha = 0.7

    for i in trail:
      mrender.context.fillStyle = cstring"orange"
      mrender.context.fillRect(JsObject(i).x, JsObject(i).y, 2, 2)

    mrender.context.globalAlpha = 1
    Render.endViewTransform(mrender)
  )

proc reload() = 
  Composite.clear(engine.world)
  Engine.clear(engine)
  Render.stop(mrender)
  Runner.stop(runner)
  trail.setLen(0)
  load()

proc sendBulletFlying() = 
  let hypotenuse = bullet.circleRadius.to(float64) * 0.48 # force magnitude
  let x = cos(bullet.angle.to(float64)) * hypotenuse
  let y = sin(bullet.angle.to(float64)) * hypotenuse

  Body.setVelocity(bullet, JsObject{x: x, y: y})

proc rotateBullet(clockwise = true) = 
  var rad = degToRad((360 / bullet.vertices.length.to(float64))*2)
  if not clockwise:
    rad = -rad

  Body.rotate(bullet, rad)

proc calcTrajectory() = 
  var stop = false
  let bodies = cloneAllBodies(engine.world)

  proc onCollision(event: JsObject) = 
    if event.pairs[0].bodyA.id == bullet.id:
      stop = true

  Events.on(engine, "collisionStart", onCollision)

  sendBulletFlying()

  trail.setLen(0)
  for i in 1..1000:
    trail.add JsVector JsObject{x: jsFloatToInt bullet.position.x, y: jsFloatToInt bullet.position.y}

    if stop:
      break

    Engine.update(engine)

  Events.off(engine, "collitionStart", onCollision)

  for (e, b) in enumerate Composite.allBodies(engine.world):
    assert b.id == bodies[e].id
    let oldb = bodies[e]

    # with b:
    #   angle = oldb.angle
    #   position = oldb.position
    #   force = oldb.force
    #   torque = oldb.torque
    #   positionImpulse = oldb.positionImpulse
    #   constraintImpulse = oldb.constraintImpulse
    #   totalContacts = oldb.totalContacts
    #   speed = oldb.speed
    #   angularSpeed = oldb.angularSpeed
    #   velocity = oldb.velocity
    #   angularVelocity = oldb.angularVelocity

    # print JsObject{old: oldb.velocity, cur: b.velocity}

    b.anglePrev = oldb.anglePrev
    b.force = oldb.force
    b.torque = oldb.torque
    Body.setPosition(b, oldb.position)
    Body.setVelocity(b, oldb.velocity)
    Body.setAngularVelocity(b, oldb.angularVelocity)
    Body.setAngle(b, oldb.angle)

    # print JsObject{aft: b.velocity}
  
proc render*(params: Params): VNode =
  result = buildHtml(tdiv):
    button():
      text "Start the simulation"
      proc onclick()  =
          engine.timing.timeScale = 1
      
    button():
      text "Stop the simulation"
      proc onclick() = 
        engine.timing.timeScale = 0

    button():
      text "Rotate"
      proc onclick() = 
        rotateBullet()

    button(onclick = calcTrajectory):
      text "Trajectory"

    button():
      text "Rot & Traj"
      proc onclick() = 
        rotateBullet()
        calcTrajectory()

    button():
      text "Send ball flying"
      proc onclick() = 
        sendBulletFlying()
      
    canvas(id = "canvas", style = fmt"width: {canvasWidth}px; height: {canvasHeight}px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

document.addEventListener("keyup", proc (event: Event) = 
  let event = KeyboardEvent(event)
  case $event.key
  of "t":
    calcTrajectory()
  of "ArrowRight":
    rotateBullet()
    calcTrajectory()
  of "ArrowLeft":
    rotateBullet(false)
    calcTrajectory()
  of "Enter":
    sendBulletFlying()
  of "Backspace":
    reload()
  of "p":
    jsonPrint mconstraint, bullet
)


