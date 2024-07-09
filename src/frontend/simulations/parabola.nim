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
    height*: float
    vel*, gravity*: Vec

  CanonBase = object
    body*: JsObject
    dragging*: bool # This is also true if the platform is being dragged
    dragOffset*: float

  TrajectoryPoint = object
    ## pos is according to matter-js update body function
    ## acutalPos uses the high school level projectile motion formulas
    pos*, vel*: Vec
    time*: float

  Trajectory = object
    points*: seq[TrajectoryPoint]
    highestPoint*: int
    closestPoint*: int # Closest point to the mouse
    #initialState*: CanonState
    pinnedPoint*: int
    dragging*: bool # Is the pinned point being dragged
    totalTime*: float

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

    onMousedown*, onMouseup*, onMousemove*, 
      onMouseleave*, onWheel*: proc(event: JsObject)

    floatPrecision*: range[0..8]

# Projectile motion equations
proc calcTotalTime*(initialState: CanonState): float = 
  (initialState.vel.y + sqrt(initialState.vel.y^2 + 
    2 * initialState.gravity.y * initialState.height)) / initialState.gravity.y

proc calcMaxRange*(initialState: CanonState): float = 
  initialState.vel.x * initialState.calcTotalTime()

proc calcMaxHeight*(initialState: CanonState): float = 
  initialState.height + (initialState.vel.y^2 / (2*initialState.gravity.y))

proc calcX*(initialState: CanonState, t: float): float = 
  t * initialState.vel.x

proc calcY*(initialState: CanonState, t: float): float = 
  initialState.height + (t * initialState.vel.y) - 
    (initialState.gravity.y * t^2) / 2

proc calcPos*(initialState: CanonState, t: float): Vec = 
  vec(initialState.calcX(t), initialState.calcY(t))

proc calcVel*(initialState: CanonState, t: float): Vec = 
  vec(initialState.vel.x, 
    initialState.vel.y - (initialState.gravity.y * t))

# Don't use, too inaccurate
#proc calcTime*(initialState: CanonState, y: float): float = 
#  -initialState.vel.y + sqrt(initialState.vel.y^2 - 
#    (2 * initialState.gravity.y * initialState.height) + (2 * 
#      initialState.gravity.y * y)) / initialState.gravity.y
#  #-initialState.vel.y - sqrt(initialState.vel.y^2 - 
#  #  (2 * initialState.gravity.y * initialState.height) + (2 * 
#  #    initialState.gravity.y * y)) / initialState.gravity.y

const
  fps = 60
  timeScale = 0.03
  delta = (1000 / fps) * timeScale # 60fps, 60 times in one second (1000 milliseconds)

  # For some reason if you use the projectile motion formulas with matter-js
  # gravity you get a different trajectory, you instead have to multiply
  # matter-js gravity by this proportion to make it work :shrug:
  gravityFactor = 279.0

  groundHeight = 80.0

  canonXRatio = 0.2 # Ratio
  canonInitialSpeed = 250.0
  canonSpeedChange = 1.0
  canonAngleChangeDeg = 3.0

  canonTexture = "/public/img/canon.png"
  canonBaseTexture = "/public/img/canonBase.png"
  canonPlatformTexture = "/public/img/canonPlatform.png"

  trajectoryStrokeStyle = "orange"
  trajectoryLineWidth = 2
  trajectoryPointRadius = 7 # The radius of the trajectory point hovered by the mouse

  velVectorScale = canonInitialSpeed * 0.002 # Scale of the velocity arrows
  speedLimit = (canonInitialSpeed/2)..(canonInitialSpeed*1.5)
  angleLowerLimit = 16.0 # Lower limit when canon is too close to the floor

proc setSpeed(state: var CanonState, speed: float) = 
  state.speed = clamp(speed, speedLimit)
  state.vel = speedToVelRad(state.speed, state.angleRad)  

proc initCanonState(angle: float, deg = false, speed: float, 
  gravity: Vec, height = 0.0): CanonState = 
  let angleDeg = if deg: angle else: radToDeg(angle)
  let angleRad = if deg: degToRad(angle) else: angle

  result = CanonState(angleDeg: angleDeg, angleRad: angleRad, 
    gravity: gravity, height: height)
  result.setSpeed(speed)

