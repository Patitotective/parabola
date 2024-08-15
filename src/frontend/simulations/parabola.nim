import std/[math, jsffi, times, dom, jsconsole, enumerate, with, strformat, 
  asyncjs, algorithm, strutils, parseutils, sugar]
import karax/[karax, karaxdsl, vdom, vstyles]

import matter, utils, mouseconstraint

type
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
    imgSize*: Vec

  TrajectoryPoint = object
    pos*, vel*: Vec
    time*, speed*: float

  Trajectory = object
    state*: CanonState
    points*: seq[TrajectoryPoint]
    highestPoint*: int
    closestPoint*: int # Closest point to the mouse
    extraPoint*: int # When you change a variable through the inputs, a new point
    # is created with the exact value you entered. This field points to its index
    pinnedPoint*: int
    color*: int # Index of trajectoryStrokeStyles

  Canon = object
    platform*: CanonPlatform
    #status*: CanonStatus
    #state*: CanonState
    base*: CanonBase

    body*: JsObject
    pivot*: Vec
    dragOffset*: float

    bullets*: seq[JsObject]
    bulletOptions*: JsObject
    flyingBullets*: seq[int]
    bulletRadius*: int
    bulletsLimit*: int

    dragging*: bool # Is the canon being dragged

    showAngle*: bool
    imgSize*: Vec

  CanonPlatform = object
    body*: JsObject
    imgSize*: Vec

  ParabolaState* = object
    engine*: JsObject
    render*: JsObject
    runner*: JsObject
    canvas*: Element

    # paused is true when the user pauses the simulation
    paused*: bool
    # frozen is true when the simulation pauses itself since there's no movement
    frozen*: bool

    mouse*: JsObject
    mouseCons*: JsObject
    timeAtClick*: Time # the value of getTime() when left-click, used to check double click

    canon*: Canon
    thingy*: JsObject
    ground*: JsObject

    trajectories*: seq[Trajectory]
    currentTrajectory*: int
    draggingPoint*: bool # Is the pinned point being dragged
    followBullet*: bool # Have closestPoint follow the bullet

    bounds*: JsObject
    boundsScale*: JsObject
    boundsScaleTarget*: float

    onMousedown*, onMouseup*, onMousemove*, 
      onMouseleave*, onWheel*: proc(event: JsObject)

    floatPrecision*: range[0..8]
    startedRendering*: bool

template totalTime(t: Trajectory): float = 
  t.points[^1].time

template maxRange(t: Trajectory): float = 
  t.points[^1].pos.x

template maxHeight(t: Trajectory): float = 
  t.points[t.highestPoint].pos.y

# Projectile motion equations
proc calcTotalTime(initialState: CanonState): float = 
  (initialState.vel.y + sqrt(initialState.vel.y^2 + 
    2 * initialState.gravity.y * initialState.height)) / initialState.gravity.y

proc calcMaxRange(initialState: CanonState): float = 
  initialState.vel.x * initialState.calcTotalTime()

proc calcMaxHeight(initialState: CanonState): float = 
  initialState.height + (initialState.vel.y^2 / (2*initialState.gravity.y))

proc calcX(initialState: CanonState, t: float): float = 
  t * initialState.vel.x

proc calcY(initialState: CanonState, t: float): float = 
  initialState.height + (t * initialState.vel.y) - 
    (initialState.gravity.y * t^2) / 2

proc calcPos(initialState: CanonState, t: float): Vec = 
  vec(initialState.calcX(t), initialState.calcY(t))

proc calcVel(initialState: CanonState, t: float): Vec = 
  vec(initialState.vel.x, 
    initialState.vel.y - (initialState.gravity.y * t))

proc calcTime(initialState: CanonState, x: float): float = 
  x / initialState.vel.x

proc calcTime(initialState: CanonState, y: float, sign: bool): float = 
  if sign:
    -(initialState.vel.y + sqrt(
      initialState.vel.y^2 - (2 * initialState.gravity.y * initialState.height) + 
      (2 * initialState.gravity.y * y)
    )) / initialState.gravity.y
  else:
    -(initialState.vel.y - sqrt(
      initialState.vel.y^2 - (2 * initialState.gravity.y * initialState.height) + 
      (2 * initialState.gravity.y * y)
    )) / initialState.gravity.y

proc magnitude(v: Vec): float = 
  sqrt(v.x^2 + v.y^2)

proc path(p: static string): string = 
  when defined(relativePath):
    "./" & p
  else:
    "/public/" & p

const
  fps = 60
  timeScale = 0.025
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

  canonTexture = path "img/canon.png"
  canonBaseTexture = path "img/canonBase.png"
  canonPlatformTexture = path "img/canonPlatform.png"

  trajectoryStrokeStyles = ["Orange", "Salmon", "Crimson", "Pink", "HotPink", "Tomato", 
  "Gold", "Khaki", "Violet", "SlateBlue", "YellowGreen", "LightSeaGreen", 
  "SkyBlue"]
  trajectoryLineWidth = 2
  trajectoryPointRadius = 7 # The radius of the trajectory point hovered by the mouse
  
  velVectorScale = canonInitialSpeed * 0.0015 # Scale of the velocity arrows
  speedLimit = (canonInitialSpeed/2)..(canonInitialSpeed*1.69)
  angleLowerLimit = 0.0 # Lower limit when canon is too close to the floor

  gravities = {"Pluto": 0.7, "Moon": 1.6, "Mercury & Mars": 3.7, "Uranus": 8.7,
    "Venus": 8.9, "Saturn": 9, "Earth": 9.81, "Neptune": 11, "Jupiter": 23.1}

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

proc initTrajectory(): Trajectory = 
  Trajectory(closestPoint: -1, highestPoint: -1, pinnedPoint: -1, extraPoint: -1, 
    state: initCanonState(0, deg = true, 
      canonInitialSpeed, gravity = vec(0, (9.807 * muMeterFactor) / 
        gravityFactor))
  )

template trajectory(state: ParabolaState): Trajectory = 
  state.trajectories[state.currentTrajectory]

#proc trajectory(state: var ParabolaState): var Trajectory = 
#  state.trajectories[state.currentTrajectory]

proc getPos(state: ParabolaState, p: TrajectoryPoint): Vec = 
  ## Converts p.pos into matter-js coordinates
  vec(
    state.canon.pivot.x + p.pos.x,
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
    speed = result.speed.toMuSpeed()

proc wrapObject(state: ParabolaState): JsObject = 
  JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: state.canvas.clientWidth, y: undefined}} # To avoid boilerplate

proc strfloat(state: ParabolaState, f: float): string = 
  let f =
    if f.classify() == fcNegZero: 0.0
    else: f

  formatValue(result, f, &".{state.floatPrecision}f")

proc inputStep(state: ParabolaState): string = 
  if state.floatPrecision > 0:
    &"0.{'0'.repeat(state.floatPrecision-1)}1"
  else: "1" 

proc pause(state: var ParabolaState) = 
  state.runner.enabled = false
  state.paused = true

proc unpause(state: var ParabolaState) = 
  state.runner.enabled = true
  state.paused = false

proc freeze(state: var ParabolaState) = 
  state.pause()
  Matter.Render.stop(state.render)
  # I realized that sometimes the canvas would go blank when it froze so I
  # thought the render might stop and leave the canvas blank so we run it once
  # here to be sure there's something on the canvas
  state.render.runOnce()
  state.frozen = true

proc unfreeze(state: var ParabolaState) = 
  state.unpause()
  Matter.Render.run(state.render)
  state.frozen = false

proc togglePause(state: var ParabolaState) = 
  if state.paused:
    state.unpause()
  else:
    state.pause()

## Since a body's angle can be negative and can be higher than 360, this procedure makes it so it's always positive and inside 0..359
proc normalizeAngle(rad: float, p = false): float =
  result = rad.radToDeg().round(0)
  result -= float(result.int div 360) * 360 # Remove excess rotations

  result = 
    if result < 0:
      abs result
    elif result > 0:
      360 - result
    else: result

proc normalizedAngleDeg(canon: Canon, extraRad = 0.0): float = 
  normalizeAngle(canon.body.angle.to(float) + extraRad)

proc rotationLimit(state: ParabolaState): Slice[float] = 
  if state.trajectory.state.height > state.canon.imgSize.x:
    (0.0)..(360.0)
  elif state.trajectory.state.height > (state.canon.imgSize.y / 2):
    0.0..180.0
  else:
    angleLowerLimit..(180.0-angleLowerLimit)

proc rotateCanon(state: var ParabolaState, rad = degToRad(canonAngleChangeDeg), limit = true) =
  if rad == 0: return

  var rad = rad
  if limit:
    let rotationLimit = state.rotationLimit()

    let desiredAngleDeg = state.canon.normalizedAngleDeg(extraRad = rad)
    if desiredAngleDeg notin rotationLimit:
      let lowerLimit = 
        if desiredAngleDeg > 180: 360.0 + rotationLimit.a
        else: rotationLimit.a

      if abs(desiredAngleDeg - lowerLimit) < 
        abs(desiredAngleDeg - rotationLimit.b):
        rad = degToRad(state.canon.normalizedAngleDeg() - 
          rotationLimit.a)
      else:
        rad = degToRad(state.canon.normalizedAngleDeg() - 
          rotationLimit.b)

  Matter.Body.rotate(state.canon.body, rad, state.canon.pivot.jsVec)

  state.trajectory.state.angleDeg = state.canon.normalizedAngleDeg()
  state.trajectory.state.angleRad = degToRad(float state.trajectory.state.angleDeg)
  state.trajectory.state.vel = speedToVelRad(state.trajectory.state.speed, 
    state.trajectory.state.angleRad)

proc rotateCanonBack(state: var ParabolaState, rad = degToRad(canonAngleChangeDeg), limit = true) =
  state.rotateCanon(-rad, limit)

proc nextBullet(state: var ParabolaState): JsObject = 
  result = Matter.Bodies.circle(
    state.canon.pivot.x, state.canon.pivot.y, 
    state.canon.bulletRadius, state.canon.bulletOptions
  )
  Matter.Body.setAngle(result, state.trajectory.state.angleDeg)
  Matter.Body.setInertia(result, Infinity)

proc findBy[T](points: openArray[TrajectoryPoint], v: T, by: proc(p: TrajectoryPoint): T): tuple[index: int, exactMatch: bool] = 
  var closestDistance = 0.0
  for e, p in points:
    let d = abs(by(p) - v)
    if d == 0:
      return (e, true)
    elif e == 0 or d < closestDistance:
      closestDistance = d
      result.index = e

