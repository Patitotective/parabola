import std/[math, jsffi, times, dom, jsconsole, enumerate, with, strformat, asyncjs, algorithm]
import karax/[karax, karaxdsl, vdom, vstyles]

import matter, utils

type
  CanonStatus = enum
    csReady # Not launched yet
    csFlight # In the air
    csHit # Hit something and stopped

  CanonState = object
    angleDeg*: float
    angleRad*: float
    speed*: float
    pos*, vel*, gravity*: Vec

  CanonBase = object
    body*: JsObject
    dragging*: bool # This is also true if the platform is being dragged
    dragOffset*: float

  TrajectoryPoint = object
    ## pos is according to matter-js update body function
    ## acutalPos uses the high school level projectile motion formulas
    falsePos*, pos*, vel*: Vec
    falseTime*: int
    time*: float

  Trajectory = object
    points*: seq[TrajectoryPoint]
    middlePoint*: int
    closestPoint*: int # Closest point to the mouse
    initialState*: CanonState
    pinnedPoint*: int
    dragging*: bool # Is the pinned point being dragged

  Canon = object
    platform*: CanonPlatform
    status*: CanonStatus
    state*: CanonState
    base*: CanonBase

    body*: JsObject
    pivot*: JsObject
    dragOffset*: JsObject

    bullets*: seq[JsObject]
    bulletOptions*: JsObject
    currentBullet*: int
    bulletRadius*: int

    #x*, y*: int
    elevated*: bool
    dragging*: bool # Is the canon being dragged

  CanonPlatform = object
    body*: JsObject

  ParabolaState* = object
    engine*: JsObject
    render*: JsObject
    runner*: JsObject
    canvas*: Element

    paused*: bool

    mouse*: JsObject
    timeAtClick*: Time # the value of getTime() when left-click, used to check double click

    canon*: Canon
    trajectory*: Trajectory
    thingy*: JsObject
    ground*: JsObject

    bounds*: JsObject
    boundsScale*: JsObject
    boundsScaleTarget*: float

proc initCanonState(angle: float, deg = false, speed: float, 
  gravity: Vec, pos = vec(0, 0)): CanonState = 
  let angleDeg = if deg: angle else: radToDeg(angle)
  let angleRad = if deg: degToRad(angle) else: angle

  CanonState(angleDeg: angleDeg, angleRad: angleRad, 
    speed: speed, vel: speedToVelRad(speed, angleRad), 
    gravity: gravity, pos: pos
  )

# Projectile motion equations
proc calcTotalTime*(initialState: CanonState): float = 
  (initialState.vel.y + sqrt(initialState.vel.y^2 + 
    2 * initialState.gravity.y * initialState.pos.y)) / initialState.gravity.y

proc calcMaxRange*(initialState: CanonState): float = 
  initialState.vel.x * initialState.calcTotalTime()

proc calcMaxHeight*(initialState: CanonState): float = 
  initialState.pos.y + (initialState.vel.y^2 / (2*initialState.gravity.y))

proc calcPos*(initialState: CanonState, t: float): Vec = 
  vec(initialState.pos.x + (t * initialState.vel.x), 
    initialState.pos.y + (t * initialState.vel.y) - 
      (initialState.gravity.y * t^2) / 2)

proc calcVel*(initialState: CanonState, t: float): Vec = 
  vec(initialState.vel.x, 
    initialState.vel.y - (initialState.gravity.y * t))

const
  fps = 60
  timeScale = 0.4
  delta = (1000 / fps) * timeScale # 60fps, 60 times in one second (1000 milliseconds)

  groundHeight = 80

  canonXRatio = 0.2 # Ratio
  canonInitialSpeed = 10
  canonSpeedChange = 1
  canonAngleChangeDeg = 5d

  canonTexture = "/public/img/canon.png"
  canonBaseTexture = "/public/img/canonBase.png"
  canonPlatformTexture = "/public/img/canonPlatform.png"

  trajectoryStrokeStyle = "orange"
  trajectoryLineWidth = 2
  trajectoryPointRadius = 7 # The trajectory point hovered by the mouse

  velVectorScale = 9 # Scale of the velocity arrows
  speedLimit = 8.0..19.0
  rotaTionLimit = 10.0..160.0