proc getPos(state: ParabolaState, p: TrajectoryPoint): Vec = 
  ## Converts p.pos into matter-js coordinates
  vec(
    state.canon.pivot.x.to(float) + p.pos.x,
    state.canvas.clientHeight.float - groundHeight.float - p.pos.y
  )

proc toMu(state: CanonState): CanonState = 
  result = state
  with result:
    speed = result.speed.toMuSpeed()
    height = result.height.toMuDistance()
    gravity = result.gravity.both(proc(a: float): float = toMuAcceleration(a))
    vel = speedToVelRad(result.speed, result.angleRad)

proc toMu(point: TrajectoryPoint): TrajectoryPoint = 
  result = point
  with result:
    pos = result.pos.both(proc(d: float): float = toMuDistance(d))
    vel = result.vel.both(proc(v: float): float = toMuSpeed(v))

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

proc rotationLimit(state: ParabolaState): Slice[float] = 
  let canonImg = state.canonImg or JsObject{width: 1, height: 1}

  if state.canon.state.height > canonImg.width.to(float):
    (0.0)..(360.0)
  elif state.canon.state.height > (canonImg.height.to(float) / 2):
    0.0..180.0
  else:
    angleLowerLimit..(180.0-angleLowerLimit)

proc rotateCanon(state: var ParabolaState, rad = degToRad(canonAngleChangeDeg), limit = true) =
  var rad = rad
  if limit:
    let rotationLimit = state.rotationLimit()

    let desiredAngleDeg = normalizeAngle(state.canon.body.angle.to(float) + rad)
    if desiredAngleDeg notin rotationLimit:
      let lowerLimit = 
        if desiredAngleDeg > 180: 360.0 + rotationLimit.a
        else: rotationLimit.a

      if abs(desiredAngleDeg - lowerLimit) < 
        abs(desiredAngleDeg - rotationLimit.b):
        rad = degToRad(normalizeAngle(state.canon.body.angle.to(float)) - 
          rotationLimit.a)
      else:
        rad = degToRad(normalizeAngle(state.canon.body.angle.to(float)) - 
          rotationLimit.b)

  Body.rotate(state.canon.body, rad, state.canon.pivot)

  state.canon.state.angleDeg = normalizeAngle(state.canon.body.angle.to(float))
  state.canon.state.angleRad = degToRad(float state.canon.state.angleDeg)
  state.canon.state.vel = speedToVelRad(state.canon.state.speed, 
    state.canon.state.angleRad)

proc rotateCanonBack(state: var ParabolaState, rad = degToRad(canonAngleChangeDeg), limit = true) =
  state.rotateCanon(-rad, limit)

proc nextBullet(state: var ParabolaState): JsObject = 
  result = Bodies.circle(
    state.canon.pivot.x, state.canon.pivot.y, 
    state.canon.bulletRadius, state.canon.bulletOptions
  )
  Body.setAngle(result, state.canon.state.angleDeg)
  Body.setInertia(result, Infinity)

proc calcTrajectory(state: var ParabolaState) =
  var initialState = state.canon.state
  initialState.gravity = initialState.gravity * gravityFactor

  let downwards = initialState.angleDeg > 180 and initialState.angleDeg < 360

  let totalTime = initialState.calcTotalTime()
  state.trajectory.totalTime = totalTime

  var highest = (index: 0, y: 0.0)

  state.trajectory.points.setLen(0)
  for t in countthrough(0.0, totalTime, step = delta / 50):
    var point: TrajectoryPoint
    with point:
      time = t
      pos = initialState.calcPos(t)
      vel = initialState.calcVel(t)

    state.trajectory.points.add point

    if not downwards and point.pos.y > highest.y:
      highest = (state.trajectory.points.high, point.pos.y)

  state.trajectory.highestPoint = highest.index

  if not downwards:
    var highestPoint = state.trajectory.points[highest.index]
    var initialStateB = initialState
    initialStateB.height = 0

    highestPoint.pos.y = initialState.calcMaxHeight()
    highestPoint.time = initialStateB.calcTotalTime() / 2
    highestPoint.pos.x = initialState.calcX(highestPoint.time)
    highestPoint.vel.y = 0

    state.trajectory.points[highest.index] = highestPoint

  with state.trajectory.points[^1]:
    pos = vec(initialState.calcMaxRange(), 0)
    #vel = siInitialState.calcVel(siTotalTime) #siInitialState.vel
    time = totalTime

  if not kxi.surpressRedraws: redraw(kxi)

