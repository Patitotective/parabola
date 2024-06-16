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
    speed*: float
    velocity*: tuple[x, y: float]

  CanonBase = object
    x*, y*: int
    img*: JsObject
    isDragging*: bool

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

    y*: int
    pivot*: JsObject
    base*: CanonBase
    platform*: CanonPlatform
    elevated*: bool

  CanonPlatform = object
    img*: JsObject
    y*: int

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

    bounds*: JsObject
    boundsScale*: JsObject
    boundsScaleTarget*: float

proc initCanonState(angleDeg: int, speed: float): CanonState = 
  let angleRad = degToRad(float angleDeg)
  CanonState(angleDeg: angleDeg, angleRad: angleRad, speed: speed, velocity: speedToVelRad(speed, angleRad))

proc initCanonState(angleRad: float, speed: float): CanonState = 
  let angleDeg = int radToDeg(angleRad)
  CanonState(angleDeg: angleDeg, angleRad: angleRad, speed: speed, velocity: speedToVelRad(speed, angleRad))

const
  fps = 60
  delta = 1000 / fps # 60fps, 60 times in one second (1000 milliseconds)
  timeScale = 0.6

  #canvasWidth = 700
  #canvasHeight = 500

  groundHeight = 10

  canonWidth = 120
  canonHeight = 70
  canonX = canonWidth
  canonInitialSpeed = 12
  canonSpeedChange = 1
  canonAngleChangeDeg = 5d
  canonTexture = "/public/img/canon.png"
  
  canonBaseImgPath = "/public/img/canonBase.png"

  trajectoryColor = "orange"

  velocityVectorScale = 9

proc wrapObject(state: ParabolaState): JsObject = 
  JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: state.canvas.clientWidth, y: undefined}} # To avoid boilerplate

## Since a body's angle can be negative and can be higher than 360, this procedure makes it so it's always positive and inside 0..359
proc normalizeAngle(rad: float): int =
  result = int rad.radToDeg()
  result -= (result div 360) * 360 # Remove excess rotations

  if result < 0:
    result = abs result
  elif result > 0:
    result = 360 - result

proc rotate(canon: var Canon, rad = degToRad(canonAngleChangeDeg), limit = true) =
  if limit and normalizeAngle(canon.body.angle.to(float) + rad) notin 20..160:
    #echo &"Invalid angle ", (deg: normalizeAngle(canon.body.angle.to(float) + rad), rad: canon.body.angle.to(float) + rad)
    return

  Body.rotate(canon.body, rad, canon.pivot)

  canon.state.angleDeg = normalizeAngle(canon.body.angle.to(float))
  canon.state.angleRad = degToRad(float canon.state.angleDeg)
  canon.state.velocity = speedToVelRad(canon.state.speed, canon.state.angleRad)

proc rotateBack(canon: var Canon, rad = degToRad(canonAngleChangeDeg), limit = true) =
  canon.rotate(-rad, limit)

proc updatePos(canon: var Canon) =
  let prevAngle = canon.body.angle.to(float) 
  canon.rotate(-prevAngle, limit = false)
  Body.setPosition(canon.body, JsObject{x: canonX, y: canon.y})
  canon.rotate(prevAngle, limit = false)

proc setSpeed(canon: var Canon, speed: float) = 
  canon.state.speed = clamp(speed, 8.0..18.0)
  canon.state.velocity = speedToVelRad(canon.state.speed, canon.state.angleRad)  

proc onResize(state: var ParabolaState) = 
  #echo "before: ", (canonX: canonX, state.canon.y: state.canon.y)
  #jsonPrint state.canon.body

  state.render.canvas.width = state.canvas.clientWidth
  state.render.canvas.height = state.canvas.clientHeight

  if not state.canon.elevated:
    state.canon.y = state.canvas.clientHeight - groundHeight - int(state.canon.base.img.height.to(float) * 0.5)
    state.canon.pivot = JsObject{x: canonX  - (canonWidth / 2.5), y: state.canon.y}

    state.canon.base.x = state.canon.pivot.x.to(float).int - state.canon.base.img.width.to(float).int div 2
    state.canon.base.y = state.canvas.clientHeight - groundHeight - state.canon.base.img.height.to(float).int
  
    state.canon.updatePos()

  Body.setPosition(state.ground, JsObject{x: state.canvas.clientWidth / 2, y: state.canvas.clientHeight - (groundHeight div 2)})

  let wrap = state.wrapObject()

  state.canon.bulletOptions.plugin = JsObject{wrap: wrap}

  for bullet in state.canon.bullets:
    bullet.plugin.wrap = wrap

  state.thingy.plugin.wrap = wrap

  #echo "after: ", (canonX: canonX, state.canon.y: state.canon.y)
  #jsonPrint state.canon.body

