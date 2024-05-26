import std/[math, jsffi, dom, jsconsole, enumerate, with, strformat, asyncjs]
import karax/[karax, karaxdsl, vdom, vstyles]

import matter, utils

type
  CanonStatus = enum
    csReady # Not launched yet
    csFlight # In the air
    csHit # Hit something and stopped

  CanonState = object
    angleDeg*: int
    angleRad*: float
    speed*: int
    velocity*: tuple[x, y: float]

  Canon = object
    body*: JsObject

    bullets*: seq[JsObject]
    currentBullet*: int
    bulletRadius*: int
    bulletOptions*: JsObject

    trajectory*: seq[JsVector]
    isDragging*: bool # Is the canon being dragged
    status*: CanonStatus
    state*: CanonState

  ParabolaState* = object
    engine*: JsObject
    render*: JsObject
    runner*: JsObject
    canvas*: Element

    paused*: bool

    mouseConstraint*: JsObject
    mouse*: JsObject

    canon*: Canon
    thingy*: JsObject
    ground*: JsObject

proc initCanonState(angleDeg: int, speed: int): CanonState = 
  let angleRad = degToRad(float angleDeg)
  CanonState(angleDeg: angleDeg, angleRad: angleRad, speed: speed, velocity: speedToVelRad(float speed, angleRad))

proc initCanonState(angleRad: float, speed: int): CanonState = 
  let angleDeg = int radToDeg(float angleRad)
  CanonState(angleDeg: angleDeg, angleRad: angleRad, speed: speed, velocity: speedToVelRad(float speed, angleRad))

proc initParabolaState*(): ParabolaState = 
  ParabolaState(canon: Canon(bulletRadius: 20, state: initCanonState(45,25)))

const
  deltaTime = 1000 / 60 # 60fps, 60 times in one second (1000 milliseconds)
  secPerFrame = 1 / 60
  timeScale = 0.5

  canvasWidth = 700
  canvasHeight = 500

  groundHeight = 20

  canonWidth = 100
  canonHeight = 50
  canonX = 100
  canonY = canvasHeight - groundHeight - canonHeight
  canonTexture = "/public/img/canon.png"

  trajectoryColor = "orange"

let
  canonPivot = JsObject{x: canonX  - (canonWidth / 2), y: canonY}

proc wrapObject(state: ParabolaState): JsObject = 
  JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: state.canvas.clientWidth, y: undefined}} # To avoid boilerplate

proc `bullet`(canon: Canon): JsObject = 
  assert canon.currentBullet in canon.bullets.low..canon.bullets.high, &"Invalid bullet index {canon.currentBullet}"
  canon.bullets[canon.currentBullet]

#proc `bullet`(state: var CanonState): var JsObject = 
#  state.bullets[state.currentBullet]

