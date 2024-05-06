import std/[math, jsffi, dom, jsconsole, enumerate, with, strformat, asyncjs]
import karax/[karax, karaxdsl, vdom, vstyles]

import matter, utils

type
  Exercise = object
    pos*: tuple[x, y: int]
    angle*: int # Degrees
    angleRad*: float
    speed*: int
    velocity*: tuple[x, y: float]
    text*: string

  ExerciseStatus = enum
    esStart # Not launched yet
    esStarted # In the air
    esEnd # Touched something and stopped

proc initExercise(pos: tuple[x, y: int], angle: int, speed: int, text = ""): Exercise = 
  let angleRad = degToRad(float angle)
  Exercise(pos: pos, angle: angle, angleRad: angleRad, speed: speed, velocity: speedToVelRad(float speed, angleRad), text: text)

const
  deltaTime = 1000 / 60 # 60fps, 60 times in one second (1000 milliseconds)
  secPerFrame = 1 / 60
  canvasWidth = 700
  canvasHeight = 500
  groundHeight = 20
  timeScale = 0.60

var
  engine*, mrender*, bullet, ground*, runner*, thingy*: JsObject
  constraint*, mconstraint*, mouse*: JsObject
  canvas*: Element

  trail = newSeq[JsVector]()
  mConstraintDragEnded*: bool # True when you release the mouse constraint

  # The first exercise is the default exercise and it is modifed as you modify the bullet
  exercises = @[
    initExercise(pos = (0, 0), angle = 0, speed = 20), 
    initExercise(pos = (0, 0), angle = 0, speed = 20), 
    initExercise(pos = (0, 0), angle = 0, speed = 20), 
    initExercise(pos = (0, 0), angle = 0, speed = 20), 
    initExercise(pos = (0, 0), angle = 0, speed = 20), 
    initExercise(pos = (0, 0), angle = 0, speed = 20), 
    initExercise(pos = (0, 0), angle = 0, speed = 20), 
    initExercise(pos = (0, 0), angle = 0, speed = 20), 
    initExercise(pos = (50, 0), angle = 48, speed = 30, text = 
      "Una pelota se lanza a 12 m/s y a un ángulo de 67° " & 
      "respecto a la horizontal. ¿Cuál es su altura a los 2 segundos?"
    )
  ]
  curExercise = 0
  exerciseStatus: ExerciseStatus
  exerciseTotalTime: float
  paused = false # Is engine.timing.timeScale == 0?


proc wrapObject(): JsObject = 
  JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: canvas.clientWidth, y: undefined}} # To avoid boilerplate

## Loads the simulation
proc load*() =
  # Render all MathJax expressions asynchronously
  MathJax.typesetPromise()

  # Load wrap's plugin and load matter aliases to point to the correct values
  Matter.use("matter-wrap")
  loadMatterAliases()

  canvas = getElementById("canvas")
  engine = createEngine(JsObject{gravity: JsObject{x: 0, y: 1, scale: 0.001}, timing: JsObject{timeScale: timeScale}})
  mrender = createRender(JsObject{
    canvas: canvas,
    engine: engine,
    options: JsObject{
      width: canvas.clientWidth,
      height: canvas.clientHeight,
      showAngleIndicator: false,
      background: "transparent",#"rgb(20, 21, 31)",
    }
  })
  Render.run(mrender)

  runner = Runner.create(JsObject{delta: deltaTime})
  Runner.run(runner, engine)

  # Create and add all bodies to the world
  bullet = Bodies.circle(300, 300, 25, JsObject{isStatic: false, frictionAir: 0, friction: 1, plugin: JsObject{wrap: wrapObject()}})

  Body.setInertia(bullet, Infinity)
  # Body.setAngle(bullet, degToRad(180d))

  # constraint = Constraint.create(JsObject{pointA: jsVector(400, 300), bodyB: bullet, length: 30, stiffness: 0.1})

  ground = Bodies.rectangle(canvas.clientWidth / 2, 
    canvas.clientHeight + (groundHeight div 2), canvas.clientWidth * 1000, 
    groundHeight, JsObject{isStatic: true}
  ) # 350, 495, 1200

  thingy = Bodies.rectangle(500, 350, 20, 80, JsObject{isStatic: false, plugin: JsObject{wrap: wrapObject()}})

  mouse = Mouse.create(canvas)
  mconstraint = MouseConstraint.create(engine, JsObject{mouse: mouse})

  Composite.add(engine.world, toJs [bullet, mconstraint,
    # Walls
     Bodies.rectangle(350, -200, 1000, 20, JsObject{isStatic: true}), # up
    # Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}), # right
    ground, # down
    # Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}), # left
    thingy,

  ])

  # Set event callbacks
  Events.on(engine, "afterUpdate", proc() =
    # So that it updates the formula values
    if not kxi.surpressRedraws: redraw(kxi)
  )

  Events.on(engine, "collisionStart", proc(event: JsObject) = 
    if exerciseStatus == esStarted and event.pairs[0].bodyA.id == bullet.id:
      exerciseStatus = esEnd
  )


  Events.on(mrender, "afterRender", proc() =
    Render.startViewTransform(mrender)
    mrender.context.globalAlpha = 0.7

    for i in trail:
      mrender.context.fillStyle = cstring"orange"
      mrender.context.fillRect(JsObject(i).x, JsObject(i).y, 2, 2)

    if exerciseStatus == esStarted:
      let pos = bullet.position
      drawArrow(mrender.context, pos.x, pos.y, pos.x + (bullet.velocity.x * toJs 5), pos.y + (bullet.velocity.y * toJs 5), toJs 5, toJs cstring"white")

    mrender.context.globalAlpha = 1
    Render.endViewTransform(mrender)
  )