proc initParabolaState*(): ParabolaState = 
  result = ParabolaState(
    boundsScale: JsObject{x: 1, y: 1},
    boundsScaleTarget: 1, 
    canon: Canon(
      bulletRadius: 20, state: initCanonState(0, canonInitialSpeed), 
      bulletOptions: JsObject{
        isStatic: false, frictionAir: 0, friction: 1, 
      }, base: CanonBase(img: newImage())
  ))

  result.canon.base.img.src = cstring canonBaseImgPath

proc `bullet`(canon: Canon): JsObject = 
  assert canon.currentBullet in canon.bullets.low..canon.bullets.high, &"Invalid bullet index {canon.currentBullet}"
  canon.bullets[canon.currentBullet]

#proc `bullet`(state: var CanonState): var JsObject = 
#  state.bullets[state.currentBullet]

proc nextBullet(state: var ParabolaState): JsObject = 
  result = Bodies.circle(
    state.canon.pivot.x, state.canon.pivot.y, 
    state.canon.bulletRadius, state.canon.bulletOptions
  )

  Body.setAngle(result, state.canon.state.angleDeg)

proc calcTrajectory(state: var ParabolaState) =
  let bullet = state.nextBullet()
  bullet.plugin = JsObject{wrap: state.wrapObject()}

  let gx = to(state.engine.gravity.x * state.engine.gravity.scale, float)
  let gy = to(state.engine.gravity.y * state.engine.gravity.scale, float)
  let v = state.canon.state.velocity

  # Invert velocity y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVector(v.x, -v.y))

  state.canon.trajectory.setLen(0)
  var i = 0
  while i < 6000:
    if bullet.position.y.to(float).int > state.canvas.clientHeight - groundHeight:
      break

    MatterWrap.Body.wrap(bullet, bullet.plugin.wrap)

    let x = bullet.position.x
    let y = bullet.position.y

    state.canon.trajectory.add JsVector JsObject{x: jsFloatToInt x, y: jsFloatToInt y}

    bullet.force.x += bullet.mass * toJs gx
    bullet.force.y += bullet.mass * toJs gy
    Body.update(bullet)
    bullet.force.x = 0
    bullet.force.y = 0
    bullet.torque = 0

    inc i