proc toggleFormula(ele: Element, to: bool, trueVal: string, falseVal = "__"): string = 
  let inp = ele.firstChild
  let label = ele.children[1]
  let icon = Element label.firstChild

  if not to:
    inp.checked = false
    inp.disabled = true

    if label.hasAttribute("data-tooltip"):
      if not label.hasAttribute("old-data-tooltip"):
        label.setAttr("old-data-tooltip", label.getAttribute("data-tooltip"))

      if label.hasAttribute("disabled-data-tooltip"):
        label.setAttr("data-tooltip", label.getAttribute("disabled-data-tooltip"))

    icon.classList.remove("icon-arrow-right")
    icon.classList.add("icon-cross")

    falseVal
  else:
    inp.disabled = false

    if label.hasAttribute("data-tooltip"):
      if label.hasAttribute("old-data-tooltip"):
        label.setAttr("data-tooltip", label.getAttribute("old-data-tooltip"))

    icon.classList.remove("icon-cross")
    icon.classList.add("icon-arrow-right")

    trueVal

proc updateFormulaAccordion(state: var ParabolaState) = 
  var siInitialState = state.trajectory.state.toMu()
  siInitialState.gravity = siInitialState.gravity * gravityFactor
  let vySquared = siInitialState.vel.y ^ 2
  let gTwice = siInitialState.gravity.y * 2
  let gTimesH = siInitialState.gravity.y * siInitialState.height
  let gTimesHTwice = 2 * gTimesH

  let changes = {
    "#vix > label:nth-child(2) > mjx-container:nth-child(2) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.vel.x)}m/s",
    "#vix > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.speed)}m/s",
    "#vix > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mrow:nth-child(5) > mjx-texatom:nth-child(3) > mjx-mi:nth-child(1)":
      &"{siInitialState.angleDeg:.0f}°",
    "#vix > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.vel.x)}m/s",    

    "#viy > label:nth-child(2) > mjx-container:nth-child(2) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#viy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.speed)}m/s",
    "#viy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mrow:nth-child(5) > mjx-texatom:nth-child(3) > mjx-mi:nth-child(1)":
      &"{siInitialState.angleDeg:.0f}°",
    "#viy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",    

    "#maxheight > label:nth-child(2) > mjx-container:nth-child(2) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      toggleFormula(getElementById("maxheight"), state.trajectory.highestPoint != 0, 
        &"{state.strfloat(state.trajectory.maxHeight.toMuDistance)}m"),
    "#mh4 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.height + (vySquared / gTwice))}m",
    "#mh4 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(3)":
      &"{state.strfloat(vySquared / gTwice)}m",
    "#mh4 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.height)}m",
    "#mh2 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-dbox:nth-child(2) > mjx-dtable:nth-child(1) > mjx-row:nth-child(2) > mjx-den:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(gTwice)}m/s²",
    "#mh2 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(vySquared)}m²/s²",
    "#mh2 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.height)}m",
    "#mh1 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-dbox:nth-child(2) > mjx-dtable:nth-child(1) > mjx-row:nth-child(2) > mjx-den:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#mh1 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msup:nth-child(1) > mjx-mrow:nth-child(1) > mjx-mi:nth-child(2)":
       &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#mh1 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.height)}m",

    "#l_f-2 > mjx-container:nth-child(2) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(state.trajectory.totalTime)}s",
    "#tf1 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msqrt:nth-child(5) > mjx-sqrt:nth-child(1) > mjx-box:nth-child(2) > mjx-mrow:nth-child(1) > mjx-msup:nth-child(1) > mjx-mi:nth-child(1)":
      &"({state.strfloat(siInitialState.vel.y)}m/s)",
    "#tf1 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "mjx-mi.mjx-i:nth-child(9)":
      &"{state.strfloat(siInitialState.height)}m",
    "#tf1 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msqrt:nth-child(5) > mjx-sqrt:nth-child(1) > mjx-box:nth-child(2) > mjx-mrow:nth-child(1) > mjx-mrow:nth-child(5) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#tf1 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-dbox:nth-child(2) > mjx-dtable:nth-child(1) > mjx-row:nth-child(2) > mjx-den:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#tf2 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(1)":
       &"{state.strfloat(siInitialState.vel.y)}m/s", 
    "#tf2 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msqrt:nth-child(5) > mjx-sqrt:nth-child(1) > mjx-box:nth-child(2) > mjx-mrow:nth-child(1) > mjx-mi:nth-child(1)":
      &"{state.strfloat(vySquared)}m²/s²", 
    "#tf2 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msqrt:nth-child(5) > mjx-sqrt:nth-child(1) > mjx-box:nth-child(2) > mjx-mrow:nth-child(1) > mjx-mrow:nth-child(5) > mjx-mi:nth-child(5)":
      &"{state.strfloat(gTimesH)}m²/s²", 
    "#tf2 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-dbox:nth-child(2) > mjx-dtable:nth-child(1) > mjx-row:nth-child(2) > mjx-den:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²", 
    "#tf3 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msqrt:nth-child(5) > mjx-sqrt:nth-child(1) > mjx-box:nth-child(2) > mjx-mrow:nth-child(1) > mjx-mi:nth-child(1)":
      &"{state.strfloat(vySquared)}m²/s²", 
    "#tf3 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(1)":
       &"{state.strfloat(siInitialState.vel.y)}m/s", 
    "#tf3 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msqrt:nth-child(5) > mjx-sqrt:nth-child(1) > mjx-box:nth-child(2) > mjx-mrow:nth-child(1) > mjx-mi:nth-child(5)": 
      &"{state.strfloat(gTimesHTwice)}m²/s²",
    "#tf3 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-dbox:nth-child(2) > mjx-dtable:nth-child(1) > mjx-row:nth-child(2) > mjx-den:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#tf4 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-dbox:nth-child(2) > mjx-dtable:nth-child(1) > mjx-row:nth-child(2) > mjx-den:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#tf4 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y)}m/s", 
    "#tf4 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msqrt:nth-child(5) > mjx-sqrt:nth-child(1) > mjx-box:nth-child(2) > mjx-mrow:nth-child(1) > mjx-mrow:nth-child(1) > mjx-mi:nth-child(1)":
      &"{state.strfloat(vySquared + gTimesHTwice)}",
    "#tf5 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",  
    "#tf5 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-dbox:nth-child(2) > mjx-dtable:nth-child(1) > mjx-row:nth-child(2) > mjx-den:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#tf5 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(5)":
      &"{state.strfloat(sqrt(vySquared + gTimesHTwice))}m/s",
    "#tf6 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(siInitialState.vel.y + sqrt(vySquared + gTimesHTwice))}m/s",
    "#tf6 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mstyle:nth-child(3) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-dbox:nth-child(2) > mjx-dtable:nth-child(1) > mjx-row:nth-child(2) > mjx-den:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#tf6 > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat((siInitialState.vel.y + sqrt(vySquared + gTimesHTwice)) / siInitialState.gravity.y)}s",
    
    "#l_f-3 > mjx-container:nth-child(2) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(state.trajectory.maxRange.toMuDistance)}m",
    "#maxRange > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.x)}m/s",
    "#maxRange > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(5)":
      &"{state.strfloat(state.trajectory.totalTime)}s",
    "#maxRange > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(state.trajectory.maxRange.toMuDistance)}m",
  }

  for (query, value) in changes:
    document.querySelector(cstring query).innerText = cstring value

  if state.frozen:
    state.unfreeze()

proc updateStateAccordion(state: var ParabolaState) = 
  var siInitialState = state.trajectory.state.toMu()
  siInitialState.gravity = siInitialState.gravity * gravityFactor

  getElementById("state-input-h").value = cstring state.strfloat(siInitialState.height)
  getElementById("state-input-a").value = cstring &"{siInitialState.angleDeg:.0f}"
  getElementById("state-input-s").value = cstring state.strfloat(siInitialState.speed)
  getElementById("state-input-vx").value = cstring state.strfloat(siInitialState.vel.x)
  getElementById("state-input-vy").value = cstring state.strfloat(siInitialState.vel.y)
  getElementById("state-input-g").value = cstring state.strfloat(siInitialState.gravity.y)

  if state.frozen:
    state.unfreeze()

proc currentPoint(state: ParabolaState): (bool, TrajectoryPoint) = 
  # If followBullet and the bullet is in flight or
  # you're dragging the point
  if state.trajectory.closestPoint in state.trajectory.points and (state.followBullet and 
    state.canon.flyingBullets.len > 0 or state.draggingPoint):
    result = (true, state.trajectory.points[state.trajectory.closestPoint].toMu())
  elif not state.draggingPoint and state.trajectory.pinnedPoint in state.trajectory.points:
    result = (true, state.trajectory.points[state.trajectory.pinnedPoint].toMu())

proc updatePointAccordion(state: var ParabolaState) = 
  let (show, point) = state.currentPoint()

  if show:
    getElementById("point-input-x").value = cstring state.strfloat(point.pos.x)
    getElementById("point-input-y").value = cstring state.strfloat(point.pos.y)
    getElementById("point-input-t").value = cstring state.strfloat(point.time)
    getElementById("point-input-vx").value = cstring state.strfloat(point.vel.x)
    getElementById("point-input-vy").value = cstring state.strfloat(point.vel.y)
    getElementById("point-input-s").value = cstring state.strfloat(point.speed)
  else:
    getElementById("point-input-x").value = ""
    getElementById("point-input-y").value = ""
    getElementById("point-input-t").value = ""
    getElementById("point-input-vx").value = ""
    getElementById("point-input-vy").value = ""
    getElementById("point-input-s").value = ""

  var siInitialState = state.trajectory.state.toMu()
  siInitialState.gravity = siInitialState.gravity * gravityFactor

  let changes = {
    "#x > label:nth-child(2) > mjx-container:nth-child(2) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      getElementById("x").toggleFormula(show, &"{state.strfloat(point.pos.x)}m"),
    "#x > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(point.time)}s",
    "#x > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.vel.x)}m/s",
    "#x > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(point.pos.x)}m",

    "#y > label:nth-child(2) > mjx-container:nth-child(2) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      getElementById("y").toggleFormula(show, &"{state.strfloat(point.pos.y)}m"),
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.height)}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mrow:nth-child(5) > mjx-mi:nth-child(1)":
      &"{state.strfloat(point.time)}s",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mrow:nth-child(5) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(9) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",  
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(9) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-msup:nth-child(5) > mjx-mi:nth-child(1)":
      &"({state.strfloat(point.time)}s)",

    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.height)}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(5)":
      &"{state.strfloat(point.time * siInitialState.vel.y)}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(9) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",  
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(9) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mrow:nth-child(2) > mjx-mi:nth-child(5)":
      &"{state.strfloat(point.time ^ 2)}s²",

    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(3) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.height + (point.time * siInitialState.vel.y))}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(3) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mstyle:nth-child(5) > mjx-mfrac:nth-child(1) > mjx-frac:nth-child(1) > mjx-num:nth-child(1) > mjx-mi:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y * (point.time ^ 2))}m",  

    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(4) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.height + (point.time * siInitialState.vel.y))}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(4) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(5)":
      &"{state.strfloat((siInitialState.gravity.y * (point.time ^ 2)) / 2)}m",  
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(4) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(point.pos.y)}m",

    "#vy > label:nth-child(2) > mjx-container:nth-child(2) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      getElementById("vy").toggleFormula(show, &"{state.strfloat(point.vel.y)}m/s"),
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mrow:nth-child(5) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mrow:nth-child(5) > mjx-mi:nth-child(5)":
      &"{state.strfloat(point.time)}s",

    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mrow:nth-child(3) > mjx-mi:nth-child(5)":
      &"{state.strfloat(siInitialState.gravity.y * point.time)}m/s",
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > mjx-container:nth-child(1) > mjx-math:nth-child(1) > mjx-mi:nth-child(5)":
      &"{state.strfloat(point.vel.y)}m/s"
  }

  for (query, value) in changes:
    document.querySelector(cstring query).innerText = cstring value

  if state.frozen:
    state.unfreeze()