proc toSi(state: CanonState): CanonState = 
  result = CanonState(
    angleDeg: state.angleDeg, angleRad: state.angleRad,
    speed: state.speed.toSiSpeed(delta),
    pos: state.pos.both(toSiMeters),
    gravity: vec(state.gravity.x, 9.807)#state.gravity.both(
    # proc(a: float): float = toSiAcceleration(a, delta))
  )
  result.vel = speedToVelRad(result.speed, state.angleRad)

proc canonBaseImg(state: ParabolaState): JsObject = 
  state.render.textures[canonBaseTexture]

proc canonPlatformImg(state: ParabolaState): JsObject = 
  state.render.textures[canonPlatformTexture]

proc canonImg(state: ParabolaState): JsObject = 
  state.render.textures[canonTexture]

proc wrapObject(state: ParabolaState): JsObject = 
  JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: state.canvas.clientWidth, y: undefined}} # To avoid boilerplate

## Since a body's angle can be negative and can be higher than 360, this procedure makes it so it's always positive and inside 0..359
proc normalizeAngle(rad: float): float =
  result = rad.radToDeg().round(0)
  result -= float(result.int div 360) * 360 # Remove excess rotations

  if result < 0:
    result = abs result
  elif result > 0:
    result = 360 - result

proc rotate(canon: var Canon, rad = degToRad(canonAngleChangeDeg), limit = true) =
  if limit and normalizeAngle(canon.body.angle.to(float) + rad) notin rotationLimit:
    return

  Body.rotate(canon.body, rad, canon.pivot)

  canon.state.angleDeg = normalizeAngle(canon.body.angle.to(float))
  canon.state.angleRad = degToRad(float canon.state.angleDeg)
  canon.state.vel = speedToVelRad(canon.state.speed, canon.state.angleRad)

proc rotateBack(canon: var Canon, rad = degToRad(canonAngleChangeDeg), limit = true) =
  canon.rotate(-rad, limit)

proc setSpeed(canon: var Canon, speed: float) = 
  canon.state.speed = clamp(speed, speedLimit)
  canon.state.vel = speedToVelRad(canon.state.speed, canon.state.angleRad)  

proc nextBullet(state: var ParabolaState): JsObject = 
  result = Bodies.circle(
    state.canon.pivot.x, state.canon.pivot.y, 
    state.canon.bulletRadius, state.canon.bulletOptions
  )
  Body.setAngle(result, state.canon.state.angleDeg)

proc calcTrajectory(state: var ParabolaState) =
  let bullet = state.nextBullet()
  #bullet.timeScale = timeScale
  bullet.plugin = JsObject{wrap: state.wrapObject()}

  let initialPos = bullet.position.vec()
  let initialState = state.canon.state
  state.trajectory.initialState = initialState

  let siInitialState = initialState.toSi()
  #echo siInitialState

  let totalFalseTime = block: # Really aproximated calculation
    var a = initialState
    a.gravity = a.gravity * 15.6
    a.calcTotalTime()

  let siMaxRange = siInitialState.calcMaxRange()
  let siTotalTime = siInitialState.calcTotalTime()

  # Invert vel.y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVec(initialState.vel.x, -initialState.vel.y))

  # Highest point is actually lowest point since matter counts 0 from the top
  var highestPoint = (index: 0, y: state.canvas.clientHeight.float)

  state.trajectory.points.setLen(0)
  for i in countup(0, totalFalseTime.int * 4):
    if bullet.getY.int > state.canvas.clientHeight - groundHeight:
      break

    #MatterWrap.Body.wrap(bullet, bullet.plugin.wrap)

    let falsePos = bullet.position.vec()

    state.trajectory.points.add TrajectoryPoint(
      falsePos: falsePos,
      falseTime: i
    )

    if falsePos.y < highestPoint.y:
      highestPoint = (state.trajectory.points.high, falsePos.y)

    bullet.force.x += bullet.mass * toJs initialState.gravity.x
    bullet.force.y += bullet.mass * toJs initialState.gravity.y
    Body.update(bullet, delta * 8)
    bullet.force.x = 0
    bullet.force.y = 0
    bullet.torque = 0

  # Here we use the displacement of the bullet position to estimate the time in each point
  let xRange = abs(bullet.position.vec().x - initialPos.x)

  for p in state.trajectory.points.mitems:
    let siTime = ((abs(p.falsePos.x - initialPos.x) * siTotalTime) / xRange)

    with p:
      time = siTime
      pos = siInitialState.calcPos(siTime)
      vel = siInitialState.calcVel(siTime)

  state.trajectory.middlePoint = highestPoint.index
  #with state.trajectory.points[highestPoint.index]:
  #  pos = vec(
  #    siMaxRange / 2,
  #    siInitialState.calcMaxHeight()
  #  )
  #  vel = vec(siInitialState.vel.x, 0)
  #  time = siTotalTime / 2

  #with state.trajectory.points[^1]:
  #  pos = vec(siMaxRange, 0)
  #  vel = siInitialState.calcVel(siTotalTime) #siInitialState.vel
  #  time = siTotalTime

  if not kxi.surpressRedraws: redraw(kxi)

