import std/[math, jsffi, dom, jsconsole, enumerate]
import karax/[karax, karaxdsl, vdom, vstyles]

import ../../matter, ../utils, utils

const deltaTime = 16.666

var
  engine*, mrender*, bullet, ground*, runner*: JsObject
  constraint*, mconstraint*, mouse*: JsObject
  canvas*: Element
  trail = newSeq[JsVector]()
  mConstraintDragEnded*: bool

proc load*() = #canvasId: string, canvasWidth, canvasHeight: int, background: string) = 
  engine = Engine.create()
  canvas = getElementById("canvas")
  mrender = Render.create(JsObject{
    canvas: canvas, 
    engine: engine,
    options: JsObject{
      width: 700,
      height: 500,
      showAngleIndicator: true,
      background: "rgb(20, 21, 31)",
    }
  })
  Render.run(mrender)

  runner = Runner.create(JsObject{delta: deltaTime})
  Runner.run(runner, engine)
  
  bullet = Bodies.circle(400, 300, 25, JsObject{isStatic: false})
  Body.setAngle(bullet, degToRad(180d))

  constraint = Constraint.create(JsObject{pointA: JsObject{x: 400, y: 300}, bodyB: bullet, length: 30, stiffness: 0.1})

  mouse = Mouse.create(canvas)
  mconstraint = MouseConstraint.create(engine, JsObject{mouse: mouse})

  Composite.add(engine.world, toJs [bullet, constraint, mconstraint, 
    # Walls
    Bodies.rectangle(350, 10, 700, 20, JsObject{isStatic: true}),
    Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}),
    Bodies.rectangle(350, 495, 700, 20, JsObject{isStatic: true}),
    Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}),
    # Thingy
    Bodies.rectangle(400, 350, 20, 80, JsObject{isStatic: false})

  ])

  Events.on(mconstraint, "enddrag", proc(event: JsObject) = 
    console.log event
    mConstraintDragEnded = true
    # discard setTimeOut(proc() = Composite.remove(engine.world, constraint), 10)
  )

  Events.on(engine, "afterUpdate", proc(event: JsObject) = 
    let d = distance(constraint.pointA, bullet.position)
    if mConstraintDragEnded:
      print d
    if mConstraintDragEnded and d.x.to(float64) < 30d and d.y.to(float64) < 30d:
      # print distance(constraint.pointA, bullet.position)
      # jsonPrint constraint, mconstraint
      Composite.remove(engine.world, constraint)
      mConstraintDragEnded = false
  )

  Events.on(mrender, "afterRender", proc() =
    Render.startViewTransform(mrender)
    mrender.context.globalAlpha = 0.7

    for i in trail:
      mrender.context.fillStyle = cstring"orange"
      mrender.context.fillRect(JsObject(i).x, JsObject(i).y, 2, 2)

    mrender.context.globalAlpha = 1
    Render.endViewTransform(mrender)
  )

proc calcTrajectory() = 
  for i in 1..100:
    let g = JsVector JsObject{x: engine.gravity.x * engine.gravity.scale, y: engine.gravity.y * engine.gravity.scale}
    let t = deltaTime * float64 i
    trail.add JsVector(bullet.position) + JsVector(bullet.constraintImpulse) * t + (g / 2) * pow(t, 2)


    # pos(t) = startPos + startVel * t + gravitionalForce * (1/2) * t ** 2
  # var stop = false


  # let bodies = cloneAllBodies(engine.world)

  # if not mconstraint.body.isNil:
  #   mconstraint.body = nil
  #   mconstraint.constraint.bodyB = mconstraint.body
  #   mconstraint.constraint.pointB = nil

  #   # Composite.remove(engine.world, constraint)

  # Events.on(engine, "collisionStart", proc (event: JsObject) = 
  #   if event.pairs[0].bodyA.id == bullet.id:
  #     stop = true
  # )

  # let force = bullet.circleRadius.to(float64) / 250
  # # Body.applyForce(bullet, bullet.position, JsObject{x: cos(bullet.angle.to(float64)) * force, y: sin(bullet.angle.to(float64)) * force})

  # trail.setLen(0)
  # for i in 1..1000:
  #   trail.add JsObject{x: jsFloatToInt bullet.position.x, y: jsFloatToInt bullet.position.y}

  #   if stop:
  #     break

  #   Engine.update(engine)

  # Events.off(engine, "collitionStart")

  # for (e, b) in enumerate Composite.allBodies(engine.world):
  #   assert b.id == bodies[e].id
  #   let oldb = bodies[e]

  #   b.anglePrev = oldb.anglePrev
  #   b.force = oldb.force
  #   b.torque = oldb.torque
  #   Body.setPosition(b, oldb.position)
  #   Body.setVelocity(b, oldb.velocity)
  #   Body.setAngularVelocity(b, oldb.angularVelocity)
  #   Body.setAngle(b, oldb.angle)

  # # if not mconstraint.body.isNil:
  # Composite.add(engine.world, constraint)

proc render*(params: Params): VNode =
  result = buildHtml(tdiv):
    button():
      text "Start the simulation"
      proc onclick()  =
        # if engine.isNil:
          # loadMatter("canvas", 500, 500, "rgb(20, 21, 31)")
        # else:
          engine.timing.timeScale = 1
      
    button():
      text "Stop the simulation"
      proc onclick() = 
        engine.timing.timeScale = 0

    button():
      text "Rotate"
      proc onclick() = 
        Body.rotate(bullet, degToRad((360 / bullet.vertices.length.to(float64))*2))

    button(onclick = calcTrajectory):
      text "Trajectory"

    button():
      text "Rot & Traj"
      proc onclick() = 
        Body.rotate(bullet, degToRad((360 / bullet.vertices.length.to(float64))*2))
        echo degToRad(360 / bullet.vertices.length.to(float64))
        print bullet.angle
        calcTrajectory()

    button():
      text "Send ball flying"
      proc onclick() = 
        let force = bullet.circleRadius.to(float64) / 250
        Body.applyForce(bullet, bullet.position, JsObject{x: cos(bullet.angle.to(float64)) * force, y: sin(bullet.angle.to(float64)) * force})

    canvas(id = "canvas", style = "width: 700px; height: 500px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

document.addEventListener("keyup", proc (event: Event) = 
  let event = KeyboardEvent(event)
  case $event.key
  of "t":
    calcTrajectory()
  of "r":
    Composite.add(engine.world, constraint)
  of "p":
    jsonPrint mconstraint, constraint, bullet
)