proc calcTrajectory(state: var ParabolaState) =
  var initialState = state.trajectory.state
  initialState.gravity = initialState.gravity * gravityFactor

  let downwards = initialState.angleDeg > 180 and initialState.angleDeg < 360

  # Was the pinned point the highest or the last point?
  let prevHighestPoint = state.trajectory.pinnedPoint in state.trajectory.points and 
    state.trajectory.highestPoint == state.trajectory.pinnedPoint
  let prevLastPoint = state.trajectory.pinnedPoint in state.trajectory.points and 
    state.trajectory.points.high == state.trajectory.pinnedPoint

  var highest = (index: 0, y: 0.0)

  state.trajectory.points.setLen(0)
  for t in countthrough(0.0, initialState.calcTotalTime(), step = delta / 20):
    var point: TrajectoryPoint
    with point:
      time = t.round(state.floatPrecision)
      pos = initialState.calcPos(point.time)
      vel = initialState.calcVel(point.time)
      speed = point.vel.magnitude()

    state.trajectory.points.add point

    if not downwards and point.pos.y > highest.y:
      highest = (state.trajectory.points.high, point.pos.y)

  state.trajectory.highestPoint = highest.index

  if not downwards: # Don't calculate highest point when the canon is downwards
    var highestPoint = state.trajectory.points[highest.index]
    var initialStateB = initialState
    initialStateB.height = 0

    highestPoint.pos.y = initialState.calcMaxHeight().round(state.floatPrecision)
    highestPoint.time = (initialStateB.calcTotalTime() / 2).round(state.floatPrecision)
    highestPoint.pos.x = initialState.calcX(highestPoint.time).round(state.floatPrecision)
    highestPoint.vel.y = 0
    highestPoint.speed = highestPoint.vel.magnitude()

    state.trajectory.points[highest.index] = highestPoint

  with state.trajectory.points[^1]:
    pos = vec(initialState.calcMaxRange().round(state.floatPrecision), 0)

  if prevHighestPoint and not downwards:
    state.trajectory.pinnedPoint = highest.index
  elif prevLastPoint:
    state.trajectory.pinnedPoint = state.trajectory.points.high

  state.updateStateAccordion()
  state.updatePointAccordion()
  state.updateFormulaAccordion()

## The difference of canon's y respect base's y
proc canonYDiff(state: ParabolaState): float = 
  state.canon.base.imgSize.y * 0.15

proc baseYRange(state: ParabolaState): Slice[float] = 
  # Remember matter-js's y starts from the top
  (state.canon.imgSize.x + state.canonYDiff)..(state.canvas.clientHeight.float - groundHeight.float + state.canonYDiff)

proc canonYRange(state: ParabolaState): Slice[float] = 
  # Remember matter-js's y starts from the top
  state.canon.imgSize.x..(state.baseYRange.b - state.canonYDiff)

proc moveCanonTo(state: var ParabolaState, y: float = -1, first = false) = 
  # We rotate it to 0 to be able to position it correctly
  let canonPrevAngle = state.canon.body.angle.to(float) 
  state.rotateCanon(-canonPrevAngle, limit = false)

  let desiredBaseY = 
    if y < 0:
      if first: state.baseYRange.b
      else: state.canon.base.body.getY()
    else:
      y

  let baseY = clamp(desiredBaseY, state.baseYRange)
  state.canon.base.body.setY baseY

  let canonY = clamp(baseY - state.canonYDiff, state.canonYRange)
  let canonX = state.canon.base.body.getX() + (state.canon.imgSize.x / 3)

  state.canon.body.setPos canonX, canonY
  
  state.canon.pivot = vec(state.canon.base.body.getX(), canonY)
  state.trajectory.state.height = state.canvas.clientHeight.float - groundHeight.float - canonY

  let platformY = (baseY * 1.02) + (state.canon.platform.imgSize.y / 2)
  state.canon.platform.body.setY platformY

  state.rotateCanon(canonPrevAngle, limit = false)

proc onResize(state: var ParabolaState, first = false) = 
  if not first and not state.startedRendering: return 

  state.render.canvas.width = state.canvas.clientWidth
  state.render.canvas.height = state.canvas.clientHeight

  let wrap = state.wrapObject()

  if not state.canon.bulletOptions.to(bool):
    state.canon.bulletOptions = JsObject{plugin: JsObject{wrap: wrap}}
  else:
    state.canon.bulletOptions.plugin = JsObject{wrap: wrap}

  for b in Matter.Composite.allBodies(state.engine.world).to(seq[JsObject]):
    if b.hasOwnProperty("plugin") and b.plugin.hasOwnProperty("wrap"):
      b.plugin.wrap = wrap

    if b.hasOwnProperty("xratio"):
      let pos = JsObject{x: state.canvas.clientWidth.toJs * b.xratio, y: b.position.y}
      Matter.Body.setPosition(b, pos)

    if b.hasOwnProperty("yratio"):
      Matter.Body.setPosition(b, JsObject{x: b.position.x, y: state.canvas.clientHeight.toJs * b.yratio})

  let y = 
    if state.canon.base.dragging:
      state.mouse.position.y.to(float) + state.canon.base.dragOffset
    else: -1
  state.moveCanonTo(y, 
    first = first)

  if not first:
    state.calcTrajectory()

#proc `bullet`(canon: Canon): JsObject = 
#  assert canon.currentBullet in canon.bullets, &"Invalid bullet index {canon.currentBullet}"
#  canon.bullets[canon.currentBullet]    

proc fireBullet(state: var ParabolaState) = 
  let bullet = state.nextBullet()

  for b in state.canon.flyingBullets:
    # Do not fire bullets at the same time, since if they are in the same position
    # You probably are firing them too quickly or while paused
    if state.canon.bullets[b].getPos() == bullet.getPos():
      return

  # If the limit is exceed by the double, remove half of the bullets
  if state.canon.bullets.len + 1 > state.canon.bulletsLimit * 2:
    var toDelete: seq[int]
    for i in countup(0, state.canon.bullets.len - state.canon.bulletsLimit):
      Matter.Composite.remove(state.engine.world, state.canon.bullets[i])
      toDelete.add i

    for i in countdown(toDelete.high, toDelete.low):
      state.canon.bullets.delete(toDelete[i])
      if (let a = state.canon.flyingBullets.find(toDelete[i]); a >= 0):
        state.canon.flyingBullets.delete(a)

    if toDelete.len > 0:
      # Lower each index by the number of bullets deleted since we deleted one
      for i in state.canon.flyingBullets.mitems:
        for di in toDelete:
          if i > di:
            dec i

  elif state.canon.bullets.len + 1 > state.canon.bulletsLimit:
    for i in countup(0, state.canon.bullets.len - state.canon.bulletsLimit):
      state.canon.bullets[i].collisionFilter.mask = 0
      # If we change the mask but don't wake them, they stay there without being
      # able to collide with anything, but still since they are sleeping
      if state.canon.bullets[i].isSleeping.to(bool):
        Matter.Sleeping.set(state.canon.bullets[i], false)
      # If the bullet of index 0 is in flyingBullets, delete it
      if (let a = state.canon.flyingBullets.find(i); a >= 0):
        state.canon.flyingBullets.delete(a)

  Matter.Composite.add(state.engine.world, bullet)
  state.canon.bullets.add bullet
  state.canon.flyingBullets.add state.canon.bullets.high

  # Invert vel y since matter's coordinates start from the top instead of the bottom
  Matter.Body.setVelocity(bullet, jsVec(state.trajectory.state.vel.x, -state.trajectory.state.vel.y))

  if state.frozen:
    state.unfreeze()

proc calcClosestTrajectoryPoint(state: var ParabolaState, point: Vec, minRange = false) = 
  ## Calculates the closest trajectory point to point
  ## If minRange, ignore points further than minRangeDistance
  const minRangeDistance = 40
  var
    result = -1
    closestDistance = 0.0
    bulletsPoints: seq[int] # Closest points to each bullet
    bulletsDistance: seq[float] # Closest distance to each bullet

  let
    trjctry = state.trajectory
    calcBullet = state.paused and state.canon.flyingBullets.len > 0

  for e, p in trjctry.points:
    let d = distance(state.getPos(p), point)
    if result < 0 or d < closestDistance:
      closestDistance = d
      result = e

    if calcBullet:
      for i, bi in state.canon.flyingBullets:
        let b = state.canon.bullets[bi]
        let d = distance(state.getPos(p), b.getPos())
        if i > bulletsDistance.high:
          bulletsDistance.add 0.0
        if i > bulletsPoints.high:
          bulletsPoints.add -1

        if bulletsPoints[i] < 0 or d < bulletsDistance[i]:
          bulletsDistance[i] = d
          bulletsPoints[i] = e

  result = 
    if minRange and closestDistance > minRangeDistance:
      -1 
    elif result != trjctry.highestPoint and 
      distance(state.getPos(trjctry.points[result]), 
        state.getPos(trjctry.points[trjctry.highestPoint])) < 10:
      trjctry.highestPoint
    elif calcBullet:
      var closestBulletPoint = -1
      var closestBulletDistance = 0.0
      for i, _ in state.canon.flyingBullets:
        # Distance betweeen the closest point to point and the closest point to
        # the flying bullet i
        let d = distance(state.getPos(trjctry.points[result]), 
          state.getPos(trjctry.points[bulletsPoints[i]]))

        if bulletsPoints[i] >= 0 or d < 8:
          if closestBulletPoint < 0 or d < closestBulletDistance:
            closestBulletPoint = bulletsPoints[i]
            closestBulletDistance = d

      if closestBulletDistance < 8: 
        closestBulletPoint
      else: result
    else: result

  state.trajectory.closestPoint = result