proc onResize(state: var ParabolaState, trajectory = true, first = false) = 
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

  # We rotate it to be able to position it correctly
  let canonPrevAngle = state.canon.body.angle.to(float) 
  state.rotateCanon(-canonPrevAngle, limit = false)

  # It is baseMax even though it's the lowest point since matter counts y from the top
  let baseMax = state.canvas.clientHeight.float - groundHeight.float + (canonBaseImg.height.to(float) * 0.2)
  let baseMin = canonImg.width.to(float) + (canonBaseImg.height.to(float) * 0.2)
  let desiredBaseY = 
    if state.canon.base.dragging:
      state.mouse.position.y.to(float) + state.canon.base.dragOffset
    else:
      if first: baseMax
      else: state.canon.base.body.getY()

  let baseY = clamp(desiredBaseY, baseMin, baseMax)
  state.canon.base.body.setY baseY

  let canonYDiff = canonBaseImg.height.to(float) * 0.2
  # It is canonMax even though it's the lowest point since matter counts y zero from the top
  let canonMax = baseMax - canonYDiff
  let canonMin = canonImg.width.to(float)

  let canonY = clamp(baseY - canonYDiff, canonMin, canonMax)

  let canonX = state.canon.base.body.position.x + (canonImg.width / 3.toJs)

  state.canon.body.setPos canonX, canonY
  
  state.canon.pivot = JsObject{x: state.canon.base.body.position.x, y: canonY}
  state.canon.state.height = state.canvas.clientHeight.float - groundHeight.float - state.canon.pivot.y.to(float)

  let platformY = (baseY * 1.02) + (canonPlatformImg.height.to(float) / 2)
  state.canon.platform.body.setY platformY

  state.rotateCanon(canonPrevAngle, limit = false)
  if trajectory:
    state.calcTrajectory()

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
  let trjctry = state.trajectory

  for e, p in trjctry.points:
    let d = distance(state.getPos(p), point)
    if result < 0 or d < closestDistance:
      closestDistance = d
      result = e

  if minRange and closestDistance > minRangeDistance:
    result = -1 
  elif result != trjctry.highestPoint and 
    distance(state.getPos(trjctry.points[result]), 
      state.getPos(trjctry.points[trjctry.highestPoint])) < 10:
    result = trjctry.highestPoint

  state.trajectory.closestPoint = result

proc initParabolaState*(): ParabolaState = 
  result = ParabolaState(
    boundsScale: JsObject{x: 1, y: 1},
    boundsScaleTarget: 1, 
    floatPrecision: 1,
    canon: Canon(
      bulletRadius: 20, state: initCanonState(0, deg = true, 
        canonInitialSpeed, gravity = vec(0, (9.807 * muMeterFactor) / 
          gravityFactor)
        ), 
      bulletOptions: JsObject{
        isStatic: false, frictionAir: 0, friction: 1,
      }),
    trajectory: Trajectory(  
      closestPoint: -1, highestPoint: -1, pinnedPoint: -1),
  )

proc onAfterUpdate(state: var ParabolaState, event: JsObject) = 
  if state.canon.bullets.len > 0:
    let bullet = state.canon.bullet
    if state.canon.status == csFlight and 
      bullet.collisionFilter.mask == 0.toJs and
      bullet.position.y.to(float) < state.canvas.clientHeight.float - 
        groundHeight - (bullet.circleRadius.to(float)):

      bullet.collisionFilter.mask = maskDefault

proc onCollisionStart(state: var ParabolaState, event: JsObject) = 
  if state.canon.bullets.len > 0 and state.canon.status == csFlight:
    for pair in items(event.pairs):
      if pair.bodyA.id == state.canon.bullet.id or pair.bodyB.id == state.canon.bullet.id:
        state.canon.status = csHit
        break

proc onBeforeRender(state: var ParabolaState, event: JsObject) = 
  return
  # WIP zoom
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