proc onResize(state: var ParabolaState) = 
  state.render.canvas.width = state.canvas.clientWidth
  state.render.canvas.height = state.canvas.clientHeight

  let wrap = state.wrapObject()

  state.canon.bulletOptions.plugin = JsObject{wrap: wrap}

  for b in Composite.allBodies(state.engine.world).to(seq[JsObject]):
    if b.hasOwnProperty("plugin") and b.plugin.hasOwnProperty("wrap"):
      b.plugin.wrap = wrap

    if b.hasOwnProperty("xratio"):
      let pos = JsObject{x: state.canvas.clientWidth.toJs * b.xratio, y: b.position.y}
      Body.setPosition(b, pos)

    if b.hasOwnProperty("yratio"):
      Body.setPosition(b, JsObject{x: b.position.x, y: state.canvas.clientHeight.toJs * b.yratio})

  let canonImg = state.canonImg or JsObject{width: 1, height: 1}
  let canonBaseImg = state.canonBaseImg or JsObject{width: 1, height: 1}
  let canonPlatformImg = state.canonPlatformImg or JsObject{width: 1, height: 1}

  if not state.canon.elevated:# and not canonBaseImg.isUndefined and not canonPlatformImg.isUndefined:
    let canonPrevAngle = state.canon.body.angle.to(float) 
    state.canon.rotate(-canonPrevAngle, limit = false)

    let baseY = state.canvas.clientHeight.float - groundHeight.float - (2.5*meterPerPx)
    state.canon.base.body.setY baseY
  
    let canonX = state.canon.base.body.position.x + (canonImg.width / 3.toJs)
    let canonY = baseY.toJs - (canonBaseImg.height * 0.2.toJs)

    state.canon.body.setPos canonX, canonY
    
    state.canon.pivot = JsObject{x: state.canon.base.body.position.x, y: canonY}
    state.canon.state.pos.y = state.canvas.clientHeight.float - groundHeight.float - state.canon.pivot.y.to(float)

    let platformY = (baseY * 1.02) + (canonPlatformImg.height.to(float) / 2)
    state.canon.platform.body.setY platformY

    state.canon.rotate(canonPrevAngle, limit = false)
    state.calcTrajectory()

proc initParabolaState*(): ParabolaState = 
  result = ParabolaState(
    boundsScale: JsObject{x: 1, y: 1},
    boundsScaleTarget: 1, 
    canon: Canon(
      bulletRadius: 20, state: initCanonState(0, deg = true, 
        canonInitialSpeed, gravity = vec(0, 0.001)), 
      bulletOptions: JsObject{
        isStatic: false, frictionAir: 0, friction: 1, mass: 1,
      }),
    trajectory: Trajectory(  
      closestPoint: -1, middlePoint: -1, pinnedPoint: -1)
  )

proc `bullet`(canon: Canon): JsObject = 
  assert canon.currentBullet in canon.bullets, &"Invalid bullet index {canon.currentBullet}"
  canon.bullets[canon.currentBullet]

proc fireBullet(state: var ParabolaState) = 
  let bullet = state.nextBullet()
  bullet.collisionFilter.mask = 0

  Composite.add(state.engine.world, bullet)
  state.canon.bullets.add bullet
  state.canon.currentBullet = state.canon.bullets.high

  state.canon.status = csFlight

  let vel = state.canon.state.vel

  # Invert vel y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVec(vel.x, -vel.y))