## Loads the simulation
proc load*(state: var ParabolaState) =
  # Render all MathJax expressions asynchronously
  MathJax.typesetPromise()

  # Load wrap's plugin and load matter aliases to point to the correct values
  Matter.use("matter-wrap")
  loadMatterAliases()

  state.canvas = getElementById("canvas")
  state.engine = createEngine(JsObject{gravity: JsObject{x: 0, y: 1, scale: 0.001}, timing: JsObject{timeScale: timeScale}})
  state.render = createRender(JsObject{
    canvas: state.canvas,
    engine: state.engine,
    options: JsObject{
      width: state.canvas.clientWidth,
      height: state.canvas.clientHeight,
      showAngleIndicator: false,
      showSleeping: false,
      wireframes: false,
      background: "transparent",#"rgb(20, 21, 31)",
    }
  })
  Render.run(state.render)

  state.runner = Runner.create(JsObject{delta: deltaTime})
  Runner.run(state.runner, state.engine)

  # Create and add all bodies to the world

  state.canon.body = Bodies.rectangle(canonX, canonY, canonWidth, canonHeight, JsObject{
    isStatic: true, collisionFilter: JsObject{mask: 0}, render: JsObject{sprite: JsObject{
      texture: cstring canonTexture, 
      xOffset: 0, yOffset: 0
    }}
  })
  #constraint = Constraint.create(JsObject{pointA: jsVector(0, 0), bodyB: canon})#, length: 30, stiffness: 0.1})

  state.ground = Bodies.rectangle(state.canvas.clientWidth / 2, 
    state.canvas.clientHeight + (groundHeight div 2), state.canvas.clientWidth * 1000, 
    groundHeight, JsObject{isStatic: true}
  ) # 350, 495, 1200

  state.thingy = Bodies.rectangle(500, 350, 20, 80, JsObject{isStatic: false, plugin: JsObject{wrap: state.wrapObject}})

  state.mouse = Mouse.create(state.canvas)
  state.mouseConstraint = MouseConstraint.create(state.engine, JsObject{mouse: state.mouse, collisionFilter: JsObject{mask: 0}})

  Composite.add(state.engine.world, toJs [state.canon.body, state.mouseConstraint,
    state.thingy,
    # Walls
     Bodies.rectangle(350, -200, 1000, 20, JsObject{isStatic: true}), # up
    # Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}), # right
    state.ground, # down
    # Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}), # left
  ])

  Events.on(state.mouseConstraint, "mousedown", proc(event: JsObject) = 
    if Bounds.contains(state.canon.body.bounds, event.mouse.position).to(bool):# and event.mouse.button == toJs 0:
      state.canon.isDragging = true
  )


  Events.on(state.mouseConstraint, "mouseup", proc(event: JsObject) = 
    state.canon.isDragging = false
  )

  # Set event callbacks
  Events.on(state.engine, "afterUpdate", proc() =
    # So that it updates the formula values
    #if not kxi.surpressRedraws: redraw(kxi) # TODO: REALLY INEFFICIENT
    if state.canon.isDragging:
      let targetAngle = Vector.angle(canonPivot, state.mouse.position)
      Body.rotate(state.canon.body, targetAngle - state.canon.body.angle, canonPivot)
  )

  Events.on(state.engine, "collisionStart", proc(event: JsObject) = 
    if state.canon.bullets.len > 0 and state.canon.status == csFlight and 
      event.pairs[0].bodyA.id == state.canon.bullet.id:
      state.canon.status = csHit
  )

  Events.on(state.render, "afterRender", proc() =
    Render.startViewTransform(state.render)
    state.render.context.globalAlpha = 0.7

    for p in state.canon.trajectory:
      state.render.context.fillStyle = cstring trajectoryColor
      state.render.context.fillRect(JsObject(p).x, JsObject(p).y, 2, 2)

    if state.canon.bullets.len > 0 and state.canon.status == csFlight:
      let pos = state.canon.bullet.position
      drawArrow(state.render.context, pos.x, pos.y, 
        pos.x + (state.canon.bullet.velocity.x * toJs 7), 
        pos.y + (state.canon.bullet.velocity.y * toJs 7), 
        toJs 4, toJs cstring"white"
      )

    state.render.context.globalAlpha = 1
    Render.endViewTransform(state.render)
  )

## Reloads the simulation
proc reload*(state: var ParabolaState) =
  Composite.clear(state.engine.world)
  Engine.clear(state.engine)
  Render.stop(state.render)
  Runner.stop(state.runner)
  state.canon.trajectory.setLen(0)
  state.load()

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
proc normalizeBulletY(state: ParabolaState, y: int, bulletRadius: int): int =
  -y + (state.ground.position.y.to(int) - (groundHeight div 2) - bulletRadius)

proc rotate(canon: var Canon, clockwise = true) =
  var rad = degToRad(20d)#(360 / bullet.vertices.length.to(float64))*2)
  if not clockwise:
    rad = -rad

  Body.rotate(canon.body, rad, canonPivot)

  canon.state.angleDeg = normalizeAngle(canon.body.angle.to(float))
  canon.state.angleRad = degToRad(float canon.state.angleDeg)
  canon.state.velocity = speedToVelRad(float canon.state.speed, canon.state.angleRad)