proc calcClosestTrajectoryPointToBullet(state: var ParabolaState, index = -1) = 
  ## Calculates the closest trajectory point to point
  ## If minRange, ignore points further than minRangeDistance
  if state.canon.flyingBullets.len == 0:
    state.trajectory.closestPoint = -1
    return

  let bullet = 
    if index < 0:
      state.canon.bullets[state.canon.flyingBullets[^1]]
    else:
      state.canon.bullets[index]

  const minRangeDistance = 40
  var
    result = -1
    closestDistance = 0.0

  let
    trjctry = state.trajectory

  for e, p in trjctry.points:
    let d = distance(state.getPos(p), bullet.getPos())
    if result < 0 or d < closestDistance:
      closestDistance = d
      result = e

  state.trajectory.closestPoint = 
    if closestDistance > minRangeDistance:
      -1 
    else: result

proc initParabolaState*(): ParabolaState = 
  result = ParabolaState(
    boundsScale: JsObject{x: 1, y: 1},
    boundsScaleTarget: 1, 
    floatPrecision: 2,
    canon: Canon(bulletRadius: 20, bulletsLimit: 11,
      bulletOptions: JsObject{
        zIndex: 0, isStatic: false, frictionAir: 0, friction: 1, frictionStatic: 1, 
        collisionFilter: JsObject{mask: 0}, sleepThreshold: 1, label: cstring"bullet",
      }),
    trajectories: @[initTrajectory()],
  )

proc onAfterUpdate(state: var ParabolaState, event: JsObject) = 
  try:
    if state.canon.flyingBullets.len > 0:
      if state.followBullet and not state.paused:
        state.calcClosestTrajectoryPointToBullet()
        state.updatePointAccordion()

    # Sequence of bullets to delete from bullets since they went under the floor
    var toDelete: seq[int]
    for e, b in state.canon.bullets:
      # If the bullet is above the floor, make it able to collide with the ground
      if b.getY > state.canvas.clientHeight.float + b.circleRadius.to(float):
        Matter.Composite.remove(state.engine.world, b)
        toDelete.add e

      elif e in state.canon.flyingBullets and b.collisionFilter.mask == 0.toJs and
        b.getY < state.canvas.clientHeight.float - 
        groundHeight - (b.circleRadius.to(float)):

        b.collisionFilter.mask = 2

    for i in countdown(toDelete.high, toDelete.low):
      state.canon.bullets.delete(toDelete[i])
      if (let a = state.canon.flyingBullets.find(toDelete[i]); a >= 0):
        state.canon.flyingBullets.delete(a)

    if toDelete.len > 0:
      # Lower each index by the number of bullets deleted since we deleted one
      for i in state.canon.flyingBullets.mitems:
        for di in toDelete:
          if i > di:
            dec i

    # Freeze the simulation if every non-static body is sleeping
    var freeze = true
    for b in Matter.Composite.allBodies(state.engine.world).to(seq[JsObject]):
      if not b.isSleeping.to(bool) and not b.isStatic.to(bool):
        freeze = false

      if b.speed.to(float) > 1000:
        Matter.Body.setSpeed(b, 10)
    
    if freeze and not state.canon.base.dragging and not state.canon.dragging and 
      not state.draggingPoint and not (state.followBullet and state.canon.flyingBullets.len > 0):
      state.freeze()
  except:
    state.pause()
    raise

proc onCollisionStart(state: var ParabolaState, event: JsObject) = 
  if state.canon.flyingBullets.len > 0:
    for pair in items(event.pairs):
      # Sequence of bullets to delete from flyingBullets since the mouse
      # constraint grabbed them
      var toDelete: seq[int]
      for i, bi in state.canon.flyingBullets:
        let b = state.canon.bullets[bi]
        if pair.bodyA.id == b.id or pair.bodyB.id == b.id:
          #let floorCollision = pair.bodyA.id == state.ground.id or pair.bodyB.id == state.ground.id
          let collision = pair.bodyA.collisionFilter.category.to(int) == 2 or
            pair.bodyB.collisionFilter.category.to(int) == 2
          
          if collision:
            b.frictionAir = 0.1
            b.collisionFilter.mask = 3
            toDelete.add i

            if state.followBullet:
              state.trajectory.pinnedPoint = state.trajectory.points.high
              state.trajectory.closestPoint = state.trajectory.pinnedPoint
              state.updatePointAccordion()

      for i in countdown(toDelete.high, toDelete.low):
        state.canon.flyingBullets.delete(toDelete[i])

proc onBeforeRender(state: var ParabolaState, event: JsObject) = 
  return
  # WIP zoom
  #let mouse = state.mouse
  #var scaleFactor = mouse.wheelDelta.to(float) * -0.1

  #if state.boundsScaleTarget + scaleFactor >= 1 and 
  #  (scaleFactor < 0 and state.boundsScale.x.to(float) >= 0.6 or 
  #    scaleFactor > 0 and state.boundsScale.x.to(float) <= 1.4):
  #  state.boundsScaleTarget += scaleFactor

  ## if scale has changed
  #if abs(state.boundsScale.x.to(float) - state.boundsScaleTarget) > 0.01:
  #  # smoothly tween scale factor
  #  scaleFactor = (state.boundsScaleTarget - state.boundsScale.x.to(float)) * 0.2
  #  state.boundsScale.x += toJs scaleFactor
  #  state.boundsScale.y += toJs scaleFactor

  #  # scale the render bounds
  #  state.render.bounds.max.x = state.render.bounds.min.x + state.render.options.width.toJs * state.boundsScale.x
  #  state.render.bounds.max.y = state.render.bounds.min.y + state.render.options.height.toJs * state.boundsScale.y

  #  # translate so zoom is from centre of view
  #  let translate = JsObject{
  #    x: state.render.options.width.to(float) * scaleFactor * -0.5,
  #    y: state.render.options.height.to(float) * scaleFactor * -0.5
  #  }

  #  Matter.Bounds.translate(state.render.bounds, translate)

  #  # update mouse
  #  Matter.Mouse.setScale(mouse, state.boundsScale)
  #  Matter.Mouse.setOffset(mouse, state.render.bounds.min)

  ## get vector from mouse relative to centre of viewport
  #var viewportCentre = JsObject{
  #  x: state.render.options.width * toJs 0.5,
  #  y: state.render.options.height * toJs 0.5
  #}
  #let deltaCentre = Matter.Vector.sub(mouse.absolute, viewportCentre)
  #let centreDist = Matter.Vector.magnitude(deltaCentre)

  ## translate the view if mouse has moved over 50px from the centre of viewport
  #if centreDist.to(float) > 50:
  #  # create a vector to translate the view, allowing the user to control view speed
  #  let direction = Matter.Vector.normalise(deltaCentre)
  #  let speed = min(10, pow(centreDist.to(float) - 50, 2) * 0.0002)

  #  let translate = Matter.Vector.mult(direction, speed)

  #  # prevent the view moving outside the extens (bounds)
  #  if to(state.render.bounds.min.x + translate.x < state.bounds.min.x, bool):
  #    translate.x = state.bounds.min.x - state.render.bounds.min.x

  #  if to(state.render.bounds.max.x + translate.x > state.bounds.max.x, bool):
  #    translate.x = state.bounds.max.x - state.render.bounds.max.x

  #  if to(state.render.bounds.min.y + translate.y < state.bounds.min.y, bool):
  #    translate.y = state.bounds.min.y - state.render.bounds.min.y

  #  if to(state.render.bounds.max.y + translate.y > state.bounds.max.y, bool):
  #    translate.y = state.bounds.max.y - state.render.bounds.max.y

  #  # move the view
  #  Matter.Bounds.translate(state.render.bounds, translate)

  #  # we must update the mouse too
  #  Matter.Mouse.setOffset(mouse, state.render.bounds.min)

proc drawVelocityArrows(state: ParabolaState, ctx: JsObject) = 
  for bi in state.canon.flyingBullets:
    let b = state.canon.bullets[bi]
    const
      threshold = 4.0
      arrowWidth = 3
    if b.velocity.y.to(float) notin -threshold..threshold:
      drawArrow(ctx, b.position.x, b.position.y, 
        b.position.x,
        b.position.y + (b.velocity.y * toJs velVectorScale), 
        toJs arrowWidth, toJs cstring"red"
      )

    if b.velocity.x.to(float) notin -threshold..threshold:
      drawArrow(ctx, b.position.x, b.position.y, 
        b.position.x + (b.velocity.x * toJs velVectorScale), 
        b.position.y,
        toJs arrowWidth, toJs cstring"#3FD0F6" # Neon blue
      )

    if b.velocity.x.to(float) notin -threshold..threshold or 
      b.velocity.y.to(float) notin -threshold..threshold:
      drawArrow(ctx, b.position.x, b.position.y, 
        b.position.x + (b.velocity.x * toJs velVectorScale), 
        b.position.y + (b.velocity.y * toJs velVectorScale), 
        toJs arrowWidth, toJs cstring"white"
      )

proc drawTrajectory(state: ParabolaState, ctx: JsObject) = 
  for e, trjctry in state.trajectories:
    if trjctry.points.len == 0: continue

    ctx.beginPath()
    let pos0 = state.getPos(trjctry.points[0])
    ctx.moveTo(pos0.x, pos0.y)

    ctx.strokeStyle = cstring trajectoryStrokeStyles[trjctry.color]
    ctx.lineWidth = trajectoryLineWidth

    for e, p in trjctry.points[1..^1]:
      let pos = state.getPos(p)
      ctx.lineTo(pos.x, pos.y)

    ctx.stroke()

  if state.currentTrajectory notin state.trajectories:
    return

  # Draw points
  ctx.fillStyle = cstring"#47D916"

  if state.trajectory.highestPoint in state.trajectory.points:
    let middlePos = state.getPos(state.trajectory.points[state.trajectory.highestPoint])
    ctx.beginPath()
    ctx.arc(middlePos.x, middlePos.y, 
      int(trajectoryPointRadius.float * 0.8), 0, 2 * PI
    )
    ctx.fill()

  if state.trajectory.points.len > 0:
    let lastPos = state.getPos(state.trajectory.points[^1])
    ctx.beginPath()
    ctx.arc(lastPos.x, lastPos.y, 
      int(trajectoryPointRadius.float * 0.8), 0, 2 * PI
    )
    ctx.fill()

  let (drawPoint, pos) = 
    if (state.followBullet and state.canon.flyingBullets.len > 0):
      (false, Vec.default)
    elif state.draggingPoint and state.trajectory.closestPoint in state.trajectory.points:
      (true, state.getPos(state.trajectory.points[state.trajectory.closestPoint]))
    elif not state.draggingPoint and state.trajectory.pinnedPoint in state.trajectory.points:
      (true, state.getPos(state.trajectory.points[state.trajectory.pinnedPoint]))
    else: (false, Vec.default)

  if drawPoint:
    ctx.fillStyle = cstring"#16B0D9"
    ctx.beginPath()
    ctx.arc(pos.x, pos.y, 
      trajectoryPointRadius, 0, 2 * PI
    )
    ctx.fill()

