import std/[math, jsffi, dom, jsconsole, enumerate, with, strformat, asyncjs, algorithm]
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

const
  fps = 60
  delta = 1000 / fps # 60fps, 60 times in one second (1000 milliseconds)
  timeScale = 0.4

  canvasWidth = 700
  canvasHeight = 500

  groundHeight = 20

  canonWidth = 120
  canonHeight = 70
  canonX = canonWidth
  canonY = canvasHeight - groundHeight - canonHeight
  canonRotationDeg = 20d
  canonInitialSpeed = 12
  canonTexture = "/public/img/canon.png"

  trajectoryColor = "orange"

  velocityVectorScale = 8

let
  canonPivot = JsObject{x: canonX  - (canonWidth / 2), y: canonY}

proc initParabolaState*(): ParabolaState = 
  ParabolaState(canon: Canon(
    bulletRadius: 20, state: initCanonState(0, canonInitialSpeed), 
    bulletOptions: JsObject{
      isStatic: false, frictionAir: 0, friction: 1, 
    },
  ))

proc `bullet`(canon: Canon): JsObject = 
  assert canon.currentBullet in canon.bullets.low..canon.bullets.high, &"Invalid bullet index {canon.currentBullet}"
  canon.bullets[canon.currentBullet]

proc wrapObject(state: ParabolaState): JsObject = 
  JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: state.canvas.clientWidth, y: undefined}} # To avoid boilerplate

#proc `bullet`(state: var CanonState): var JsObject = 
#  state.bullets[state.currentBullet]

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

proc rotate(canon: var Canon, rad = degToRad(canonRotationDeg)) =
  Body.rotate(canon.body, rad, canonPivot)

  canon.state.angleDeg = normalizeAngle(canon.body.angle.to(float))
  canon.state.angleRad = degToRad(float canon.state.angleDeg)
  canon.state.velocity = speedToVelRad(float canon.state.speed, canon.state.angleRad)

proc rotateBack(canon: var Canon, rad = degToRad(canonRotationDeg)) =
  canon.rotate(-rad)

proc nextBulletPosition(state: ParabolaState): JsVector = 
  let vertice1 = state.canon.body.vertices[1]
  let vertice2 = state.canon.body.vertices[2]
  jsVector((vertice1.x + vertice2.x) / toJs 2, (vertice1.y + vertice2.y) / toJs 2)

proc nextBullet(state: var ParabolaState): JsObject = 
  let pos = JsObject state.nextBulletPosition()
  result = Bodies.circle(
    pos.x, pos.y, 
    state.canon.bulletRadius, state.canon.bulletOptions
  )

  #Body.setInertia(result, Infinity)
  #echo (stateAngle: state.canon.state.angleDeg, state)
  Body.setAngle(result, state.canon.state.angleDeg)

proc calcTrajectory(state: var ParabolaState) =
  let bullet = state.nextBullet()
  let gx = to(state.engine.gravity.x * state.engine.gravity.scale, float)
  let gy = to(state.engine.gravity.y * state.engine.gravity.scale, float)
  let velocity = state.canon.state.velocity

  # Invert velocity y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVector(velocity.x, -velocity.y))

  state.canon.trajectory.setLen(0)
  var i = 0
  while i < 100:
    state.canon.trajectory.add JsVector JsObject{x: jsFloatToInt bullet.position.x, y: jsFloatToInt bullet.position.y}

    bullet.force.x += bullet.mass * toJs gx
    bullet.force.y += bullet.mass * toJs gy
    Body.update(bullet)
    bullet.force.x = 0
    bullet.force.y = 0
    bullet.torque = 0

    inc i