## Reloads the simulation
proc reload() =
  Composite.clear(engine.world)
  Engine.clear(engine)
  Render.stop(mrender)
  Runner.stop(runner)
  trail.setLen(0)
  load()

## Since a body's angle can be negative and can be higher than 360, this procedure makes it so it's always positive and inside 0..359
proc normalizeAngle(rad: float): int =
  result = int rad.radToDeg()
  result -= (result div 360) * 360 # Remove excess rotations
  # echo result
  if result < 0:
    result = abs result
  elif result > 0:
    result = 360 - result
  # echo "final ", result

## Since matter measures y from the top of the screen, here we "normalize" it so that the 0 starts at the ground
proc normalizeY(y: int): int =
  -y + (ground.position.y.to(int) - (groundHeight div 2) - bullet.circleRadius.to(int))

proc sendBulletFlying(changeStatus = true) =
  if paused: return

  if changeStatus:
    exerciseStatus = esStarted

  # let speed = bullet.circleRadius.to(float64) * 0.48 # force magnitude
  let exercise = exercises[curExercise]

  # Invert velocity y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVector(exercise.velocity.x / 2.5, -exercise.velocity.y / 2.5))

proc rotateBullet(clockwise = true) =
  if paused: return

  var rad = degToRad(20d)#(360 / bullet.vertices.length.to(float64))*2)
  if not clockwise:
    rad = -rad

  Body.rotate(bullet, rad)

  curExercise = 0
  exercises[0].angle = normalizeAngle(bullet.angle.to(float))
  exercises[0].angleRad = degToRad(float exercises[0].angle)
  exercises[0].velocity = speedToVelRad(float exercises[0].speed, exercises[0].angleRad)

proc calcTrajectory() {.async.} =
  var stop = false # Stop updating the engine
  # let bodies = cloneAllBodies(engine.world)
  let e = exercises[curExercise]
  #let g = engine.gravity.y.to(float) * engine.gravity.scale.to(float)
  let oldb = bullet.structuredClone()
  # print bullet.jsonStringify()

  var formerStaticBodies: seq[JsObject]
  for body in Composite.allBodies(engine.world):
    if body.id != bullet.id:
      if body.isStatic.to(bool) == true:
        formerStaticBodies.add body.id
      else:
        Body.setStatic(body, true)

  proc onCollision(event: JsObject) =
    if event.pairs[0].bodyA.id == bullet.id:
      stop = true

  Events.on(engine, "collisionStart", onCollision)

  sendBulletFlying(changeStatus = false)

  trail.setLen(0)
  for i in 1..500:
    if stop:
      exerciseTotalTime = (2 * e.velocity.y) / 9.8 #i.float * secPerTick
      exerciseStatus = esEnd
      break

    trail.add JsVector JsObject{x: jsFloatToInt bullet.position.x, y: jsFloatToInt bullet.position.y}

    Engine.update(engine)

  Events.off(engine, "collitionStart", onCollision)

  for b in [bullet]:#enumerate Composite.allBodies(engine.world):
    # assert b.id == bodies[e].id
    # let oldb = bodies[e]
    # Object.assign(b, oldb)

    b.force = oldb.force
    b.torque = oldb.torque
    b.positionImpulse = oldb.positionImpulse
    b.constraintImpulse = oldb.constraintImpulse
    b.positionPrev = oldb.positionPrev
    # Body.setParts(b, oldb.parts)# b.parts = oldb.parts
    # Body.setVertices(b, oldb.vertices)# b.vertices = oldb.vertices
    # b.bounds = oldb.bounds

    Body.setPosition(b, oldb.position)
    Body.setAngle(b, oldb.angle)
    Body.setVelocity(b, oldb.velocity)
    Body.setAngularVelocity(b, oldb.angularVelocity)

  for body in Composite.allBodies(engine.world):
    if body.id != bullet.id and body.id notin formerStaticBodies:
      Body.setStatic(body, false)

  # print bullet.jsonStringify()#Composite.allBodies(engine.world).jsonStringify()