proc drawHeight(state: ParabolaState, ctx: JsObject) = 
  # So that when clientHeight is 621, size is 25
  #let fontSize = int round(state.canvas.clientHeight.float * 
  #  0.040257648953301126, 0)
  const width = 20
  let text = &"{state.strfloat(state.trajectory.state.height.toMuDistance)}m"
  let xOffset = -(state.canon.platform.imgSize.x / 2) - 10

  if state.trajectory.state.height > 0:
    ctx.beginPath()
    ctx.moveTo(state.canon.pivot.x + xOffset - width, 
      state.canvas.clientHeight.float - groundHeight)
    ctx.lineTo(state.canon.pivot.x + xOffset, 
      state.canvas.clientHeight.float - groundHeight)

    ctx.moveTo(state.canon.pivot.x + xOffset - width, 
      state.canvas.clientHeight.float - groundHeight - state.trajectory.state.height)
    ctx.lineTo(state.canon.pivot.x + xOffset, 
      state.canvas.clientHeight.float - groundHeight - state.trajectory.state.height)

    ctx.moveTo(state.canon.pivot.x + xOffset - (width / 2), 
      state.canvas.clientHeight.float - groundHeight)
    ctx.lineTo(state.canon.pivot.x + xOffset - (width / 2), 
      state.canvas.clientHeight.float - groundHeight - state.trajectory.state.height)

    ctx.strokeStyle = cstring"white"
    ctx.lineWidth = 1
    ctx.stroke()

  ctx.font = cstring "22px serif"
  ctx.fillStyle = cstring"white"
  ctx.shadowColor = cstring"black"
  ctx.shadowOffsetX = 2
  ctx.shadowOffsetY = 2

  let metrics = ctx.measureText(cstring text)
  let twidth = metrics.width.to(float).clamp(50.0..100.0)
  let theight = to(metrics.actualBoundingBoxAscent + 
    metrics.actualBoundingBoxDescent, float).clamp(10.0..25.0)

  ctx.fillText(cstring text, 
    state.canon.pivot.x + xOffset - (width / 2) - twidth - 5,
    state.canvas.clientHeight.float - groundHeight - (state.trajectory.state.height / 2) - (theight / 2))

  ctx.shadowOffsetX = 0
  ctx.shadowOffsetY = 0

proc drawRange(state: ParabolaState, ctx: JsObject) = 
  const
    height = 10
    yOffset = groundHeight - 35

  let text = &"{state.strfloat(state.trajectory.maxRange.toMuDistance)}m"
  
  if state.trajectory.maxRange != 0:
    ctx.beginPath()
    ctx.moveTo(state.canon.pivot.x, 
      state.canvas.clientHeight.float - groundHeight + yOffset)
    ctx.lineTo(state.canon.pivot.x, 
      state.canvas.clientHeight.float - groundHeight + yOffset + height)

    ctx.moveTo(state.canon.pivot.x + state.trajectory.maxRange, 
      state.canvas.clientHeight.float - groundHeight + yOffset)
    ctx.lineTo(state.canon.pivot.x + state.trajectory.maxRange, 
      state.canvas.clientHeight.float - groundHeight + yOffset + height)

    ctx.moveTo(state.canon.pivot.x, 
      state.canvas.clientHeight.float - groundHeight + yOffset + (height / 2))
    ctx.lineTo(state.canon.pivot.x + state.trajectory.maxRange ,
      state.canvas.clientHeight.float - groundHeight + yOffset + (height / 2))

    ctx.strokeStyle = cstring"white"
    ctx.lineWidth = 1
    ctx.stroke()

  ctx.font = cstring "22px serif"
  ctx.fillStyle = cstring"white"
  ctx.shadowColor = cstring"black"
  ctx.shadowOffsetX = 2
  ctx.shadowOffsetY = 2

  let textWidth = ctx.measureText(cstring text).width.to(float).clamp(50.0..100.0)

  ctx.fillText(cstring text, 
    state.canon.pivot.x + (state.trajectory.maxRange / 2) - (textWidth / 2),
    state.canvas.clientHeight.float - (groundHeight / 2))

  ctx.shadowOffsetX = 0
  ctx.shadowOffsetY = 0

proc drawAngle(state: ParabolaState, ctx: JsObject) = 
  ctx.lineWidth = 2
  ctx.strokeStyle = cstring"#C7C7D1"
  let radius = state.canon.imgSize.x / 1.25

  ctx.beginPath()
  ctx.moveTo(state.canon.pivot.x, state.canon.pivot.y)
  ctx.lineTo(state.canon.pivot.x + radius, state.canon.pivot.y)
  ctx.arc(state.canon.pivot.x, state.canon.pivot.y, radius, 
    0, -state.trajectory.state.angleRad, true)
  ctx.stroke()

  let angle = abs(state.trajectory.state.angleDeg)
  let text = &"{angle:.0f}°"
    #if angle.int.float == angle: # If it doesn't have decimals
    #  &"{angle:.0f}°"
    #else:
    #  &"{state.strfloat(angle)}°"
  ctx.font = cstring "22px serif"
  ctx.fillStyle = cstring"white"
  ctx.shadowColor = cstring"black"
  ctx.shadowOffsetX = 2
  ctx.shadowOffsetY = 2

  ctx.fillText(cstring text, 
    state.canon.pivot.x + radius + 10, 
    state.canon.pivot.y - 10)

  ctx.shadowOffsetX = 0
  ctx.shadowOffsetY = 0

proc onAfterRender(state: var ParabolaState, event: JsObject) = 
  try:
    Matter.Render.startViewTransform(state.render)
    let ctx = state.render.context

    state.drawVelocityArrows(ctx)

    # Draw trajectory
    if state.trajectory.points.len > 0:
      state.drawTrajectory(ctx)
      state.drawAngle(ctx)
      state.drawHeight(ctx)
      state.drawRange(ctx)

    discard Matter.Render.endViewTransform(state.render)
  except:
    state.pause()
    raise

proc onAfterAdd(state: var ParabolaState, event: JsObject) = 
  ## Sort bodies by z-index/depth
  state.engine.world.bodies = state.engine.world.bodies.to(seq[JsObject]).sorted(proc(a, b: JsObject): int =
    let z1 = if a.zIndex.isNil: 0 else: a.zIndex.to(float).int
    let z2 = if b.zIndex.isNil: 0 else: b.zIndex.to(float).int
    z1 - z2
  )

proc onStartdrag(state: var ParabolaState, event: JsObject) = 
  var toDelete: seq[int]
  for i, bi in state.canon.flyingBullets:
    let b = state.canon.bullets[bi]
    if event.body.id == b.id:
      b.frictionAir = 0.1
      b.collisionFilter.mask = 3
      toDelete.add i

      if state.followBullet:
        state.trajectory.pinnedPoint = state.trajectory.closestPoint

  for i in countdown(toDelete.high, toDelete.low):
    state.canon.flyingBullets.delete(toDelete[i])

proc unloadEvents(state: var ParabolaState) = 
  state.mouse.element.removeEventListener("mousedown", state.onMousedown)
  state.mouse.element.removeEventListener("mouseup", state.onMouseup)
  state.mouse.element.removeEventListener("mousemove", state.onMousemove)
  state.mouse.element.removeEventListener("mouseleave", state.onMouseleave)
  state.mouse.element.removeEventListener("wheel", state.onWheel)

proc loadEvents(state: var ParabolaState) = 
  proc onMousemove(event: JsObject) = 
    if not state.startedRendering: return

    if state.canon.dragging:
      let targetAngle = Matter.Vector.angle(state.canon.pivot.jsVec, 
        state.mouse.position).to(float) - state.canon.dragOffset
      state.rotateCanon(targetAngle - state.canon.body.angle.to(float))
      state.calcTrajectory()

    elif state.canon.base.dragging:
      state.onResize()
      state.rotateCanon(0) # To check if the canon is in the rotation limit

    elif state.draggingPoint:
      state.calcClosestTrajectoryPoint(state.mouse.position.vec())
      state.updatePointAccordion()

  proc onMousedown(event: JsObject) = 
    if not state.startedRendering: return

    case event.button.to(int)
    of 0:
      let t = getTime()

      if t - state.timeAtClick <= initDuration(milliseconds = 250):
        state.calcClosestTrajectoryPoint(state.mouse.position.vec(), minRange = true)
        if state.trajectory.closestPoint in state.trajectory.points:
          if state.followBullet and state.canon.flyingBullets.len > 0:
            getElementById("point-input-f").checked = false
            state.followBullet = false

          state.draggingPoint = true
          state.updatePointAccordion()
        # If you double clicked outside of the minRange, remove the pinnedPoint
        elif state.trajectory.pinnedPoint in state.trajectory.points:
          state.trajectory.pinnedPoint = -1
          state.updatePointAccordion()
      elif Matter.Bounds.contains(state.canon.base.body.bounds, state.mouse.position).to(bool):
        state.canon.base.dragging = true
        state.canon.base.dragOffset = state.canon.base.body.getY - state.mouse.position.y.to(float)
      elif Matter.Bounds.contains(state.canon.body.bounds, state.mouse.position).to(bool): 
        state.canon.dragging = true
        state.canon.dragOffset = Matter.Vector.angle(state.canon.pivot.jsVec, 
          state.mouse.position).to(float) - state.canon.body.angle.to(float)
      elif Matter.Bounds.contains(state.canon.platform.body.bounds, state.mouse.position).to(bool):
        state.canon.base.dragging = true
        state.canon.base.dragOffset = state.canon.base.body.getY - state.mouse.position.y.to(float)
      elif state.frozen or not state.paused:
        Matter.MouseConstraint.onmousedown(state.mouseCons, Matter.Composite.allBodies(state.engine.world))
        if state.frozen:
          state.unfreeze()

      state.timeAtClick = t
    of 1:
      state.fireBullet()
    else: discard

  proc onMouseup(event: JsObject) = 
    if not state.startedRendering: return

    case event.button.to(int)
    of 0:
      Matter.MouseConstraint.onmouseup(state.mouseCons)
   
      if state.draggingPoint and state.trajectory.closestPoint in state.trajectory.points:
        state.trajectory.pinnedPoint = state.trajectory.closestPoint
        state.updatePointAccordion()

      state.canon.dragging = false
      state.canon.base.dragging = false
      state.draggingPoint = false
    else:
      discard

  proc onMouseleave(event: JsObject) = 
    if not state.startedRendering: return

    # If the mouse leaves the canvas while dragging the base through the
    # bottom, drop the canon base to the floor. Since it's usual that if you
    # move the mouse quickly, the position isn't registered all the time
    # but every frame
    #if state.canon.base.dragging:
    #  if state.mouse.getY() >= state.canvas.clientHeight.float * 0.95:
    #    state.canon.elevated = false
    #    state.onResize()

    if state.draggingPoint and state.trajectory.closestPoint in state.trajectory.points:
      state.trajectory.pinnedPoint = state.trajectory.closestPoint
      state.updatePointAccordion()

    state.canon.dragging = false
    state.canon.base.dragging = false
    state.draggingPoint = false

    # To stop the mouse constraint
    Matter.MouseConstraint.onmouseup(state.mouseCons)
    #state.mouseCons.mouse.button = -1

  proc onWheel(event: JsObject) = 
    if not state.startedRendering: return

    let wheelDelta = event.wheelDelta.to(float)
    if wheelDelta != 0:
      let change = wheelDelta * (canonInitialSpeed / 4800)
      state.trajectory.state.setSpeed(state.trajectory.state.speed + change)
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

  Matter.Events.on(state.engine, "afterUpdate", 
    (event: JsObject) => state.onAfterUpdate(event))

  Matter.Events.on(state.engine, "collisionStart", 
    (event: JsObject) => state.onCollisionStart(event))

  Matter.Events.on(state.render, "beforeRender", 
    (event: JsObject) => state.onBeforeRender(event))

  Matter.Events.on(state.render, "afterRender", 
    (event: JsObject) => state.onAfterRender(event))

  Matter.Events.on(state.engine.world, "afterAdd", 
    (event: JsObject) => state.onAfterAdd(event))

  Matter.Events.on(state.mouseCons, "startdrag", 
    (event: JsObject) => state.onStartdrag(event))

