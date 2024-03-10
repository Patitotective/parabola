import std/[math, jsffi, dom, jsconsole, enumerate, with, strformat]
import karax/[karax, karaxdsl, vdom, vstyles]

import ../../matter, ../utils, utils

type
  Excercise = object
    pos: tuple[x, y: int]
    angle: float
    speed: int

const
  deltaTime = 16.666
  canvasWidth = 700
  canvasHeight = 500
  excercises = [Excercise(pos: (10, 0), angle: 120, speed: 10)]

let
  wrapObject = JsObject{min: JsObject{x: 0, y: 0}, max: JsObject{x: canvasWidth, y: canvasHeight}} # To avoid boilerplate

var
  engine*, mrender*, bullet, floor, ground*, runner*: JsObject
  constraint*, mconstraint*, mouse*: JsObject
  canvas*: Element
  trail = newSeq[JsVector]()
  mConstraintDragEnded*: bool

proc load*() = #canvasId: string, canvasWidth, canvasHeight: int, background: string) = 
  # MathJax
  MathJax.typesetPromise()

  # Matter
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

    b.anglePrev = oldb.anglePrev
    b.force = oldb.force
    b.torque = oldb.torque
    Body.setPosition(b, oldb.position)
    Body.setVelocity(b, oldb.velocity)
    Body.setAngularVelocity(b, oldb.angularVelocity)
    Body.setAngle(b, oldb.angle)

proc renderTextDiv*(): VNode = 
  result = buildHtml tdiv(style = "float: left; width: 50%;".toCss):
    p(text r"\(a = \frac{v_f - v_i}{\Delta t}\)", style = "font-size: 80px;".toCss)
    # p(text fmt"\(a = \frac{{v_f - {bullet.position.x}}}{{\Delta t}}\)", style = "font-size: 80px;".toCss)

proc renderSimDiv*(): VNode = 
  result = buildHtml tdiv(style = "float: right; width: 50%;".toCss):
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

  
proc render*(params: Params): VNode =
  result = buildHtml tdiv(style = "width: 100%; justify-content: center; align-items: center;".toCss):
    renderTextDiv()
    renderSimDiv()

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