proc loadEvents(state: var ParabolaState) = 
  Events.on(state.mouseConstraint, "mousedown", proc(event: JsObject) = 
    if Bounds.contains(state.canon.body.bounds, event.mouse.position).to(bool):
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
      state.canon.rotate(to(targetAngle - state.canon.body.angle, float))
      state.calcTrajectory()
  )

  Events.on(state.engine, "collisionStart", proc(event: JsObject) = 
    if state.canon.bullets.len > 0 and state.canon.status == csFlight:
      for pair in items(event.pairs):
        if pair.bodyA.id == state.canon.bullet.id or pair.bodyB.id == state.canon.bullet.id:
          state.canon.status = csHit
          break
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
        pos.x,
        pos.y + (state.canon.bullet.velocity.y * toJs velocityVectorScale), 
        toJs 4, toJs cstring"red"
      )

      drawArrow(state.render.context, pos.x, pos.y, 
        pos.x + (state.canon.bullet.velocity.x * toJs velocityVectorScale), 
        pos.y,
        toJs 4, toJs cstring"blue"
      )

      #drawArrow(state.render.context, pos.x, pos.y, 
      #  pos.x + (state.canon.bullet.velocity.x * toJs 9), 
      #  pos.y + (state.canon.bullet.velocity.y * toJs 9), 
      #  toJs 4, toJs cstring"white"
      #)

    state.render.context.globalAlpha = 1
    Render.endViewTransform(state.render)
  )

  Events.on(state.engine.world, "afterAdd", proc() =
    state.engine.world.bodies = state.engine.world.bodies.to(seq[JsObject]).sorted(proc(a, b: JsObject): int =
      to(a.collisionFilter.category - b.collisionFilter.category, int)
    )
  )

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

  state.runner = Runner.create(JsObject{delta: delta})
  Runner.run(state.runner, state.engine)

  # Create and add all bodies to the world
  state.canon.bulletOptions.plugin = JsObject{wrap: state.wrapObject()}

  state.canon.body = Bodies.rectangle(canonX, canonY, canonWidth, canonHeight, JsObject{
    isStatic: true, collisionFilter: JsObject{category: 0x2, mask: 0}, label: cstring"Canon",
    render: JsObject{sprite: JsObject{
      texture: cstring canonTexture, 
      xOffset: 0, yOffset: 0
    }}
  })
  state.canon.rotateBack(degToRad(60d))
  #constraint = Constraint.create(JsObject{pointA: jsVector(0, 0), bodyB: canon})#, length: 30, stiffness: 0.1})

  state.ground = Bodies.rectangle(state.canvas.clientWidth / 2, 
    state.canvas.clientHeight + (groundHeight div 2), state.canvas.clientWidth * 1000, 
    groundHeight, JsObject{isStatic: true, label: cstring"Groubd"}
  ) # 350, 495, 1200

  state.thingy = Bodies.rectangle(500, 350, 20, 80, JsObject{isStatic: false, label: cstring"Thingy", plugin: JsObject{wrap: state.wrapObject}})

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

  state.loadEvents()

## Reloads the simulation
proc reload*(state: var ParabolaState) =
  Composite.clear(state.engine.world)
  Engine.clear(state.engine)
  Render.stop(state.render)
  Runner.stop(state.runner)
  state.canon.trajectory.setLen(0)
  state.load()

## Since matter measures y from the top of the screen, here we "normalize" it so that the 0 starts at the ground
proc normalizeY(state: ParabolaState, y: int, height: int): int =
  -y + (state.ground.position.y.to(int) - (groundHeight div 2) - height)

proc fireBullet(state: var ParabolaState) = 
  let bullet = state.nextBullet()

  Composite.add(state.engine.world, bullet)
  state.canon.bullets.add bullet
  state.canon.currentBullet = state.canon.bullets.high

  state.canon.status = csFlight

  let velocity = state.canon.state.velocity

  # Invert velocity y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVector(velocity.x, -velocity.y))

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
    y = state.normalizeY(int bullet.position.y.to(float), bullet.circleRadius.to(int))
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
        state.canon.rotateBack()
        state.calcTrajectory()

    button():
      span(class = "material-symbols-outlined", text "rotate_right")
      proc onclick() =
        state.canon.rotate()
        state.calcTrajectory()

    #button():
    #  verbatim parabolaIconSvg
    #  #img(src = "/public/img/parabola.svg", alt = "Parabola Trajectory")
    #  proc onclick() = calcTrajectory()
    #  #text "Trajectory"

    button():
      span(class = "material-symbols-outlined", text "north_east")
      proc onclick() =
        state.fireBullet()

    br()

    #canvas(id = "canvas", style = fmt"width: {canvasWidth}px; height: {canvasHeight}px; background: rgb(20, 21, 31)".toCss):
    canvas(id = "canvas", style = fmt"width: 50vw; min-width: 300px; height: 50vh; min-height: 300px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

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
      state.calcTrajectory()
    of "ArrowRight":
      state.canon.rotate()
      state.calcTrajectory()
    of "ArrowLeft":
      state.canon.rotateBack()
      state.calcTrajectory()
    of "ArrowUp", " ":
      state.fireBullet()
    of "Backspace":
      state.reload()
    of "p":
      state.togglePause()
    #of "r":
    #  let exercise = exercises[curExercise]
    #  let bullet = bullets[currentBullet]
    #  Body.setPosition(bullet, jsVector(exercise.pos.x, state.normalizeY(exercise.pos.y)))
    #  Body.setAngle(bullet, degToRad(float(360 - exercise.angle)))
    #  calcTrajectory()
    #  exerciseStatus = csReady
    of "d":
      echo state
      print state.canon.bullet
  )