proc calcClosestTrajectoryPoint(state: var ParabolaState, point: Vec, minRange = false) = 
  ## Calculates the closest trajectory point to point
  ## If minRange, ignore points further than minRangeDistance
  const minRangeDistance = 40
  var result = -1
  var closestDistance = 0.0

  for e, p in state.trajectory.points:
    let d = distance(p.falsePos, point)
    if result < 0 or d < closestDistance:
      closestDistance = d
      result = e

  if minRange and closestDistance > minRangeDistance:
    result = -1 
  elif result != state.trajectory.middlePoint and 
    distance(state.trajectory.points[result].falsePos, 
      state.trajectory.points[state.trajectory.middlePoint].falsePos) < 10:
    result = state.trajectory.middlePoint

  state.trajectory.closestPoint = result

proc onMousedown(state: var ParabolaState, event: JsObject) = 
  case event.button.to(int)
  of 0:
    let t = getTime()
    echo (t - state.timeAtClick)
    if t - state.timeAtClick <= initDuration(milliseconds = 250):
      state.calcClosestTrajectoryPoint(state.mouse.position.vec(), minRange = true)
      if state.trajectory.closestPoint in state.trajectory.points:
        state.trajectory.dragging = true
        if not kxi.surpressRedraws: redraw(kxi)

    elif Bounds.contains(state.canon.base.body.bounds, state.mouse.position).to(bool) or 
      Bounds.contains(state.canon.platform.body.bounds, state.mouse.position).to(bool):
      state.canon.base.dragging = true
      state.canon.base.dragOffset = state.canon.base.body.getY - state.mouse.position.y.to(float)
    elif Bounds.contains(state.canon.body.bounds, state.mouse.position).to(bool): 
      state.canon.dragging = true
      state.canon.dragOffset = Vector.angle(state.canon.pivot, state.mouse.position) - state.canon.body.angle

    state.timeAtClick = t
  of 1:
    state.fireBullet()
  else: discard

proc onMouseup(state: var ParabolaState, event: JsObject) = 
  case event.button.to(int)
  of 0:
    state.canon.dragging = false
    state.canon.base.dragging = false
    state.trajectory.dragging = false
 
    if state.trajectory.closestPoint in state.trajectory.points:
      state.trajectory.pinnedPoint = state.trajectory.closestPoint
      if not kxi.surpressRedraws: redraw(kxi)
  else:
    discard

proc onMousemove(state: var ParabolaState, event: JsObject) = 
  let canonImg = state.canonImg or JsObject{width: 1, height: 1}
  let canonBaseImg = state.canonBaseImg or JsObject{width: 1, height: 1}
  let canonPlatformImg = state.canonPlatformImg or JsObject{width: 1, height: 1}

  if state.canon.base.dragging:
    let canonPrevAngle = state.canon.body.angle.to(float) 
    state.canon.rotate(-canonPrevAngle, limit = false)

    let mousey = state.mouse.position.y.to(float) + state.canon.base.dragOffset

    # It is baseMax even though it's the lowest point since matter counts y from the top
    let baseMax = state.canvas.clientHeight.float - groundHeight.float + (canonBaseImg.height.to(float) * 0.2)
    let baseMin = canonImg.width.to(float) + (canonBaseImg.height.to(float) * 0.2)#(state.canonBaseImg.height.to(float))
    let baseY = clamp(mousey, baseMin, baseMax)
    state.canon.base.body.setY baseY

    state.canon.elevated = baseY != baseMax

    let platformY = (baseY * 1.02)  + (canonPlatformImg.height.to(float) / 2)
    state.canon.platform.body.setY platformY

    # It is canonMax even though it's the lowest point since matter counts y zero from the top
    let canonMax = state.canvas.clientHeight.float - groundHeight.float# - (state.canonBaseImg.height.to(float) * 0.5)
    let canonMin = canonImg.width.to(float) # We add half the base height since the canon is always lower than the base
    let canonY = clamp(mousey - (canonBaseImg.height.to(float) * 0.2), canonMin, canonMax)
    state.canon.body.setY canonY

    state.canon.pivot.y = canonY
    state.canon.state.pos.y = state.canvas.clientHeight.float - groundHeight.float - state.canon.pivot.y.to(float)
    state.canon.rotate(canonPrevAngle, limit = false)
    state.calcTrajectory()

  elif state.canon.dragging:
    let targetAngle = Vector.angle(state.canon.pivot, state.mouse.position) - state.canon.dragOffset
    state.canon.rotate(to(targetAngle - state.canon.body.angle, float))
    state.calcTrajectory()

  elif state.trajectory.dragging:
    state.calcClosestTrajectoryPoint(state.mouse.position.vec())
    if not kxi.surpressRedraws: redraw(kxi)