proc drawTrajectory(state: ParabolaState, ctx: JsObject) = 
  let trjctry = state.trajectory

  ctx.beginPath()
  let pos0 = state.getPos(trjctry.points[0])
  ctx.moveTo(pos0.x, pos0.y)

  ctx.strokeStyle = cstring trajectoryStrokeStyle
  #ctx.strokeStyle = cstring"#7991FA"

  ctx.lineWidth = trajectoryLineWidth
  for e, p in trjctry.points[1..^1]:
    # If the previous trajectory point is too far away (because of wrapping)
    # Don't draw do lineTo but moveTo
    # e is the index of the previous trajectory point beacause ...points[1..^1]
    #if abs(points[e].getPos.x - state.getPos(p).x) > 100:
    #  ctx.moveTo(state.getPos(p).x, state.getPos(p).y)
    #else:
    let pos = state.getPos(p)
    ctx.lineTo(pos.x, pos.y)

  ctx.stroke()

  # Draw points
  ctx.fillStyle = cstring"#47D916"

  if trjctry.highestPoint in trjctry.points:
    let middlePos = state.getPos(trjctry.points[trjctry.highestPoint])
    ctx.beginPath()
    ctx.arc(middlePos.x, middlePos.y, 
      int(trajectoryPointRadius.float * 0.8), 0, 2 * PI
    )
    ctx.fill()

  let lastPos = state.getPos(trjctry.points[^1])
  ctx.beginPath()
  ctx.arc(lastPos.x, lastPos.y, 
    int(trajectoryPointRadius.float * 0.8), 0, 2 * PI
  )
  ctx.fill()

  var drawPoint = false
  var pos: Vec

  if trjctry.dragging and trjctry.closestPoint in trjctry.points:
    drawPoint = true
    pos = state.getPos(trjctry.points[trjctry.closestPoint])
  elif not trjctry.dragging and trjctry.pinnedPoint in trjctry.points:
    drawPoint = true
    pos = state.getPos(trjctry.points[trjctry.pinnedPoint])

  if drawPoint:
    ctx.fillStyle = cstring"#16B0D9"
    ctx.beginPath()
    ctx.arc(pos.x, pos.y, 
      trajectoryPointRadius, 0, 2 * PI
    )
    ctx.fill()

proc drawHeight(state: ParabolaState, ctx: JsObject) = 
  if not state.canon.pivot.isNull:
    # So that when clientHeight is 621, size is 25
    #let fontSize = int round(state.canvas.clientHeight.float * 
    #  0.040257648953301126, 0)
    let height = state.canon.state.height.toMuDistance.round(state.floatPrecision)
    let text = &"{height}m"
    
    ctx.font = cstring "25px serif"
    ctx.fillStyle = cstring"white"
    let textsSize = ctx.measureText(cstring text)

    let canonPlatformImg = state.canonPlatformImg or JsObject{width: 1, height: 1}

    ctx.fillText(cstring text, 
      state.canon.pivot.x - textsSize.width - (canonPlatformImg.width / 1.8.toJs), 
      state.canvas.clientHeight.float - groundHeight - 10)

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
    ctx.globalAlpha = 1

    ctx.restore()

  ctx.save()
  state.drawHeight(ctx)
  ctx.restore()

  Render.endViewTransform(state.render)

proc onAfterAdd(state: var ParabolaState, event: JsObject) = 
  ## Sort bodies by z-index/depth
  state.engine.world.bodies = state.engine.world.bodies.to(seq[JsObject]).sorted(proc(a, b: JsObject): int =
    let z1 = if a.zIndex.isNil: 0 else: a.zIndex.to(float).int
    let z2 = if b.zIndex.isNil: 0 else: b.zIndex.to(float).int
    z1 - z2
  )

proc unloadEvents(state: var ParabolaState) = 
  state.mouse.element.removeEventListener("mousedown", state.onMousedown)
  state.mouse.element.removeEventListener("mouseup", state.onMouseup)
  state.mouse.element.removeEventListener("mousemove", state.onMousemove)
  state.mouse.element.removeEventListener("mouseleave", state.onMouseleave)
  state.mouse.element.removeEventListener("wheel", state.onWheel)