proc renderTextDiv*(): VNode =
  buildHtml tdiv(style = "".toCss):
    p(text r"\(t_f = \frac{2 \cdot v_i \cdot \sin(\theta)}{g}\)", style = "font-size: 50px;".toCss)

    if not bullet.isNil:
      p(text &"x = {int bullet.position.x.to(float)} y = {normalizeY(int bullet.position.y.to(float))}")
      p(text &"angle = {normalizeAngle(bullet.angle.to(float))}")

      let exercise = exercises[curExercise]
      p(text &"Vi = {exercise.speed}")
      p(text &"t = {exerciseTotalTime:.2f}")

    # p(text fmt"\(a = \frac{{v_f - {bullet.position.x}}}{{\Delta t}}\)", style = "font-size: 80px;".toCss)

proc renderSimDiv*(): VNode =
  proc exerciseOnClick(current: int): proc =
    proc () =
      let exercise = exercises[current]
      curExercise = current
      Body.setPosition(bullet, jsVector(exercise.pos.x, normalizeY(exercise.pos.y)))
      Body.setAngle(bullet, degToRad(float(360 - exercise.angle)))
      discard calcTrajectory()
      exerciseStatus = esStart

  buildHtml tdiv(style = "".toCss):
    button():
      #text "Pause/Resume"
      if engine.isNil:
          span(class = "material-symbols-outlined", text "play_pause")
      else:
        if paused:
          span(class = "material-symbols-outlined", text "play_arrow")
        else:
          span(class = "material-symbols-outlined", text "pause")

      proc onclick()  =
        if paused:
          engine.timing.timeScale = timeScale
        else:
          engine.timing.timeScale = 0
    
        paused = not paused

    button():
      span(class = "material-symbols-outlined", text "rotate_left")
      proc onclick() =
        rotateBullet(clockwise = false)
        discard calcTrajectory()

    button():
      span(class = "material-symbols-outlined", text "rotate_right")
      proc onclick() =
        rotateBullet()
        discard calcTrajectory()

    button():
      verbatim parabolaIconSvg
      #img(src = "/public/img/parabola.svg", alt = "Parabola Trajectory")
      proc onclick() = discard calcTrajectory()
      #text "Trajectory"


    button():
      span(class = "material-symbols-outlined", text "north_east")
      proc onclick() =
        sendBulletFlying()

    br()

    #canvas(id = "canvas", style = fmt"width: {canvasWidth}px; height: {canvasHeight}px; background: rgb(20, 21, 31)".toCss):
    canvas(id = "canvas", style = fmt"width: 50vw; min-width: 300px; height: 50vh; min-height: 100px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

    tdiv(id = "exercises", style = "min-height: 0px; overflow-y: auto;".toCss):
      for e, exercise in exercises:
        if e == 0: continue # First exercise is the default exercise

        tdiv(style = "display: block;".toCss):
          button(onclick = exerciseOnClick(e)):
            text &"#{e} angle = {exercise.angle} vi = {exercise.speed} pos = ({exercise.pos.x}, {exercise.pos.x})"

proc render*(): VNode =
  buildHtml tdiv(style = "display: flex; flex-flow: column wrap; justify-content: start; align-items: center;".toCss):
    renderTextDiv()
    renderSimDiv()

window.addEventListener("resize", proc(event: Event) = 
  mrender.canvas.width = canvas.clientWidth
  mrender.canvas.height = canvas.clientHeight

  bullet.plugin.wrap = wrapObject()
  thingy.plugin.wrap = wrapObject()

  Body.setPosition(ground, JsObject{x: canvas.clientWidth / 2, y: canvas.clientHeight + (groundHeight div 2)})
)

document.addEventListener("keyup", proc(event: Event) =
  let event = KeyboardEvent(event)
  case $event.key
  of "t":
    discard calcTrajectory()
  of "ArrowRight":
    rotateBullet()
    discard calcTrajectory()
  of "ArrowLeft":
    rotateBullet(false)
    discard calcTrajectory()
  of "ArrowUp":
    sendBulletFlying()
  of "Backspace":
    reload()
  of "p":
    if paused:
      engine.timing.timeScale = timeScale
    else:
      engine.timing.timeScale = 0

    paused = not paused
  of "r":
    let exercise = exercises[curExercise]
    Body.setPosition(bullet, jsVector(exercise.pos.x, normalizeY(exercise.pos.y)))
    Body.setAngle(bullet, degToRad(float(360 - exercise.angle)))
    discard calcTrajectory()
    exerciseStatus = esStart
  of "d":
    jsonPrint bullet
)