proc onMouseleave(state: var ParabolaState, event: JsObject) = 
  state.canon.dragging = false
  state.canon.base.dragging = false
  state.trajectory.dragging = false

  if state.trajectory.closestPoint in state.trajectory.points:
    state.trajectory.pinnedPoint = state.trajectory.closestPoint
    if not kxi.surpressRedraws: redraw(kxi)

proc onWheel(state: var ParabolaState, event: JsObject) = 
  let wheelDelta = event.wheelDelta.to(float)
  if wheelDelta != 0:
    state.canon.setSpeed(state.canon.state.speed + (wheelDelta / 120))
    state.calcTrajectory()

proc onAfterUpdate(state: var ParabolaState, event: JsObject) = 
  if state.canon.bullets.len > 0:
    let bullet = state.canon.bullet
    if state.canon.status == csFlight and bullet.collisionFilter.mask == 0.toJs and
      bullet.position.y.to(float).int < state.canvas.clientHeight - groundHeight - bullet.circleRadius.to(float).int:

      bullet.collisionFilter.mask = maskDefault

proc onCollisionStart(state: var ParabolaState, event: JsObject) = 
  if state.canon.bullets.len > 0 and state.canon.status == csFlight:
    for pair in items(event.pairs):
      if pair.bodyA.id == state.canon.bullet.id or pair.bodyB.id == state.canon.bullet.id:
        state.canon.status = csHit
        break

proc onBeforeRender(state: var ParabolaState, event: JsObject) = 
  return
  let mouse = state.mouse#state.mouseConstraint.mouse
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

proc drawVelocityArrows(state: ParabolaState, ctx: JsObject) = 
  if state.canon.bullets.len > 0 and state.canon.status == csFlight:
    let pos = state.canon.bullet.position
    const threshold = 0.4
    if state.canon.bullet.velocity.y.to(float) notin -threshold..threshold:
      drawArrow(ctx, pos.x, pos.y, 
        pos.x,
        pos.y + (state.canon.bullet.velocity.y * toJs velVectorScale), 
        toJs 4, toJs cstring"red"
      )

    if state.canon.bullet.velocity.x.to(float) notin -threshold..threshold:
      drawArrow(ctx, pos.x, pos.y, 
        pos.x + (state.canon.bullet.velocity.x * toJs velVectorScale), 
        pos.y,
        toJs 4, toJs cstring"#3FD0F6" # Neon blue
      )

    #if state.canon.bullet.velocity.x.to(float).int != 0 and state.canon.bullet.velocity.y.to(float).int != 0:
      #drawArrow(ctx, pos.x, pos.y, 
      #  pos.x + (state.canon.bullet.velocity.x * toJs velVectorScale), 
      #  pos.y + (state.canon.bullet.velocity.y * toJs velVectorScale), 
      #  toJs 4, toJs cstring"white"
      #)