proc onImagesLoaded(state: var ParabolaState) = 
  state.canon.imgSize = state.render.textures[canonTexture].sizeVec()
  state.canon.base.imgSize = state.render.textures[canonTexture].sizeVec()
  state.canon.platform.imgSize = state.render.textures[canonPlatformTexture].sizeVec()

  Matter.Body.scale(state.canon.body, state.canon.imgSize.x, state.canon.imgSize.y)
  Matter.Body.scale(state.canon.base.body, state.canon.base.imgSize.x, 
    state.canon.base.imgSize.y)
  Matter.Body.scale(state.canon.platform.body, state.canon.platform.imgSize.x, 
    state.canon.platform.imgSize.y)

  state.onResize(first = true)
  state.rotateCanonBack(degToRad(60d))
  state.calcTrajectory()

  Matter.Render.run(state.render)

  state.startedRendering = true

#proc typesetMathjax(): Future[void] = 
#  var promise = newPromise() do (resolve: proc()):
#    # Matter.Render all MathJax expressions synchronously
#    (resolve)

## Loads the simulation
proc load*(state: var ParabolaState) =
  # Load wrap's plugin and load matter aliases to point to the correct values
  Matter.use("matter-wrap")

  let gravity = state.trajectory.state.gravity.jsVec()
  gravity.scale = 1

  state.canvas = getElementById("canvas")
  state.canvas.focus()
  state.engine = createEngine(JsObject{gravity: gravity, 
    timing: JsObject{timeScale: timeScale}, 
    enableSleeping: true,
  })
  state.render = createRender(JsObject{
    canvas: state.canvas,
    engine: state.engine,
    options: JsObject{
      width: state.canvas.clientWidth,
      height: state.canvas.clientHeight,
      showAngleIndicator: false,
      showSleeping: false,
      wireframes: false,
      showDebug: false,
      background: "transparent",#"rgb(20, 21, 31)",
    }
  })

  state.runner = Matter.Runner.create(JsObject{fps: fps})
  Matter.Runner.run(state.runner, state.engine)

  state.bounds = JsObject{min: JsObject{x: 0, y: 0}, max: JsObject{x: state.canvas.clientWidth.float * 0.6, y: state.canvas.clientHeight.float * 0.5}}

  # Create and add all bodies to the world
  # onResize will set the correct positions
  state.canon.body = Matter.Bodies.rectangle(0, 0, 1, 1, JsObject{
    zIndex: 3, isStatic: true, collisionFilter: JsObject{mask: 0}, label: cstring"Canon",
    render: JsObject{sprite: JsObject{
      texture: cstring canonTexture, 
      xOffset: 0, yOffset: 0
    }}
  })

  state.canon.base.body = Matter.Bodies.rectangle(0, 0, 1, 1, JsObject{
    zIndex: 4, isStatic: true, collisionFilter: JsObject{mask: 0}, label: cstring"Base",
    render: JsObject{sprite: JsObject{
      texture: cstring canonBaseTexture, 
      xOffset: 0, yOffset: 0
    }}
  })
  state.canon.base.body.xratio = canonXRatio

  state.canon.platform.body = Matter.Bodies.rectangle(0, 0, 1, 1, JsObject{
    zIndex: 1, isStatic: true, collisionFilter: JsObject{mask: 0}, label: cstring"Platform",
    render: JsObject{sprite: JsObject{
      texture: cstring canonPlatformTexture, 
      xOffset: 0, yOffset: 0
    }}
  })
  state.canon.platform.body.xratio = canonXRatio

  state.ground = Matter.Bodies.rectangle(0, 0, state.canvas.clientWidth * 1000, groundHeight * 2, 
    JsObject{zIndex: -1, friction: 1, frictionStatic: 1, isStatic: true, 
      label: cstring"Ground", collisionFilter: JsObject{category: 2, mask: 3}
    }
  ) # 350, 495, 1200
  state.ground.xratio = 0.5
  state.ground.yratio = 1

  state.thingy = Matter.Bodies.rectangle(state.canvas.clientWidth / 2, 
    state.canvas.clientHeight.float * 0.6, 20, 80, 
    JsObject{zIndex: 0, isStatic: false, label: cstring"Thingy", frictionAir: 0.1, 
      friction: 1, frictionStatic: 1, plugin: JsObject{wrap: state.wrapObject}, 
      collisionFilter: JsObject{category: 2, mask: 3}, sleepThreshold: 1,
  })
  #Matter.Body.setInertia(state.thingy, 0.1)

  state.mouse = Matter.Mouse.create(state.canvas)
  state.render.mouse = state.mouse
  
  state.mouseCons = Matter.MouseConstraint.create(state.engine, JsObject{
    mouse: state.mouse, collisionFilter: JsObject{category: 2, mask: 3}, 
    constraint: JsObject{render: JsObject{visible: false}, stiffness: 1}})
  #state.mouseCons.constraint.render.visible = false

  let roof = Matter.Bodies.rectangle(0, -100, 1000, 20, JsObject{
    isStatic: true, label: cstring"Roof"
  })
  roof.xratio = 0.5

  state.loadEvents()

  Matter.Composite.add(state.engine.world, toJs [
    state.canon.body, state.mouseCons,
    state.thingy, state.canon.base.body,
    state.canon.platform.body,
    # Walls
    roof, # up
    # Matter.Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}), # right
    state.ground, # down
    # Matter.Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}), # left
  ])

  # Wait until all textures are loaded
  var loadedImgCount = 0
  var images = newSeq[cstring]()
  for b in Matter.Composite.allBodies(state.engine.world).to(seq[JsObject]):
    if not b.render.sprite.texture.isUndefined and not to(b.render.sprite.texture in state.render.textures, bool):
      images.add b.render.sprite.texture.to(cstring)

  for src in images:
    let img = newImage()
    img.onload = proc() =
      inc loadedImgCount
      if loadedImgCount == images.len:
        # Typeset mathjax expressions before since onImagesLoaded updates them
        MathJax.typesetPromise().then proc() = 
          state.onImagesLoaded()

    img.src = src
    state.render.textures[src] = img

## Reloads the simulation
proc reload*(state: var ParabolaState) =
  Matter.Composite.clear(state.engine.world)
  Matter.Engine.clear(state.engine)
  Matter.Render.stop(state.render)
  Matter.Runner.stop(state.runner)
  state.unloadEvents()
  state = initParabolaState()
  getElementById("point-input-f").checked = false
  state.load()
  if not kxi.surpressRedraws: redraw(kxi)

proc renderLeftDiv(state: var ParabolaState): VNode =
  buildHtml tdiv(id = "sim", class = "column col-8", style = "height: 100%".toCss):
    # tabindex makes it able to focus the canvas
    canvas(id = "canvas", style = toCss "height: 100%; width: 100%; min-width: 500px;" & 
      "min-height: 300px; background: rgb(20, 21, 31); outline: none", tabindex = "0"):
      text "Matter-js simulation"
      proc onclick(e: Event, n: VNode) = 
        n.dom.focus()
      # Doing this because I saw it on matter-js's Matter.Render._createCanvas
      proc oncontextmenu(ev: Event, _: VNode) = ev.preventDefault()
      proc ondragstart(ev: Event, _: VNode) = ev.preventDefault()