proc loadEvents(state: var ParabolaState) = 
  Events.on(state.mouseConstraint, "mousedown", proc(event: JsObject) = 
    let baseBounds = JsObject{
      min: JsObject{
        x: state.canon.base.x.float / 1.3, y: state.canon.base.y.float
      }, 
      max: JsObject{
        x: float(state.canon.base.x + state.canon.base.img.width.to(float).int) * 1.1, 
        y: (state.canon.base.y + state.canon.base.img.height.to(float).int)
      }, 
    }

    print baseBounds

    if event.mouse.button == 0.toJs:
      if Bounds.contains(baseBounds, event.mouse.position).to(bool):
        state.canon.base.isDragging = true

      elif Bounds.contains(state.canon.body.bounds, event.mouse.position).to(bool): 
        state.canon.isDragging = true
  )

  Events.on(state.mouseConstraint, "mouseup", proc(event: JsObject) = 
    state.canon.isDragging = false
    state.canon.base.isDragging = false
  )

  state.mouse.element.addEventListener("wheel", proc(event: JsObject) = 
    let wheelDelta = event.wheelDelta.to(float)
    #let distance = Vector.sub(state.canon.pivot, state.mouse.position)
    #let magnitude = Vector.magnitude(distance).to(float)
    #state.canon.setSpeed(float int (canonInitialSpeed / 100) * magnitude)
    if wheelDelta != 0:
      state.canon.setSpeed(state.canon.state.speed + (wheelDelta / 120))
      state.calcTrajectory()
  )

  #TODO: move afterUpdate to mousemove

  # Set event callbacks
  Events.on(state.engine, "afterUpdate", proc() =
    # So that it updates the formula values
    #if not kxi.surpressRedraws: redraw(kxi) # TODO: REALLY INEFFICIENT
    if state.canon.base.isDragging:
      let mousey = int state.mouse.position.y.to(float)# / 1.1
      # It is canonMax even though it's the lowest point since matter counts y zero from the top
      let canonMax = state.canvas.clientHeight - groundHeight - int(state.canon.base.img.height.to(float) * 0.5)
      let canonMin = canonHeight + int(state.canon.base.img.height.to(float) * 0.5) # We add half the base height since the canon is always lower than the base
      state.canon.y = clamp(mousey + int(state.canon.base.img.height.to(float) * 0.5), canonMin, canonMax)
  
      state.canon.elevated = state.canon.y != canonMax

      state.canon.pivot = JsObject{x: canonX  - (canonWidth / 2.5), y: state.canon.y}

      # It is baseMax even though it's the lowest point since matter counts y zero from the top
      let baseMax = state.canvas.clientHeight - groundHeight - state.canon.base.img.height.to(float).int
      state.canon.base.y = clamp(mousey, canonHeight, baseMax)
      
      state.canon.updatePos()

      state.calcTrajectory()

    elif state.canon.isDragging:
      let targetAngle = Vector.angle(state.canon.pivot, state.mouse.position)
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
  Events.on(state.render, "beforeRender", proc() =
    return
    let mouse = state.mouseConstraint.mouse
    var scaleFactor = mouse.wheelDelta.to(float) * -0.1

    if state.boundsScaleTarget + scaleFactor >= 1 and 
      (scaleFactor < 0 and state.boundsScale.x.to(float) >= 0.6 or 
        scaleFactor > 0 and state.boundsScale.x.to(float) <= 1.4):
      state.boundsScaleTarget += scaleFactor

    # if scale has changed
    if abs(state.boundsScale.x.to(float) - state.boundsScaleTarget) > 0.01:
      # smoothly tween scale factor
      scaleFactor = (state.boundsScaleTarget - state.boundsScale.x.to(float)) * 0.2
      state.boundsScale.x += toJs scaleFactor
      state.boundsScale.y += toJs scaleFactor

      # scale the render bounds
      state.render.bounds.max.x = state.render.bounds.min.x + state.render.options.width.toJs * state.boundsScale.x
      state.render.bounds.max.y = state.render.bounds.min.y + state.render.options.height.toJs * state.boundsScale.y

      # translate so zoom is from centre of view
      let translate = JsObject{
        x: state.render.options.width.to(float) * scaleFactor * -0.5,
        y: state.render.options.height.to(float) * scaleFactor * -0.5
      }

      Bounds.translate(state.render.bounds, translate)

      # update mouse
      Mouse.setScale(mouse, state.boundsScale)
      Mouse.setOffset(mouse, state.render.bounds.min)

    # get vector from mouse relative to centre of viewport
    var viewportCentre = JsObject{
      x: state.render.options.width * toJs 0.5,
      y: state.render.options.height * toJs 0.5
    }
    let deltaCentre = Vector.sub(mouse.absolute, viewportCentre)
    let centreDist = Vector.magnitude(deltaCentre)

    # translate the view if mouse has moved over 50px from the centre of viewport
    if centreDist.to(float) > 50:
      # create a vector to translate the view, allowing the user to control view speed
      let direction = Vector.normalise(deltaCentre)
      let speed = min(10, pow(centreDist.to(float) - 50, 2) * 0.0002)

      let translate = Vector.mult(direction, speed)

      # prevent the view moving outside the extens (bounds)
      if to(state.render.bounds.min.x + translate.x < state.bounds.min.x, bool):
        translate.x = state.bounds.min.x - state.render.bounds.min.x

      if to(state.render.bounds.max.x + translate.x > state.bounds.max.x, bool):
        translate.x = state.bounds.max.x - state.render.bounds.max.x

      if to(state.render.bounds.min.y + translate.y < state.bounds.min.y, bool):
        translate.y = state.bounds.min.y - state.render.bounds.min.y

      if to(state.render.bounds.max.y + translate.y > state.bounds.max.y, bool):
        translate.y = state.bounds.max.y - state.render.bounds.max.y

      # move the view
      Bounds.translate(state.render.bounds, translate)

      # we must update the mouse too
      Mouse.setOffset(mouse, state.render.bounds.min)
  )

  Events.on(state.render, "afterRender", proc() =
    Render.startViewTransform(state.render)

    let ctx = state.render.context

    if state.canon.base.img.complete.to(bool):
      ctx.drawImage(state.canon.base.img, state.canon.base.x, state.canon.base.y)

    if state.canon.bullets.len > 0 and state.canon.status == csFlight:
      let pos = state.canon.bullet.position

      drawArrow(ctx, pos.x, pos.y, 
        pos.x,
        pos.y + (state.canon.bullet.velocity.y * toJs velocityVectorScale), 
        toJs 4, toJs cstring"red"
      )

      drawArrow(ctx, pos.x, pos.y, 
        pos.x + (state.canon.bullet.velocity.x * toJs velocityVectorScale), 
        pos.y,
        toJs 4, toJs cstring"lightblue"
      )

      #drawArrow(ctx, pos.x, pos.y, 
      #  pos.x + (state.canon.bullet.velocity.x * toJs 9), 
      #  pos.y + (state.canon.bullet.velocity.y * toJs 9), 
      #  toJs 4, toJs cstring"white"
      #)

    ctx.globalAlpha = 0.7

    for p in state.canon.trajectory:
      ctx.fillStyle = cstring trajectoryColor
      ctx.fillRect(JsObject(p).x, JsObject(p).y, 2, 2)

    ctx.globalAlpha = 1

    Render.endViewTransform(state.render)
  )

  ## Sort bodies by z-index/depth
  Events.on(state.engine.world, "afterAdd", proc() =
    state.engine.world.bodies = state.engine.world.bodies.to(seq[JsObject]).sorted(proc(a, b: JsObject): int =
      let z1 = if a.zIndex.isNil: 0 else: a.zIndex.to(float).int
      let z2 = if b.zIndex.isNil: 0 else: b.zIndex.to(float).int
      z1 - z2
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

  state.bounds = JsObject{min: JsObject{x: 0, y: 0}, max: JsObject{x: state.canvas.clientWidth.float * 0.6, y: state.canvas.clientHeight.float * 0.5}}

  # Create and add all bodies to the world
  state.canon.body = Bodies.rectangle(canonX, state.canon.y, canonWidth, canonHeight, JsObject{
    zIndex: 1, isStatic: true, collisionFilter: JsObject{mask: 0}, label: cstring"Canon",
    render: JsObject{sprite: JsObject{
      texture: cstring canonTexture, 
      xOffset: 0, yOffset: 0
    }}
  })
  #constraint = Constraint.create(JsObject{pointA: jsVector(0, 0), bodyB: canon})#, length: 30, stiffness: 0.1})

  # onResize will set the correct position
  state.ground = Bodies.rectangle(0, 0, state.canvas.clientWidth * 1000, 
    groundHeight, JsObject{zIndex: 10, isStatic: true, label: cstring"Ground"}
  ) # 350, 495, 1200

  state.thingy = Bodies.rectangle(500, 350, 20, 80, JsObject{isStatic: false, label: cstring"Thingy", plugin: JsObject{wrap: state.wrapObject}})

  state.mouse = Mouse.create(state.canvas)
  state.mouseConstraint = MouseConstraint.create(state.engine, JsObject{mouse: state.mouse, collisionFilter: JsObject{mask: 0}})
  state.render.mouse = state.mouse

  state.onResize()
  state.canon.rotateBack(degToRad(60d))

  state.calcTrajectory()

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
  state = initParabolaState()#.canon.trajectory.setLen(0)
  state.load()

## Since matter measures y from the top of the screen, here we "normalize" it so that the 0 starts at the ground
proc normalizeY(state: ParabolaState, y: int, height: int): int =
  -y + (state.ground.position.y.to(float).int - (groundHeight div 2) - height)

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
    y = state.normalizeY(int bullet.position.y.to(float), bullet.circleRadius.to(float).int)
    angle = normalizeAngle(bullet.angle.to(float))
    speed = int state.canon.state.speed

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

    canvas(id = "canvas", style = fmt"width: 100vw; min-width: 500px; height: 60vh; min-height: 300px; background: rgb(20, 21, 31)".toCss):
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
    state.onResize()
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
    of "ArrowUp":
      state.canon.setSpeed(state.canon.state.speed + canonSpeedChange)
      state.calcTrajectory()
    of "ArrowDown":
      state.canon.setSpeed(state.canon.state.speed - canonSpeedChange)
      state.calcTrajectory()
    of " ":
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