proc fireBullet(state: var ParabolaState) = 
  let min = state.canon.body.bounds.min
  let max = state.canon.body.bounds.max
  let bullet = Bodies.circle(max.x, min.y, state.canon.bulletRadius, state.canon.bulletOptions)

  #Body.setInertia(bullet, Infinity)
  #echo (stateAngle: state.canon.state.angleDeg, state)
  Body.setAngle(bullet, state.canon.state.angleDeg)

  Composite.add(state.engine.world, bullet)
  state.canon.bullets.add bullet
  state.canon.currentBullet = state.canon.bullets.high

  state.canon.status = csFlight

  let velocity = state.canon.state.velocity

  # Invert velocity y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVector(velocity.x / 2.5, -velocity.y / 2.5))

proc calcTrajectory(state: var ParabolaState) {.async.} =
  var stop = false # Stop updating the engine

  state.fireBullet()
  let bullet = state.canon.bullet

  #var formerStaticBodies: seq[JsObject]
  #for body in Composite.allBodies(engine.world):
  #  if body.id != bullet.id:
  #    if body.isStatic.to(bool) == true:
  #      formerStaticBodies.add body.id
  #    else:
  #      Body.setStatic(body, true)

  proc onCollision(event: JsObject) =
    if event.pairs[0].bodyA.id == bullet.id:
      stop = true

  Events.on(state.engine, "collisionStart", onCollision)

  state.canon.trajectory.setLen(0)
  for i in 1..500:
    if stop:
      #exerciseTotalTime = (2 * e.velocity.y) / 9.8 #i.float * secPerTick
      state.canon.status = csHit
      break

    state.canon.trajectory.add JsVector JsObject{x: jsFloatToInt bullet.position.x, y: jsFloatToInt bullet.position.y}

    Engine.update(state.engine)

  Events.off(state.engine, "collitionStart", onCollision)

  Composite.remove(state.engine.world, bullet)
  discard state.canon.bullets.pop()
  dec state.canon.currentBullet

  #for body in Composite.allBodies(engine.world):
  #  if body.id != bullet.id and body.id notin formerStaticBodies:
  #    Body.setStatic(body, false)

  # print bullet.jsonStringify()#Composite.allBodies(engine.world).jsonStringify()

proc togglePause(state: var ParabolaState) = 
  if state.paused:
    state.engine.timing.timeScale = timeScale
  else:
    state.engine.timing.timeScale = 0

  state.paused = not state.paused

proc renderTextDiv*(state: ParabolaState): VNode =
  var x, y, angle, speed: int

  if state.canon.bullets.len > 0:
    let bullet = state.canon.bullet

    x = int bullet.position.x.to(float)
    y = state.normalizeBulletY(int bullet.position.y.to(float), bullet.circleRadius.to(int))
    angle = normalizeAngle(bullet.angle.to(float))
    speed = state.canon.state.speed

  buildHtml tdiv(id = "text", style = "".toCss):
    p(text r"\(t_f = \frac{2 \cdot v_i \cdot \sin(\theta)}{g}\)", style = "font-size: 50px;".toCss)

    p(text &"x = {x} y = {y}")
    p(text &"angle = {angle}")

    p(text &"Vi = {speed}")
    #p(text &"t = {exerciseTotalTime:.2f}")

    # p(text fmt"\(a = \frac{{v_f - {bullet.position.x}}}{{\Delta t}}\)", style = "font-size: 80px;".toCss)