proc loadEvents(state: var ParabolaState) = 
  proc onMousemove(event: JsObject) = 
    if state.canon.dragging:
      let targetAngle = Vector.angle(state.canon.pivot, state.mouse.position) - state.canon.dragOffset
      state.rotateCanon(to(targetAngle - state.canon.body.angle, float))
      state.calcTrajectory()

    elif state.canon.base.dragging:
      state.onResize()
      state.rotateCanon(0) # To check if the canon is in the rotation limit

    elif state.trajectory.dragging:
      state.calcClosestTrajectoryPoint(state.mouse.position.vec())
      if not kxi.surpressRedraws: redraw(kxi)

  proc onMousedown(event: JsObject) = 
    case event.button.to(int)
    of 0:
      let t = getTime()

      if t - state.timeAtClick <= initDuration(milliseconds = 250):
        state.calcClosestTrajectoryPoint(state.mouse.position.vec(), minRange = true)
        if state.trajectory.closestPoint in state.trajectory.points:
          state.trajectory.dragging = true
          if not kxi.surpressRedraws: redraw(kxi)
        elif state.trajectory.pinnedPoint in state.trajectory.points:
          state.trajectory.pinnedPoint = -1
          if not kxi.surpressRedraws: redraw(kxi)

      elif Bounds.contains(state.canon.base.body.bounds, state.mouse.position).to(bool):
        state.canon.base.dragging = true
        state.canon.base.dragOffset = state.canon.base.body.getY - state.mouse.position.y.to(float)
      elif Bounds.contains(state.canon.body.bounds, state.mouse.position).to(bool): 
        state.canon.dragging = true
        state.canon.dragOffset = Vector.angle(state.canon.pivot, state.mouse.position) - state.canon.body.angle
      elif Bounds.contains(state.canon.platform.body.bounds, state.mouse.position).to(bool):
        state.canon.base.dragging = true
        state.canon.base.dragOffset = state.canon.base.body.getY - state.mouse.position.y.to(float)

      state.timeAtClick = t
    of 1:
      state.fireBullet()
    else: discard
  proc onMouseup(event: JsObject) = 
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
  proc onMouseleave(event: JsObject) = 
    # If the mouse leaves the canvas while dragging the base through the
    # bottom, drop the canon base to the floor. Since it's usual that if you
    # move the mouse quickly, the position isn't registered all the time
    # but every frame
    #if state.canon.base.dragging:
    #  if state.mouse.getY() >= state.canvas.clientHeight.float * 0.95:
    #    state.canon.elevated = false
    #    state.onResize()

    state.canon.dragging = false
    state.canon.base.dragging = false
    state.trajectory.dragging = false

    if state.trajectory.closestPoint in state.trajectory.points:
      state.trajectory.pinnedPoint = state.trajectory.closestPoint
      if not kxi.surpressRedraws: redraw(kxi)
  proc onWheel(event: JsObject) = 
    let wheelDelta = event.wheelDelta.to(float)
    if wheelDelta != 0:
      let change = wheelDelta * (canonInitialSpeed / 4800)
      state.canon.state.setSpeed(state.canon.state.speed + change)
      state.calcTrajectory()

  with state:
    onMousedown = onMousedown
    onMouseup = onMouseup
    onMousemove = onMousemove
    onMouseleave = onMouseleave
    onWheel = onWheel

  let pasiveTrue = JsObject{passive: true}

  state.mouse.element.addEventListener("mousedown", state.onMousedown, 
    pasiveTrue)

  # matter-js mouseup event removes the button that was released :shrug:
  # so we remove their event before adding our own to be able to see it
  state.mouse.element.removeEventListener("mouseup", state.mouse.mouseup)
  state.mouse.element.addEventListener("mouseup", state.onMouseup, 
    pasiveTrue)
  state.mouse.element.addEventListener("mouseup", state.mouse.mouseup, 
    pasiveTrue)

  state.mouse.element.addEventListener("mousemove", state.onMousemove, 
    pasiveTrue)

  state.mouse.element.addEventListener("mouseleave", state.onMouseleave, 
    pasiveTrue)

  state.mouse.element.addEventListener("wheel", state.onWheel)

  Events.on(state.engine, "afterUpdate", 
    proc(event: JsObject) = state.onAfterUpdate(event))

  Events.on(state.engine, "collisionStart", 
    proc(event: JsObject) = state.onCollisionStart(event))

  Events.on(state.render, "beforeRender", 
    proc(event: JsObject) = state.onBeforeRender(event))

  Events.on(state.render, "afterRender", 
    proc(event: JsObject) = state.onAfterRender(event))

  Events.on(state.engine.world, "afterAdd", 
    proc(event: JsObject) = state.onAfterAdd(event))