proc renderFormulasAccordion(state: var ParabolaState): VNode =
  let liStyle = "margin-top: 20px;".toCss
  let formulaAccordionBodyStyle = "padding-left: 0.5em; overflow: auto; scrollbar-width: thin;".toCss

  buildHtml tdiv(class = "container"):
    tdiv(id = "vix", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f--1", hidden = true, checked = false)
      label(class = "accordion-header tooltip tooltip-bottom", `for` = "accordion-f--1", `data-tooltip` = "Initial vel X"):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(v_{ix} = v\:\cdot\:\cos{\alpha} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(): 
            text r"\(v_{ix} = v\:\cdot\:\cos{a} = d\)"
    
    tdiv(id = "viy", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-0", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f-0", `data-tooltip` = "Initial vel Y"):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(v_{iy} = v\:\cdot\:\sin{\alpha} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(): 
            text r"\(v_{iy} = v\:\cdot\:\sin{a} = d\)"

    tdiv(id = "maxheight", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-1", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f-1", 
        `data-tooltip` = "Max height", `disabled-data-tooltip` = "The canon cannot point downwards"):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(h_{max} = h + \dfrac{2v_{iy}^{2}}{2g} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(id = "mh1"): # font-size: 1.2em;
            text r"\(h_{max} = h + \dfrac{(v)^{2}}{2\:\cdot\:g}\)"
          li(id = "mh2", style = liStyle):
            text r"\(h_{max} = h + \dfrac{v}{g}\)"
          li(id = "mh4", style = liStyle):
            text r"\(h_{max} = h + a = d\)"

    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-2", hidden = true, checked = false)
      label(id = "l_f-2", class = "accordion-header tooltip", `for` = "accordion-f-2", `data-tooltip` = "Time of flight"):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(t_{f} = \dfrac{v_{iy}\:+\:\sqrt{v_{iy}^{2}\:+\:2gh}}{g} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(id = "tf1"): # font-size: 1.2em;
            text r"\(t_{f} = \dfrac{v\:+\:\sqrt{v^{2}\:+\:2\:\cdot\:g\:\cdot\:h}}{g}\)"
          li(id = "tf2", style = liStyle):
            text r"\(t_{f} = \dfrac{v\:+\:\sqrt{v\:+\:2\:\cdot\:a}}{g}\)"
          li(id = "tf3", style = liStyle):
            text r"\(t_{f} = \dfrac{v\:+\:\sqrt{v\:+\:a}}{g}\)"
          li(id = "tf4", style = liStyle):
            text r"\(t_{f} = \dfrac{v\:+\:\sqrt{bm²/s²}}{g}\)"
          li(id = "tf5", style = liStyle):
            text r"\(t_{f} = \dfrac{v\:+\:e}{g}\)"
          li(id = "tf6", style = liStyle):
            text r"\(t_{f} = \dfrac{c}{g} = d\)"

    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-3", hidden = true, checked = false)
      label(id = "l_f-3", class = "accordion-header tooltip", `for` = "accordion-f-3", `data-tooltip` = "Max range"):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(x_{max} = v_{ix}\:\cdot\:t_f = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(id = "maxRange", style = "list-style-type: none;".toCss):
          li(): 
            text r"\(x_{max} = v\:\cdot\:t = d\)"

proc renderStateAccordion(state: var ParabolaState): VNode = 
  proc onInputHChange(e: Event, n: VNode) = 
    if not state.startedRendering: return

    var h = 0.0

    discard parseFloat($n.value, h)
    h = h.fromMuDistance().round(state.floatPrecision).
      clamp(0.0..state.canonYRange.b)

    state.moveCanonTo(state.canvas.clientHeight.float - 
      groundHeight.float - h + state.canonYDiff)
    state.calcTrajectory()
  
  proc onInputAChange(e: Event, n: VNode) = 
    if not state.startedRendering: return

    var a = 0

    discard parseInt($n.value, a)
    a = a.clamp(0..360)
    state.rotateCanon(degToRad(
      state.canon.normalizedAngleDeg() - a.float
    ))
    state.calcTrajectory()

  proc onInputSChange(e: Event, n: VNode) = 
    if not state.startedRendering: return

    var s = 0.0

    discard parseFloat($n.value, s)
    s = s.fromMuSpeed().round(state.floatPrecision)
    state.trajectory.state.setSpeed(s)
    state.calcTrajectory()
  
  proc onInputGChange(e: Event, n: VNode) = 
    if not state.startedRendering: return

    var g = 0.0

    discard parseFloat($n.value, g)
    g = g.clamp(0.7, 23.1).fromMuAcceleration().round(state.floatPrecision)
    state.trajectory.state.gravity.y = g / gravityFactor
    state.engine.gravity.y = state.trajectory.state.gravity.y
    state.calcTrajectory()
  
  proc onPlanetClick(g: float): auto = 
    proc() = 
      let g = g.clamp(0.7, 23.1).fromMuAcceleration().round(state.floatPrecision)
      state.trajectory.state.gravity.y = g / gravityFactor
      state.engine.gravity.y = state.trajectory.state.gravity.y
      state.calcTrajectory()
  
  proc onGAccordChange(checked: bool) = 
    let ele = getElementById("accordion-g-arrow")
    if checked:
      ele.style.setProperty("transform", cstring"rotate(90deg)")
    else:
      ele.style.removeProperty("transform")

  buildHtml form(class = "form-horizontal"):
    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-h"): text "Height"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-h", 
          step = cstring state.inputStep, onchange = onInputHChange)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-a"): text "Angle"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-a", 
          step = "1", onchange = onInputAChange)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-s"): text "Speed"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-s", 
          step = cstring state.inputStep, onchange = onInputSChange)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-vx"): text "Vel X"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-vx", 
          readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-vy"): text "Vel Y"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-vy", 
          readonly = true)

    #tdiv(class = "form-group"): 
    #  tdiv(class = "accordion"):
    #    input(`type` = "checkbox", name  = "accordion-checkbox", 
    #      id = "accordion-g", hidden = true, checked = false)
    #    label(class = "accordion-header", `for` = "accordion-g"):
    #      italic(class = "icon icon-arrow-right mr-1")
      
    #    tdiv(class = "col-3 col-sm-12"):
    #      label(class = "form-label", `for` = "state-input-g"): text "Gravity"
    #    tdiv(class = "col-9 col-sm-12"):
    #      input(class = "form-input form-inline", `type` = "number", id = "state-input-g", 
    #        step = state.inputStep, onchange = onInputGChange)

    #    tdiv(class = "accordion-body"):
    #      text "asdasd"
        
    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-g", hidden = true, checked = false, 
        onchange = proc(_: Event, n: VNode) = onGAccordChange(n.dom.checked))

      label(class = "accordion-header", `for` = "accordion-g", style = "padding: 0 0 0.6rem;".toCss):    
        tdiv(class = "form-group"): 
          tdiv(class = "col-3 col-sm-12", style = "display: ruby;".toCss):
            italic(id = "accordion-g-arrow", class = "icon icon-arrow-right mr-1")
            # We do not use `for` = "state-input-g" here because we want the click
            # to show the planets' gravities
            label(class = "form-label"):
              text "Gravity"
              proc onclick() = 
                let ele = getElementById("accordion-g")
                ele.checked = not ele.checked
                onGAccordChange(ele.checked)

          tdiv(class = "col-9 col-sm-12"):
            input(class = "form-input form-inline", `type` = "number", id = "state-input-g", 
              step = cstring state.inputStep, onchange = onInputGChange)

      tdiv(class = "accordion-body"):
        for e, (name, gravity) in gravities:
          button(`type` = "button", class = "btn", onclick = onPlanetClick(gravity),
            style = "display: inline;".toCss):
            text name

    # To disable form submit on enter https://stackoverflow.com/questions/895171/prevent-users-from-submitting-a-form-by-hitting-enter#comment93893498_51507806
    input(`type` = "submit", disabled = true, style = "display: none;".toCss, `aria-hidden` = true)

    #p(text &"total time = {state.strfloat(state.trajectory.totalTime)}")

    #p(text &"max height = {state.strfloat(state.trajectory.maxHeight.toMuDistance)}")

    #p(text &"max range = {state.strfloat(state.trajectory.maxRange.toMuDistance)}")

    # p(text fmt"\(a = \frac{{v_f - {bullet.position.x}}}{{\Delta t}}\)", style = "font-size: 80px;".toCss)

proc renderPointAccordion(state: var ParabolaState): VNode =
  let (show, point) = state.currentPoint()

  let liStyle = "margin-top: 20px;".toCss
  let formulaAccordionBodyStyle = "padding-left: 0.5em; overflow: auto; scrollbar-width: thin;".toCss

  proc onInputXChange(ev: Event, n: VNode) = 
    if not state.startedRendering or state.trajectory.points.len == 0: return

    var x = 0.0

    discard parseFloat($n.value, x)
    x = x.fromMuDistance().round(state.floatPrecision)

    var (index, exactMatch) = (0, false)

    if state.trajectory.extraPoint >= 0:
      state.trajectory.points.delete(state.trajectory.extraPoint)
      state.trajectory.extraPoint = -1

    # If the trajectory is a vertical line
    if state.trajectory.maxRange == 0:
      index = 0
    # If x goes behind the first point of the trajectory (wether the trajectory goes left or right)
    elif (state.trajectory.maxRange > 0 and x <= state.trajectory.points[0].pos.x) or 
      (state.trajectory.maxRange < 0 and x >= state.trajectory.points[0].pos.x):
        index = 0
    # If x goes beyond the last point of the trajectory (wether the trajectory goes left or right)
    elif (state.trajectory.maxRange > 0 and x >= state.trajectory.maxRange) or 
      (state.trajectory.maxRange < 0 and x <= state.trajectory.maxRange):
        index = state.trajectory.points.high
    else:
      (index, exactMatch) = state.trajectory.points.findBy(x, (p) => p.pos.x)
      if not exactMatch:
        var newP: TrajectoryPoint
        var initialState = state.trajectory.state
        initialState.gravity = initialState.gravity * gravityFactor

        with newP:
          time = initialState.calcTime(x)
          pos = vec(x, initialState.calcY(newP.time))
          vel = initialState.calcVel(newP.time)
          speed = newP.vel.magnitude()

        state.trajectory.points.insert(newP, index)
        state.trajectory.extraPoint = index

    state.trajectory.pinnedPoint = index

    state.updatePointAccordion()

  proc onInputTChange(ev: Event, n: VNode) = 
    if not state.startedRendering or state.trajectory.points.len == 0: return
    #elif state.followBullet and

    var t = 0.0
    discard parseFloat($n.value, t)
    t = t.round(state.floatPrecision)

    var (index, exactMatch) = (0, false)

    if state.trajectory.extraPoint >= 0:
      state.trajectory.points.delete(state.trajectory.extraPoint)
      state.trajectory.extraPoint = -1

    if state.trajectory.totalTime == 0 or t <= 0:
      index = 0
    elif t >= state.trajectory.totalTime:
      index = state.trajectory.points.high
    else:
      (index, exactMatch) = state.trajectory.points.findBy(t, (p) => p.time)
      if not exactMatch:
        var newP: TrajectoryPoint
        var initialState = state.trajectory.state
        initialState.gravity = initialState.gravity * gravityFactor

        with newP:
          time = t
          pos = initialState.calcPos(t)
          vel = initialState.calcVel(t)
          speed = newP.vel.magnitude()

        state.trajectory.points.insert(newP, index)
        state.trajectory.extraPoint = index

    state.trajectory.pinnedPoint = index

    state.updatePointAccordion()

  proc onInputYChange(ev: Event, n: VNode) = 
    if not state.startedRendering or state.trajectory.points.len == 0: return

    var y = 0.0
    var val = $n.value
    let sign = val.len == 0 or val[0] != '-' # - = false, anything else = +
    if not sign:
      val.delete(0..0)

    discard parseFloat(val, y)
    y = y.fromMuDistance().round(state.floatPrecision)

    echo (y: y, s: sign)

    var (index, exactMatch) = (0, false)

    if state.trajectory.extraPoint >= 0:
      state.trajectory.points.delete(state.trajectory.extraPoint)
      state.trajectory.extraPoint = -1

    if state.trajectory.maxHeight == 0 or y <= 0:
      index = 
        if sign: 0
        else: state.trajectory.points.high
    elif y >= state.trajectory.maxHeight and 
      state.trajectory.highestPoint in state.trajectory.points:
      index = state.trajectory.highestPoint
    else:
      let points = 
        if state.trajectory.highestPoint in state.trajectory.points:
          if sign: state.trajectory.points[state.trajectory.highestPoint..state.trajectory.points.high]
          else: state.trajectory.points[0..state.trajectory.highestPoint]
        else: newSeq[TrajectoryPoint]()

      (index, exactMatch) = points.findBy(y, (p) => p.pos.y)
      echo (i: index, e: exactMatch)
      if not exactMatch:
        var newP: TrajectoryPoint
        var initialState = state.trajectory.state
        initialState.gravity = initialState.gravity * gravityFactor

        echo (t1: initialState.calcTime(y, true), t2: initialState.calcTime(y, false))
        with newP:
          time = initialState.calcTime(y, not sign)
          pos = vec(initialState.calcX(newP.time), y)
          vel = initialState.calcVel(newP.time)
          speed = newP.vel.magnitude()

        state.trajectory.points.insert(newP, index)
        state.trajectory.extraPoint = index

    state.trajectory.pinnedPoint = index

    state.updatePointAccordion()

  buildHtml form(class = "form-horizontal"):
    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-x"): text "Pos X"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-x", 
          step = cstring state.inputStep, onchange = onInputXChange)
    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-y"): text "Pos Y"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-y", 
          step = cstring state.inputStep, onchange = onInputYChange, readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-y"): text "Time"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-t", 
          step = cstring state.inputStep, onchange = onInputTChange)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-vx"): text "Vel X"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-vx", 
          readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-vy"): text "Vel Y"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-vy", 
          readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-s"): text "Speed"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-s", 
          readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-s"): text "Follow Bullet"
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-checkbox form-inline", `type` = "checkbox", id = "point-input-f", 
          checked = false):
          proc onchange(ev: Event, n: VNode) = 
            state.followBullet = n.dom.checked
            if state.followBullet:
              if state.canon.flyingBullets.len > 0:
                state.calcClosestTrajectoryPointToBullet()
                state.updatePointAccordion()
            else:
              if state.canon.flyingBullets.len > 0:
                state.calcClosestTrajectoryPointToBullet()
                state.trajectory.pinnedPoint = state.trajectory.closestPoint

    # To disable form submit on enter https://stackoverflow.com/questions/895171/prevent-users-from-submitting-a-form-by-hitting-enter#comment93893498_51507806
    input(`type` = "submit", disabled = true, style = "display: none;".toCss, `aria-hidden` = true)

    tdiv(id = "x", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-x", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f-x", 
        `data-tooltip` = "Pos X", `disabled-data-tooltip` = "There is no trajectory point selected"):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(x = t\:\cdot\:v_{ox} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(): 
            text r"\(x = t\:\cdot\:v = d\)"
          #li(style = liStyle): 
            #text r"\(x = x\:+\:t\:\cdot\:v = d\)"

    tdiv(id = "y", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-y", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f-y", 
        `data-tooltip` = "Pos X", `disabled-data-tooltip` = "There is no trajectory point selected"):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(y = h\:+\:t\:\cdot\:v_{oy}\:+\:\dfrac{g\:\cdot\:t^2}{2} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(): 
            text r"\(y = h\:+\:t\:\cdot\:v\:+\:\dfrac{g\:\cdot\:t^2}{2}\)"
          li(style = liStyle): 
            text r"\(y = h\:+\:a\:+\:\dfrac{g\:\cdot\:t}{2}\)"
          li(style = liStyle): 
            text r"\(y = b\:+\:\dfrac{c}{2}\)"
          li(style = liStyle): 
            text r"\(y = b\:+\:d = e\)"

    tdiv(id = "vy", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-vy", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f-vy", 
        `data-tooltip` = "Velocity Y", `disabled-data-tooltip` = "There is no trajectory point selected"):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(v_{y} = v_{iy}\:-\:g\:\cdot\:t = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(): 
            text r"\(v_{y} = v\:-\:g\:\cdot\:t\)"
          li(style = liStyle): 
            text r"\(v_{y} = v\:-\:a = b\)"

proc addTrajectory(state: var ParabolaState) = 
  if state.trajectories.len < trajectoryStrokeStyles.len:
    var colIndex = -1

    for e, c in trajectoryStrokeStyles:
      var available = true
      for t in state.trajectories:
        if t.color == e:
          available = false
          break
      if available:
        colIndex = e

    state.trajectories.add state.trajectory
    state.currentTrajectory = state.trajectories.high
    state.trajectory.color = colIndex

    if state.trajectory.state.angleDeg +  canonAngleChangeDeg >= state.rotationLimit.b:
      state.rotateCanon(degToRad(state.canon.normalizedAngleDeg() - 60))
    else:
      state.rotateCanonBack(degToRad(canonAngleChangeDeg * 2))

    state.calcTrajectory()
    if not kxi.surpressRedraws: redraw(kxi)

proc renderTrajectories(state: var ParabolaState): VNode = 
  proc onRadioChange(e: int): auto = 
    proc() = 
      if e in state.trajectories:
        state.currentTrajectory = e

        state.rotateCanon(degToRad(state.canon.normalizedAngleDeg() - state.trajectory.state.angleDeg))
        state.moveCanonTo(state.canvas.clientHeight.float - groundHeight.float - 
          state.trajectory.state.height + state.canonYDiff)
        state.engine.gravity.y = state.trajectory.state.gravity.y
        state.calcTrajectory()

  proc onRemoveClick(e: int): auto = 
    proc() = 
      if state.trajectories.len > 1 and e in state.trajectories:
        state.trajectories.delete(e)
        if state.currentTrajectory > state.trajectories.high:
          state.currentTrajectory = state.trajectories.high

          state.moveCanonTo(state.canvas.clientHeight.float - 
            groundHeight.float - state.trajectory.state.height + state.canonYDiff)
          state.rotateCanon(degToRad(state.canon.normalizedAngleDeg() - state.trajectory.state.angleDeg))

        if state.frozen:
          state.unfreeze()

        if not kxi.surpressRedraws: redraw(kxi)

  buildHtml tdiv(class = "form-horizontal", style = "margin: 0rem .2rem -0.3rem 1.3rem;".toCss):
    tdiv(class = "form-group"):
      tdiv(class = "col-3"):
        label(class = "form-label tooltip tooltip-right", `data-tooltip` = "Double-click a trajectory to delete it"):
          text "Trajectories"

      tdiv(class = "col-9", id = "traj-radios"): 
        if state.trajectories.len < trajectoryStrokeStyles.len:
          button(class = "btn btn-action btn-sm", style = "margin-right: 0.4rem;".toCss):
            italic(class = "icon icon-plus")
            proc onclick() = 
              state.addTrajectory()

        for e, t in state.trajectories:
          let checked = state.currentTrajectory == e
          let color = trajectoryStrokeStyles[t.color]
          label(class = "form-radio form-inline", ondblclick = onRemoveClick(e)):
            input(`type`  = "radio", name = "trajectory",
              onchange = onRadioChange(e), checked = checked)
            italic(class = "form-icon", style = toCss &"background-color: {color}; border-color: {color}")

        #tdiv(class = "popover popover-right"):
          #  label(class = "form-radio form-inline"):
          #    input(`type`  = "radio", name = "trajectory",
          #      onchange = onRadioChange(e), checked = checked)
          #    italic(class = "form-icon", style = toCss &"background-color: {color}; border-color: {color}")

          #  tdiv(class = "popover-container"):
          #    if state.trajectories.len > 1:
          #      button(class = "btn", onclick = onRemoveClick(e)):
          #        text "Remove"

proc renderRightDiv(state: var ParabolaState): VNode =
  buildHtml tdiv(class = "column col-4", style = toCss "overflow: auto; height: 100%; " & 
      "scrollbar-width: thin;"):
    state.renderTrajectories()
    #tdiv(class = "accordion"):
    #  input(`type` = "checkbox", name  = "accordion-checkbox", 
    #    id = "accordion-traj", hidden = true, checked = false)
    #  label(class = "accordion-header", `for` = "accordion-traj"):
    #    italic(class = "icon icon-arrow-right mr-1")
    #    text "Trajectories"
    #  tdiv(class = "accordion-body", style = "padding-left: 2em;".toCss):
    #    state.renderTrajectoriesAccordion()

    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-1", hidden = true, checked = true)
      label(class = "accordion-header", `for` = "accordion-1"):
        italic(class = "icon icon-arrow-right mr-1")
        text "Initial State"
      tdiv(class = "accordion-body", style = "padding-left: 2em;".toCss):
        state.renderStateAccordion()

    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-2", hidden = true, checked = true)
      label(class = "accordion-header", `for` = "accordion-2"):
        italic(class = "icon icon-arrow-right mr-1")
        text "Point"
      tdiv(class = "accordion-body", style = "padding-left: 2em;".toCss):
        state.renderPointAccordion()

    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-3", hidden = true, checked = true)
      label(class = "accordion-header", `for` = "accordion-3"):
        italic(class = "icon icon-arrow-right mr-1")
        text "Formulas"
      tdiv(class = "accordion-body", style = 
        "padding-left: 2em; width: 100%; overflow: auto;".toCss):
        state.renderFormulasAccordion()

      #li(class=class({"active": state.currentTab == tPoint}, "tab-item"),
      #  onClick=proc(e: Event, n: VNode) = (state.currentTab = tPoint)):
      #    a(id="point-tab", class="c-hand"):
      #      text "Trajectory Point"

proc render*(state: var ParabolaState): VNode =
  buildHtml tdiv(class = "columns col-gapless", style = "height: 100%; width: 100%".toCss):
    state.renderLeftDiv()
    state.renderRightDiv()

  #buildHtml tdiv(style = "display: flex; flex-direction: column; justify-content: start; align-items: center; height: 100%;".toCss):
  #  state.renderTopDiv()
  #  state.renderSimDiv()
  #  state.renderBottomDiv()

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
    if not state.startedRendering or
      #(not document.activeElement.isNil and document.activeElement.nodename == "INPUT"): 
      (not document.activeElement.isNil and document.activeElement.id != "canvas"): 
      return

    let event = KeyboardEvent(event)
    case $event.key
    of "ArrowRight":
      state.rotateCanon()
      state.calcTrajectory()
    of "ArrowLeft":
      state.rotateCanonBack()
      state.calcTrajectory()
    of "ArrowUp":
      state.trajectory.state.setSpeed(state.trajectory.state.speed + canonSpeedChange)
      state.calcTrajectory()
    of "ArrowDown":
      state.trajectory.state.setSpeed(state.trajectory.state.speed - canonSpeedChange)
      state.calcTrajectory()
    of " ":
      state.fireBullet()
    of "Backspace":
      state.reload()
    of "p":
      state.togglePause()
    of "Enter":
      state.addTrajectory()
    of "d":
      discard "debug"
  )