proc drawTrajectory(state: ParabolaState, ctx: JsObject, falseOne = true) = 
  let trajectory = state.trajectory
  proc foo(p: TrajectoryPoint): Vec = 
    if falseOne:
      return p.falsePos

    result = p.pos * 5.6#(meterPerPx / 14)
    result.x = state.canon.pivot.x.to(float) + result.x
    result.y = state.canon.pivot.y.to(float) - result.y #(state.canvas.clientHeight.float - (groundHeight.float + 
      #trajectory.initialState.pos.y)) - result.y
    
    #result.y = state.canon.pivot.y.to(float) - result.y
  let p0 = trajectory.points[0]

  ctx.beginPath()
  ctx.moveTo(p0.foo.x, p0.foo.y)

  if falseOne:
    ctx.strokeStyle = cstring trajectoryStrokeStyle
  else:
    ctx.strokeStyle = cstring"#7991FA"

  ctx.lineWidth = trajectoryLineWidth
  for e, p in trajectory.points[1..^1]:
    # If the previous trajectory point is too far aways
    # Don't draw do lineTo but moveTo
    # e is the index of the previous trajectory point beacause ...points[1..^1]
    #if abs(trajectory.points[e].foo.x - p.foo.x) > 100:
    #  ctx.moveTo(p.foo.x, p.foo.y)
    #else:
    ctx.lineTo(p.foo.x, p.foo.y)
  #let mp = trajectory.points[trajectory.middlePoint]
  #ctx.lineTo(mp.foo.x, mp.foo.y)

  #for e, p in trajectory.points[trajectory.middlePoint+1..^1]:
  #  # If the previous trajectory point is too far aways
  #  # Don't draw do lineTo but moveTo
  #  # e is the index of the previous trajectory point beacause ...points[1..^1]
  #  #if abs(trajectory.points[e].foo.x - p.foo.x) > 100:
  #  #  ctx.moveTo(p.foo.x, p.foo.y)
  #  #else:
  #  ctx.lineTo(p.foo.x, p.foo.y)

  ctx.stroke()

proc onAfterRender(state: var ParabolaState, event: JsObject) = 
  Render.startViewTransform(state.render)
  let ctx = state.render.context

  state.drawVelocityArrows(ctx)

  # Draw trajectory
  let trajectory = state.trajectory

  if trajectory.points.len > 0:
    ctx.save()

    ctx.globalAlpha = 0.7
    state.drawTrajectory(ctx)
    state.drawTrajectory(ctx, false)
    ctx.globalAlpha = 1

    # Draw points
    ctx.fillStyle = cstring"#47D916"

    if trajectory.middlePoint in trajectory.points:
      let middlePos = trajectory.points[trajectory.middlePoint].falsePos
      ctx.beginPath()
      ctx.arc(middlePos.x, middlePos.y, 
        int(trajectoryPointRadius.float * 0.8), 0, 2 * PI
      )
      ctx.fill()

    let lastPos = trajectory.points[^1].falsePos
    ctx.beginPath()
    ctx.arc(lastPos.x, lastPos.y, 
      int(trajectoryPointRadius.float * 0.8), 0, 2 * PI
    )
    ctx.fill()

    var drawPoint = false
    var falsePos: Vec

    if trajectory.dragging and trajectory.closestPoint in trajectory.points:
      drawPoint = true
      falsePos = trajectory.points[trajectory.closestPoint].falsePos
    elif not trajectory.dragging and trajectory.pinnedPoint in trajectory.points:
      drawPoint = true
      falsePos = trajectory.points[trajectory.pinnedPoint].falsePos

    if drawPoint:
      ctx.fillStyle = cstring"#16B0D9"
      ctx.beginPath()
      ctx.arc(falsePos.x, falsePos.y, 
        trajectoryPointRadius, 0, 2 * PI
      )
      ctx.fill()

    ctx.restore()

  Render.endViewTransform(state.render)

proc onAfterAdd(state: var ParabolaState, event: JsObject) = 
  ## Sort bodies by z-index/depth
  state.engine.world.bodies = state.engine.world.bodies.to(seq[JsObject]).sorted(proc(a, b: JsObject): int =
    let z1 = if a.zIndex.isNil: 0 else: a.zIndex.to(float).int
    let z2 = if b.zIndex.isNil: 0 else: b.zIndex.to(float).int
    z1 - z2
  )