proc onImagesLoaded*(state: var ParabolaState) = 
  Render.run(state.render)

  let canonImg = state.canonImg or JsObject{width: 1, height: 1}
  let canonBaseImg = state.canonBaseImg or JsObject{width: 1, height: 1}
  let canonPlatformImg = state.canonPlatformImg or JsObject{width: 1, height: 1}

  Body.scale(state.canon.body, canonImg.width, canonImg.height)
  Body.scale(state.canon.base.body, canonBaseImg.width, canonBaseImg.height)
  Body.scale(state.canon.platform.body, canonPlatformImg.width, canonPlatformImg.height)

  state.onResize(trajectory = false, first = true)
  state.rotateCanonBack(degToRad(60d))
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
    JsObject{zIndex: 1, friction: 1, isStatic: true, label: cstring"Ground"}
  ) # 350, 495, 1200
  state.ground.xratio = 0.5
  state.ground.yratio = 1

  state.thingy = Bodies.rectangle(state.canvas.clientWidth / 2, state.canvas.clientHeight.float * 0.6, 20, 80, JsObject{isStatic: false, label: cstring"Thing.y", plugin: JsObject{wrap: state.wrapObject}})

  state.mouse = Mouse.create(state.canvas)
  #state.mouseConstraint = MouseConstraint.create(state.engine, JsObject{mouse: state.mouse, collisionFilter: JsObject{mask: 0}})
  state.render.mouse = state.mouse

  let roof = Bodies.rectangle(350, -1000, 1000, 20, JsObject{isStatic: true, label: cstring"Roof"})
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
  state.unloadEvents()
  state = initParabolaState()
  state.load()

## Since matter measures y from the top of the screen, here we "normalize" it so that the 0 starts at the ground
proc normalizeY(state: ParabolaState, y: float, height: float): float =
  -y + (state.ground.position.y.to(float) - (groundHeight / 2) - height)

proc togglePause(state: var ParabolaState) = 
  if state.paused:
    state.engine.timing.timeScale = timeScale
  else:
    state.engine.timing.timeScale = 0

  state.paused = not state.paused

proc renderTopDiv*(state: ParabolaState): VNode =
  var siInitialState = state.canon.state.toMu()
 
  buildHtml tdiv(id = "text", style = "".toCss):
    #p(text r"\(t_f = \frac{2 \cdot v_i \cdot \sin(\theta)}{g}\)", style = "font-size: 50px;".toCss)

    p(text &"h = {siInitialState.height.round(state.floatPrecision)}")
    p(text &"α = {siInitialState.angleDeg.round(state.floatPrecision)}")

    p(text &"Vi = {siInitialState.speed.round(state.floatPrecision)}")

    p(text &"total time = {state.trajectory.totalTime.round(state.floatPrecision)}")

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
        state.rotateCanonBack()
        state.calcTrajectory()

    button():
      span(class = "material-symbols-outlined", text "rotate_right")
      proc onclick() =
        state.rotateCanon()
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
    point = trajectory.points[trajectory.closestPoint].toMu()
  elif not trajectory.dragging and trajectory.pinnedPoint in trajectory.points:
    show = true
    point = trajectory.points[trajectory.pinnedPoint].toMu()

  buildHtml tdiv(id = "text", style = "display: inline-flex;gap: 25px;".toCss):
    if show:
      p(text &"x = {point.pos.x.round(state.floatPrecision)} y = {point.pos.y.round(state.floatPrecision)}")
      p(text &"t = {point.time.round(state.floatPrecision)}")

      p(text &"Vx = {point.vel.x.round(state.floatPrecision)}")
      p(text &"Vy = {point.vel.y.round(state.floatPrecision)}")

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
      state.rotateCanon()
      state.calcTrajectory()
    of "ArrowLeft":
      state.rotateCanonBack()
      state.calcTrajectory()
    of "ArrowUp":
      state.canon.state.setSpeed(state.canon.state.speed + canonSpeedChange)
      state.calcTrajectory()
    of "ArrowDown":
      state.canon.state.setSpeed(state.canon.state.speed - canonSpeedChange)
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