proc renderSimDiv*(state: var ParabolaState): VNode =
  buildHtml tdiv(id = "sim", style = "".toCss):
    button():
      #text "Pause/Resume"
      if state.engine.isNil:
          span(class = "material-symbols-outlined", text "play_pause")
      else:
        if state.paused:
          span(class = "material-symbols-outlined", text "play_arrow")
        else:
          span(class = "material-symbols-outlined", text "pause")

      proc onclick()  =
        state.togglePause()

    button():
      span(class = "material-symbols-outlined", text "rotate_left")
      proc onclick() =
        state.canon.rotate(clockwise = false)
        discard state.calcTrajectory()

    button():
      span(class = "material-symbols-outlined", text "rotate_right")
      proc onclick() =
        state.canon.rotate(clockwise = true)
        discard state.calcTrajectory()

    #button():
    #  verbatim parabolaIconSvg
    #  #img(src = "/public/img/parabola.svg", alt = "Parabola Trajectory")
    #  proc onclick() = discard calcTrajectory()
    #  #text "Trajectory"

    button():
      span(class = "material-symbols-outlined", text "north_east")
      proc onclick() =
        state.fireBullet()

    br()

    #canvas(id = "canvas", style = fmt"width: {canvasWidth}px; height: {canvasHeight}px; background: rgb(20, 21, 31)".toCss):
    canvas(id = "canvas", style = fmt"width: 50vw; min-width: 300px; height: 50vh; min-height: 300px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

#proc exerciseOnClick(current: int): proc =
#  proc () =
#    let exercise = exercises[current]
#    let bullet = bullets[currentBullet]

#    curExercise = current
#    Body.setPosition(bullet, jsVector(exercise.pos.x, state.normalizeBulletY(exercise.pos.y)))
#    Body.setAngle(bullet, degToRad(float(360 - exercise.angle)))
#    discard calcTrajectory()
#    exerciseStatus = csReady

proc render*(state: var ParabolaState): VNode =
  buildHtml tdiv(style = "display: flex; flex-direction: column; justify-content: start; align-items: center; height: 100%;".toCss):
    state.renderTextDiv()
    state.renderSimDiv()

    #tdiv(id = "exercises-wrapper", style = "flex: 0 0 auto; position: relative; min-width: 50vw;".toCss):
      #tdiv(id = "exercises", style = "position: absolute; top: 0; left: 0; right: 0; bottom: 0; overflow-y: auto;".toCss):
    #tdiv(id = "exercises", style = "flex: 1 1 auto; overflow-y: auto; min-height: 0px;".toCss):
    #  for e, exercise in exercises:
    #    if e == 0: continue # First exercise is the default exercise

    #    tdiv(style = "".toCss):
    #      button(onclick = exerciseOnClick(e)):
    #        text &"#{e} angle = {exercise.angle} vi = {exercise.speed} pos = ({exercise.pos.x}, {exercise.pos.x})"

proc addEventListeners*(state: var ParabolaState) = 
  window.addEventListener("resize", proc(event: Event) = 
    state.render.canvas.width = state.canvas.clientWidth
    state.render.canvas.height = state.canvas.clientHeight

    for bullet in state.canon.bullets:
      bullet.plugin.wrap = state.wrapObject

    state.thingy.plugin.wrap = state.wrapObject

    Body.setPosition(state.ground, JsObject{x: state.canvas.clientWidth / 2, y: state.canvas.clientHeight + (groundHeight div 2)})
  )

  document.addEventListener("keyup", proc(event: Event) =
    let event = KeyboardEvent(event)
    echo $event.key
    case $event.key
    of "t":
      discard state.calcTrajectory()
    of "ArrowRight":
      state.canon.rotate(clockwise = true)
      discard state.calcTrajectory()
    of "ArrowLeft":
      state.canon.rotate(clockwise = false)
      discard state.calcTrajectory()
    of "ArrowUp":
      state.fireBullet()
    of "Backspace":
      state.reload()
    of "p":
      state.togglePause()
    #of "r":
    #  let exercise = exercises[curExercise]
    #  let bullet = bullets[currentBullet]
    #  Body.setPosition(bullet, jsVector(exercise.pos.x, state.normalizeBulletY(exercise.pos.y)))
    #  Body.setAngle(bullet, degToRad(float(360 - exercise.angle)))
    #  discard calcTrajectory()
    #  exerciseStatus = csReady
    #of "d":
      echo state
  )