proc loadEvents(state: var ParabolaState) = 
  #Events.on(state.mouseConstraint, "mousedown", proc(event: JsObject) = state.onMousedown(event))
  state.mouse.element.addEventListener("mousedown", 
    proc(event: JsObject) = state.onMousedown(event), JsObject{passive: true})

  state.mouse.element.removeEventListener("mouseup", state.mouse.mouseup)

  state.mouse.element.addEventListener("mouseup", 
    proc(event: JsObject) = state.onMouseup(event), JsObject{passive: true})
  
  state.mouse.element.addEventListener("mouseup", state.mouse.mouseup)

  state.mouse.element.addEventListener("mousemove", 
    proc(event: JsObject) = state.onMousemove(event), JsObject{passive: true})
  
  state.mouse.element.addEventListener("mouseleave", 
    proc(event: JsObject) = state.onMouseleave(event), JsObject{passive: true})

  state.mouse.element.addEventListener("wheel", proc(event: JsObject) = state.onWheel(event))

  Events.on(state.engine, "afterUpdate", proc(event: JsObject) = state.onAfterUpdate(event))

  Events.on(state.engine, "collisionStart", proc(event: JsObject) = state.onCollisionStart(event))

  Events.on(state.render, "beforeRender", proc(event: JsObject) = state.onBeforeRender(event))

  Events.on(state.render, "afterRender", proc(event: JsObject) = state.onAfterRender(event))

  Events.on(state.engine.world, "afterAdd", proc(event: JsObject) = state.onAfterAdd(event))

proc onImagesLoaded*(state: var ParabolaState) = 
  Render.run(state.render)

  let canonImg = state.canonImg or JsObject{width: 1, height: 1}
  let canonBaseImg = state.canonBaseImg or JsObject{width: 1, height: 1}
  let canonPlatformImg = state.canonPlatformImg or JsObject{width: 1, height: 1}

  Body.scale(state.canon.body, canonImg.width, canonImg.height)
  Body.scale(state.canon.base.body, canonBaseImg.width, canonBaseImg.height)
  Body.scale(state.canon.platform.body, canonPlatformImg.width, canonPlatformImg.height)

  state.onResize()
  state.canon.rotateBack(degToRad(60d))

  state.calcTrajectory()

## Loads the simulation
proc load*(state: var ParabolaState) =
  # Render all MathJax expressions asynchronously
  MathJax.typesetPromise()

  # Load wrap's plugin and load matter aliases to point to the correct values
  Matter.use("matter-wrap")
  loadMatterAliases()

  let gravity = state.canon.state.gravity.jsVec()
  gravity.scale = 1

  state.canvas = getElementById("canvas")
  state.engine = createEngine(JsObject{gravity: gravity, timing: JsObject{timeScale: timeScale}})
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

  state.runner = Runner.create(JsObject{fps: fps})
  Runner.run(state.runner, state.engine)

  state.bounds = JsObject{min: JsObject{x: 0, y: 0}, max: JsObject{x: state.canvas.clientWidth.float * 0.6, y: state.canvas.clientHeight.float * 0.5}}

  # Create and add all bodies to the world
  # onResize will set the correct positions
  state.canon.body = Bodies.rectangle(0, 0, 1, 1, JsObject{
    zIndex: 3, isStatic: true, collisionFilter: JsObject{mask: 0}, label: cstring"Canon",
    render: JsObject{sprite: JsObject{
      texture: cstring canonTexture, 
      xOffset: 0, yOffset: 0
    }}
  })

  state.canon.base.body = Bodies.rectangle(0, 0, 1, 1, JsObject{
    zIndex: 4, isStatic: true, collisionFilter: JsObject{mask: 0}, label: cstring"Base",
    render: JsObject{sprite: JsObject{
      texture: cstring canonBaseTexture, 
      xOffset: 0, yOffset: 0
    }}
  })
  state.canon.base.body.xratio = canonXRatio

  state.canon.platform.body = Bodies.rectangle(0, 0, 1, 1, JsObject{
    zIndex: 2, isStatic: true, collisionFilter: JsObject{mask: 0}, label: cstring"Platform",
    render: JsObject{sprite: JsObject{
      texture: cstring canonPlatformTexture, 
      xOffset: 0, yOffset: 0
    }}
  })
  state.canon.platform.body.xratio = canonXRatio

  state.ground = Bodies.rectangle(0, 0, state.canvas.clientWidth * 1000, groundHeight * 2, 
    JsObject{zIndex: 1, isStatic: true, label: cstring"Ground"}
  ) # 350, 495, 1200
  state.ground.xratio = 0.5
  state.ground.yratio = 1

  state.thingy = Bodies.rectangle(state.canvas.clientWidth / 2, state.canvas.clientHeight.float * 0.6, 20, 80, JsObject{isStatic: false, label: cstring"Thing.y", plugin: JsObject{wrap: state.wrapObject}})

  state.mouse = Mouse.create(state.canvas)
  #state.mouseConstraint = MouseConstraint.create(state.engine, JsObject{mouse: state.mouse, collisionFilter: JsObject{mask: 0}})
  state.render.mouse = state.mouse

  let roof = Bodies.rectangle(350, -200, 1000, 20, JsObject{isStatic: true, label: cstring"Roof"})
  roof.xratio = 0.5
  roof.yratio = -0.6

  state.loadEvents()

  Composite.add(state.engine.world, toJs [
    state.canon.body,#, state.mouseConstraint,
    state.thingy, state.canon.base.body,
    state.canon.platform.body,
    # Walls
    roof, # up
    # Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}), # right
    state.ground, # down
    # Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}), # left
  ])

  # Wait until all textures are loaded
  var loadedImgCount = 0
  var images = newSeq[cstring]()
  for b in Composite.allBodies(state.engine.world).to(seq[JsObject]):
    if not b.render.sprite.texture.isUndefined and not to(b.render.sprite.texture in state.render.textures, bool):
      images.add b.render.sprite.texture.to(cstring)

  for src in images:
    let img = newImage()
    img.onload = proc() =
      inc loadedImgCount
      if loadedImgCount == images.len:
        state.onImagesLoaded()

    img.src = src
    state.render.textures[src] = img

## Reloads the simulation
proc reload*(state: var ParabolaState) =
  Composite.clear(state.engine.world)
  Engine.clear(state.engine)
  Render.stop(state.render)
  Runner.stop(state.runner)
  state = initParabolaState()#.trajectory.setLen(0)
  state.load()

## Since matter measures y from the top of the screen, here we "normalize" it so that the 0 starts at the ground
proc normalizeY(state: ParabolaState, y: int, height: int): int =
  -y + (state.ground.position.y.to(float).int - (groundHeight div 2) - height)

proc togglePause(state: var ParabolaState) = 
  if state.paused:
    state.engine.timing.timeScale = timeScale
  else:
    state.engine.timing.timeScale = 0

  state.paused = not state.paused

proc renderTopDiv*(state: ParabolaState): VNode =
  var siInitialState = state.trajectory.initialState.toSi()
 
  buildHtml tdiv(id = "text", style = "".toCss):
    #p(text r"\(t_f = \frac{2 \cdot v_i \cdot \sin(\theta)}{g}\)", style = "font-size: 50px;".toCss)

    p(text &"h = {siInitialState.pos.y:.1f}")
    p(text &"α = {siInitialState.angleDeg:.0f}")

    p(text &"Vi = {siInitialState.speed:.1f}")

    p(text &"total time = {siInitialState.calcTotalTime():.2f}")

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

    canvas(id = "canvas", style = fmt"width: 100vw; min-width: 500px; height: 65vh; min-height: 300px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

proc renderBottomDiv*(state: ParabolaState): VNode =
  let trajectory = state.trajectory
  var show = false
  var point: TrajectoryPoint

  if trajectory.dragging and trajectory.closestPoint in trajectory.points:
    show = true
    point = trajectory.points[trajectory.closestPoint]
  elif not trajectory.dragging and trajectory.pinnedPoint in trajectory.points:
    show = true
    point = trajectory.points[trajectory.pinnedPoint]

  buildHtml tdiv(id = "text", style = "display: inline-flex;gap: 25px;".toCss):
    if show:
      p(text &"x = {point.pos.x:.1f} y = {point.pos.y:.1f}")
      p(text &"t = {point.time:.2f}")

      p(text &"Vx = {point.vel.x:.1f}")
      p(text &"Vy = {point.vel.y:.1f}")

    # p(text fmt"\(a = \frac{{v_f - {bullet.position.x}}}{{\Delta t}}\)", style = "font-size: 80px;".toCss)

proc render*(state: var ParabolaState): VNode =
  buildHtml tdiv(style = "display: flex; flex-direction: column; justify-content: start; align-items: center; height: 100%;".toCss):
    state.renderTopDiv()
    state.renderSimDiv()
    state.renderBottomDiv()

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
    #echo $event.key
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
