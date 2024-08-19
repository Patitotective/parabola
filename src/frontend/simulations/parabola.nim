import std/[math, jsffi, times, dom, jsconsole, with, strformat, 
  algorithm, strutils, parseutils, sugar]
import karax/[karax, karaxdsl, vdom, vstyles]

import matter, utils, mouseconstraint
import ../../translations
import ../../config as _

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

    imgSize*: Vec
    showVxArrow*, showVyArrow*, showVArrow*: bool

  CanonPlatform = object
    body*: JsObject
    imgSize*: Vec

  ParabolaState* = object
    engine*: JsObject
    render*: JsObject
    runner*: JsObject
    canvas*: Element
    canvasSize*: Vec

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

    onMousedown*, onMouseup*, onMousemove*, 
      onMouseleave*, onWheel*: proc(event: JsObject)

    floatPrecision*: range[0..8]
    startedRendering*: bool
    showFormulaResults*: bool

    lang*: Locale

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
  timeScale = 0.028
  delta = (1000 / fps) * timeScale # 60fps, 60 times in one second (1000 milliseconds)
  timeSteps = [0.5, 1, 1.75, 2.5, 3]

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
  hiddenFormulaVal = "__"

let
  formulaAccordionBodyStyle = "padding-left: 0.5em; overflow: auto; scrollbar-width: thin;".toCss

proc gravities(state: ParabolaState): auto = 
  {state.lang.pluto: 0.7, state.lang.moon: 1.6, state.lang.mercAndMars: 3.7, 
    state.lang.uranus: 8.7, state.lang.venus: 8.9, state.lang.saturn: 9, 
    state.lang.earth: 9.81, state.lang.neptune: 11, state.lang.jupiter: 23.1}

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

proc getPos(state: ParabolaState, p: TrajectoryPoint): Vec = 
  ## Converts p.pos into matter-js coordinates
  result.x = state.canon.pivot.x + p.pos.x
  result.y = state.canvasSize.y - groundHeight.float - p.pos.y

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
  JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: state.canvasSize.x, y: undefined}} # To avoid boilerplate

proc strfloat(state: ParabolaState, f: float): string = 
  let f =
    if f.classify() == fcNegZero: 0.0
    else: f

  formatValue(result, f, &".{state.floatPrecision}f")

proc inputStep(state: ParabolaState): string = 
  if state.floatPrecision > 0:
    let places = state.floatPrecision - 1
    #  if state.floatPrecision > 1:
    #    state.floatPrecision - 2
    #  else: state.floatPrecision

    &"0.{'0'.repeat(places)}1"
    #"0.1"
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

proc toggleFormula(id: string, to: bool, trueVal: string, falseVal = hiddenFormulaVal, 
  hideResult = false): string = 
  let ele = getElementById(id)
  let inp = ele.firstChild
  let label = ele.children[1]
  let icon = Element label.firstChild

  if not to:
    inp.disabled = not hideResult and true

    if not hideResult:
      #icon.classList.remove("icon-arrow-right")
      #icon.classList.add("icon-cross")
      inp.checked = false
      icon.style.setProperty("visibility", "hidden")

      if label.hasAttribute("data-tooltip"):
        if not label.hasAttribute("old-data-tooltip"):
          label.setAttr("old-data-tooltip", label.getAttribute("data-tooltip"))

        if label.hasAttribute("disabled-data-tooltip"):
          label.setAttr("data-tooltip", label.getAttribute("disabled-data-tooltip"))

    falseVal
  else:
    inp.disabled = false

    if label.hasAttribute("data-tooltip"):
      if label.hasAttribute("old-data-tooltip"):
        label.setAttr("data-tooltip", label.getAttribute("old-data-tooltip"))

    #icon.classList.remove("icon-cross")
    #icon.classList.add("icon-arrow-right")
    icon.style.setProperty("visibility", "visible")

    trueVal

proc updateFormulaAccordion(state: var ParabolaState) = 
  var siInitialState = state.trajectory.state.toMu()
  siInitialState.gravity = siInitialState.gravity * gravityFactor
  let vySquared = siInitialState.vel.y ^ 2
  let gTwice = siInitialState.gravity.y * 2
  let gTimesH = siInitialState.gravity.y * siInitialState.height
  let gTimesHTwice = 2 * gTimesH

  let changes = {
    "#maxheight > label:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      if state.trajectory.highestPoint == 0:
        toggleFormula("maxheight", false, "")
      else:
        toggleFormula("maxheight", state.showFormulaResults,
          &"{state.strfloat(state.trajectory.maxHeight.toMuDistance)}m", hideResult = true),
    "#mh1 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.height)}m",
    "#mh1 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(7)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#mh1 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(2)":
       &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#mh2 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(vySquared)}m²/s²",
    "#mh2 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(gTwice)}m/s²",
    "#mh2 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.height)}m",
    "#mh4 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.height)}m",
    "#mh4 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat(vySquared / gTwice)}m",
    "#mh4 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.height + (vySquared / gTwice))}m",

    "#l_f-2 > span:nth-child(2) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      toggleFormula("timeflight", state.showFormulaResults, 
        &"{state.strfloat(state.trajectory.totalTime)}s", hideResult = true),
    "#tf1 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#tf1 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1)":
      &"({state.strfloat(siInitialState.vel.y)}m/s)",
    "#tf1 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(13)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "span.mord:nth-child(19)":
      &"{state.strfloat(siInitialState.height)}m",
    "#tf1 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",

    "#tf2 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
       &"{state.strfloat(siInitialState.vel.y)}m/s", 
    "#tf2 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(vySquared)}m²/s²", 
    "#tf2 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(13)":
      &"{state.strfloat(gTimesH)}m²/s²", 
    "#tf2 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²", 

    "#tf3 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
       &"{state.strfloat(siInitialState.vel.y)}m/s", 
    "#tf3 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(vySquared)}m²/s²", 
    "#tf3 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(7)": 
      &"{state.strfloat(gTimesHTwice)}m²/s²",
    "#tf3 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    
    "#tf4 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y)}m/s", 
    "#tf4 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(vySquared + gTimesHTwice)}",
    "#tf4 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    
    "#tf5 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",  
    "#tf5 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7)":
      &"{state.strfloat(sqrt(vySquared + gTimesHTwice))}m/s",
    "#tf5 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",

    "#tf6 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.vel.y + sqrt(vySquared + gTimesHTwice))}m/s",
    "#tf6 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#tf6 > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat((siInitialState.vel.y + sqrt(vySquared + gTimesHTwice)) / siInitialState.gravity.y)}s",
    
    "#l_f-3 > span:nth-child(2) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      toggleFormula("maxrangediv", state.showFormulaResults, 
        &"{state.strfloat(state.trajectory.maxRange.toMuDistance)}m", hideResult = true),

    "#maxRange > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.vel.x)}m/s",
    "#maxRange > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat(state.trajectory.totalTime)}s",
    "#maxRange > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
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

  let changes = {
    "#vix > label:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      toggleFormula("vix", state.showFormulaResults, 
        &"{state.strfloat(siInitialState.vel.x)}m/s", hideResult = true),
    "#vix > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.speed)}m/s",
    "#vix > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(4) > span:nth-child(1)":
      &"{siInitialState.angleDeg:.0f}°",
    "#vix > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.vel.x)}m/s",    

    "#viy > label:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      toggleFormula("viy", state.showFormulaResults, 
        &"{state.strfloat(siInitialState.vel.y)}m/s", hideResult = true),
    "#viy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.speed)}m/s",
    "#viy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(4) > span:nth-child(1)":
      &"{siInitialState.angleDeg:.0f}°",
    "#viy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",    
  }
  
  for (query, value) in changes:
    document.querySelector(cstring query).innerText = cstring value

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
    "#x > label:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      if not show:
        toggleFormula("x", false, "")
      else:
        toggleFormula("x", state.showFormulaResults, 
          &"{state.strfloat(point.pos.x)}m", hideResult = true),
    "#x > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(point.time)}s",
    "#x > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.vel.x)}m/s",
    "#x > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      &"{state.strfloat(point.pos.x)}m",

    "span.base:nth-child(6) > span:nth-child(2)":
      if not show:
        toggleFormula("y", false, "")
      else:
        toggleFormula("y", state.showFormulaResults, 
          &"{state.strfloat(point.pos.y)}m", hideResult = true),
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.height)}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat(point.time)}s",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(5) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",  
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(5) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7) > span:nth-child(1)":
      &"({state.strfloat(point.time)}s)",

    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.height)}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat(point.time * siInitialState.vel.y)}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",  
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(7)":
      &"{state.strfloat(point.time ^ 2)}s²",

    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(3) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.height + (point.time * siInitialState.vel.y))}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(3) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(3) > span:nth-child(2) > span:nth-child(1)":
      &"{state.strfloat(siInitialState.gravity.y * (point.time ^ 2))}m",  

    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(4) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.height + (point.time * siInitialState.vel.y))}m",
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(4) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat((siInitialState.gravity.y * (point.time ^ 2)) / 2)}m",  
    "#y > div:nth-child(3) > ul:nth-child(1) > li:nth-child(4) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      &"{state.strfloat(point.pos.y)}m",

    "#vx > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      if state.showFormulaResults: 
        &"{state.strfloat(siInitialState.vel.x)}m/s"
      else:
        hiddenFormulaVal,

    "#vy > label:nth-child(2) > span:nth-child(2) > span:nth-child(1) > span:nth-child(2) > span:nth-child(5) > span:nth-child(2)":
      if not show:
        toggleFormula("vy", false, "")
      else:
        toggleFormula("vy", state.showFormulaResults, 
          &"{state.strfloat(point.vel.y)}m/s", hideResult = true),
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y)}m/s²",
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(1) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      &"{state.strfloat(point.time)}s",

    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(2) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.vel.y)}m/s",
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(3) > span:nth-child(2)":
      &"{state.strfloat(siInitialState.gravity.y * point.time)}m/s",
    "#vy > div:nth-child(3) > ul:nth-child(1) > li:nth-child(2) > span:nth-child(1) > span:nth-child(1) > span:nth-child(2) > span:nth-child(4) > span:nth-child(2)":
      &"{state.strfloat(point.vel.y)}m/s"
  }

  for (query, value) in changes:
    document.querySelector(cstring query).innerText = cstring value

  if state.frozen:
    state.unfreeze()

proc calcTrajectory(state: var ParabolaState) =
  # If you change the trajectory while a bullet is being traced, disable follow bullet
  if state.followBullet and state.canon.flyingBullets.len > 0:
    getElementById("point-input-f").checked = false
    state.followBullet = false

  var initialState = state.trajectory.state
  initialState.gravity = initialState.gravity * gravityFactor

  let downwards = initialState.angleDeg > 180 and initialState.angleDeg < 360

  # Was the pinned point the highest or the last point?
  let prevHighestPoint = state.trajectory.pinnedPoint != 0 and 
    state.trajectory.pinnedPoint in state.trajectory.points and 
    state.trajectory.highestPoint == state.trajectory.pinnedPoint
  let prevLastPoint = state.trajectory.pinnedPoint != 0 and 
    state.trajectory.pinnedPoint in state.trajectory.points and 
    state.trajectory.points.high == state.trajectory.pinnedPoint

  var highest = (index: 0, y: 0.0)

  state.trajectory.points.setLen(0)
  for t in countthrough(0.0, initialState.calcTotalTime(), step = delta / 25):
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
  (state.canon.imgSize.x + state.canonYDiff)..(state.canvasSize.y - groundHeight.float + state.canonYDiff)

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
  state.trajectory.state.height = state.canvasSize.y - groundHeight.float - canonY

  let platformY = (baseY * 1.02) + (state.canon.platform.imgSize.y / 2)
  state.canon.platform.body.setY platformY

  state.rotateCanon(canonPrevAngle, limit = false)

proc onResize(state: var ParabolaState, first = false) = 
  if not first and not state.startedRendering: return 
  state.canvasSize.x = state.canvas.clientWidth.float
  state.canvasSize.y = state.canvas.clientHeight.float

  state.render.canvas.width = state.canvasSize.x
  state.render.canvas.height = state.canvasSize.y

  let wrap = state.wrapObject()

  if not state.canon.bulletOptions.to(bool):
    state.canon.bulletOptions = JsObject{plugin: JsObject{wrap: wrap}}
  else:
    state.canon.bulletOptions.plugin = JsObject{wrap: wrap}


  for b in Matter.Composite.allBodies(state.engine.world).to(seq[JsObject]):
    Matter.Sleeping.set(b, false) # Wake all bodies
    if b.hasOwnProperty("plugin") and b.plugin.hasOwnProperty("wrap"):
      b.plugin.wrap = wrap

    if b.hasOwnProperty("xratio"):
      let pos = JsObject{x: state.canvasSize.x.toJs * b.xratio, y: b.position.y}
      Matter.Body.setPosition(b, pos)

    if b.hasOwnProperty("yratio"):
      Matter.Body.setPosition(b, JsObject{x: b.position.x, y: state.canvasSize.y.toJs * b.yratio})

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

  # If the limit is exceed by 10, remove half of the bullets
  if state.canon.bullets.len + 1 > state.canon.bulletsLimit + 10:
    var toDelete: seq[int]
    for i in countup(0, state.canon.bullets.len - state.canon.bulletsLimit):
      Matter.Composite.remove(state.engine.world, state.canon.bullets[i])
      toDelete.add i

    for i in countdown(toDelete.high, toDelete.low):
      state.canon.bullets.delete(toDelete[i])
      
      if (let a = state.canon.flyingBullets.find(toDelete[i]); a >= 0):
        state.canon.flyingBullets.delete(a)

      # We have to lower the indices greater than the one we deleted...
      for fi in state.canon.flyingBullets.mitems:
        if fi > toDelete[i]:
          dec fi

  elif state.canon.bullets.len + 1 > state.canon.bulletsLimit:
    for i in countup(0, state.canon.bullets.len - state.canon.bulletsLimit):
      state.canon.bullets[i].collisionFilter.mask = 0
      # If we change the mask but don't wake them, they stay there without being
      # able to collide with anything, but still since they are sleeping
      if state.canon.bullets[i].isSleeping.to(bool):
        Matter.Sleeping.set(state.canon.bullets[i], false)

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
    calcBullet = state.paused and state.canon.flyingBullets.len > 0

  for e in state.trajectory.points.low..state.trajectory.points.high:
    let d = distance(state.getPos(state.trajectory.points[e]), point)
    if result < 0 or d < closestDistance:
      closestDistance = d
      result = e

    if calcBullet:
      for i in state.canon.flyingBullets.low..state.canon.flyingBullets.high:
        let d = distance(state.getPos(state.trajectory.points[e]), 
          getPos(state.canon.bullets[state.canon.flyingBullets[i]]))
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
    elif result != state.trajectory.highestPoint and 
      distance(state.getPos(state.trajectory.points[result]), 
        state.getPos(state.trajectory.points[state.trajectory.highestPoint])) < 10:
      state.trajectory.highestPoint
    elif result != state.trajectory.points.high and 
      distance(state.getPos(state.trajectory.points[result]), 
        state.getPos(state.trajectory.points[^1])) < 10:
      state.trajectory.points.high
    elif result != 0 and 
      distance(state.getPos(state.trajectory.points[result]), 
        state.getPos(state.trajectory.points[0])) < 10:
      0
    elif calcBullet:
      var closestBulletPoint = -1
      var closestBulletDistance = 0.0
      for i in state.canon.flyingBullets.low..state.canon.flyingBullets.high:
        # Distance betweeen the closest point to point and the closest point to
        # the flying bullet i
        let d = distance(state.getPos(state.trajectory.points[result]), 
          state.getPos(state.trajectory.points[bulletsPoints[i]]))

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

  for e in state.trajectory.points.low..state.trajectory.points.high:
    let d = distance(state.getPos(state.trajectory.points[e]), bullet.getPos())
    if result < 0 or d < closestDistance:
      closestDistance = d
      result = e

  state.trajectory.closestPoint = 
    if closestDistance > minRangeDistance:
      -1 
    else: result

proc initParabolaState*(): ParabolaState = 
  result = ParabolaState(
    floatPrecision: 2, showFormulaResults: true, 
    canon: Canon(bulletRadius: 20, bulletsLimit: 7, showVArrow: true, 
      showVxArrow: true, showVyArrow: true,
      bulletOptions: JsObject{
        zIndex: 0, isStatic: false, frictionAir: 0, friction: 1, frictionStatic: 1, 
        collisionFilter: JsObject{mask: 0}, sleepThreshold: 1, label: cstring"bullet",
      }),
    trajectories: @[initTrajectory()], lang: English
  )

proc onAfterUpdate(state: var ParabolaState, event: JsObject) = 
  template b(): untyped = 
    state.canon.bullets[e]
  try:
    if state.canon.flyingBullets.len > 0:
      if state.followBullet and not state.paused:
        state.calcClosestTrajectoryPointToBullet()
        state.updatePointAccordion()

    # Sequence of bullets to delete from bullets since they went under the floor
    var toDelete: seq[int]
    for e in state.canon.bullets.low..state.canon.bullets.high:
      # If the bullet is above the floor, make it able to collide with the ground
      if b.getY > state.canvasSize.y + state.canon.bullets[e].circleRadius.to(float):
        Matter.Composite.remove(state.engine.world, state.canon.bullets[e])
        toDelete.add e

      elif e in state.canon.flyingBullets and b.collisionFilter.mask == 0.toJs and
        state.canon.bullets[e].getY < state.canvasSize.y - 
        groundHeight - (state.canon.bullets[e].circleRadius.to(float)):

        b.collisionFilter.mask = 2

    for i in countdown(toDelete.high, toDelete.low):
      state.canon.bullets.delete(toDelete[i])
      if (let a = state.canon.flyingBullets.find(toDelete[i]); a >= 0):
        state.canon.flyingBullets.delete(a)

    if toDelete.len > 0:
      # Lower each index by the number of bullets deleted since we deleted one
      for i in state.canon.flyingBullets.low..state.canon.flyingBullets.high:
        for di in toDelete:
          if state.canon.flyingBullets[i] > di:
            dec state.canon.flyingBullets[i]

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
  except Exception as ex:
    state.pause()
    echo ex.msg
    echo ex.trace
    # For some reason the trace is different when raise than when echo
    # So you can't get the true trace if you don't print it beforehand :shrug:
    raise ex

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

proc drawVelocityArrows(state: ParabolaState, ctx: JsObject) = 
  template b(): untyped = 
    state.canon.bullets[state.canon.flyingBullets[i]]

  for i in state.canon.flyingBullets.low..state.canon.flyingBullets.high:
    const
      threshold = 4.0
      arrowWidth = 3
    if state.canon.showVyArrow and b.velocity.y.to(float) notin -threshold..threshold:
      drawArrow(ctx, b.position.x, b.position.y, 
        b.position.x,
        b.position.y + (b.velocity.y * toJs velVectorScale), 
        toJs arrowWidth, toJs cstring"red"
      )

    if state.canon.showVxArrow and b.velocity.x.to(float) notin -threshold..threshold:
      drawArrow(ctx, b.position.x, b.position.y, 
        b.position.x + (b.velocity.x * toJs velVectorScale), 
        b.position.y,
        toJs arrowWidth, toJs cstring"DodgerBlue" # Neon blue
      )

    if state.canon.showVArrow and (b.velocity.x.to(float) notin -threshold..threshold or 
      b.velocity.y.to(float) notin -threshold..threshold):
      drawArrow(ctx, b.position.x, b.position.y, 
        b.position.x + (b.velocity.x * toJs velVectorScale), 
        b.position.y + (b.velocity.y * toJs velVectorScale), 
        toJs arrowWidth, toJs cstring"white"
      )

proc drawTrajectory(state: ParabolaState, ctx: JsObject) = 
  for e in state.trajectories.low..state.trajectories.high:
    if state.trajectories[e].points.len == 0: continue

    ctx.beginPath()
    let pos0 = state.getPos(state.trajectories[e].points[0])
    ctx.moveTo(pos0.x, pos0.y)

    ctx.strokeStyle = cstring trajectoryStrokeStyles[state.trajectories[e].color]
    ctx.lineWidth = trajectoryLineWidth

    for pe in state.trajectories[e].points.low..state.trajectories[e].points.high:
      if pe > 0:
        let pos = state.getPos(state.trajectories[e].points[pe])
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
  const width = 20
  let text = &"{state.strfloat(state.trajectory.state.height.toMuDistance)}m"
  let xOffset = -(state.canon.platform.imgSize.x / 2) - 10

  if state.trajectory.state.height > 0:
    ctx.beginPath()
    ctx.moveTo(state.canon.pivot.x + xOffset - width, 
      state.canvasSize.y - groundHeight)
    ctx.lineTo(state.canon.pivot.x + xOffset, 
      state.canvasSize.y - groundHeight)

    ctx.moveTo(state.canon.pivot.x + xOffset - width, 
      state.canvasSize.y - groundHeight - state.trajectory.state.height)
    ctx.lineTo(state.canon.pivot.x + xOffset, 
      state.canvasSize.y - groundHeight - state.trajectory.state.height)

    ctx.moveTo(state.canon.pivot.x + xOffset - (width / 2), 
      state.canvasSize.y - groundHeight)
    ctx.lineTo(state.canon.pivot.x + xOffset - (width / 2), 
      state.canvasSize.y - groundHeight - state.trajectory.state.height)

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
    state.canvasSize.y - groundHeight - (state.trajectory.state.height / 2) - (theight / 2))

  ctx.shadowOffsetX = 0
  ctx.shadowOffsetY = 0

proc drawRange(state: ParabolaState, ctx: JsObject) = 
  const
    height = 10
    yOffset = groundHeight - 30

  let text = &"{state.strfloat(state.trajectory.maxRange.toMuDistance)}m"

  if state.trajectory.maxRange != 0:
    ctx.beginPath()
    ctx.moveTo(state.canon.pivot.x, 
      state.canvasSize.y - groundHeight + yOffset)
    ctx.lineTo(state.canon.pivot.x, 
      state.canvasSize.y - groundHeight + yOffset + height)

    ctx.moveTo(state.canon.pivot.x + state.trajectory.maxRange, 
      state.canvasSize.y - groundHeight + yOffset)
    ctx.lineTo(state.canon.pivot.x + state.trajectory.maxRange, 
      state.canvasSize.y - groundHeight + yOffset + height)

    ctx.moveTo(state.canon.pivot.x, 
      state.canvasSize.y - groundHeight + yOffset + (height / 2))
    ctx.lineTo(state.canon.pivot.x + state.trajectory.maxRange ,
      state.canvasSize.y - groundHeight + yOffset + (height / 2))

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
    state.canvasSize.y - (groundHeight / 2))

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
  except Exception as ex:
    state.pause()
    echo ex.msg
    echo ex.trace
    # For some reason the trace is different when raise than when echo
    # So you can't get the true trace if you don't print it beforehand :shrug:
    raise ex

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
    #  if state.mouse.getY() >= state.canvasSize.y * 0.95:
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

  #Matter.Events.on(state.render, "beforeRender", 
  #  (event: JsObject) => state.onBeforeRender(event))

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

proc toggleStarsAnimation(to: bool) = 
  for e in document.querySelectorAll(".stars"):
    e.style.animationPlayState = cstring(
      if to: "running" else: "paused")

## Loads the simulation
proc load*(state: var ParabolaState) =
  getElementById("langSelect").value = cstring $state.lang.int
  toggleStarsAnimation(false)

  # Load wrap's plugin and load matter aliases to point to the correct values
  Matter.use("matter-wrap")

  let gravity = state.trajectory.state.gravity.jsVec()
  gravity.scale = 1

  state.canvas = getElementById("canvas")
  state.canvasSize.x = state.canvas.clientWidth.float
  state.canvasSize.y = state.canvas.clientHeight.float
  state.canvas.focus()
  state.engine = createEngine(JsObject{gravity: gravity, 
    timing: JsObject{timeScale: timeScale}, 
    enableSleeping: true,
  })
  state.render = createRender(JsObject{
    canvas: state.canvas,
    engine: state.engine,
    options: JsObject{
      width: state.canvasSize.x,
      height: state.canvasSize.y,
      showAngleIndicator: false,
      showSleeping: false,
      wireframes: false,
      showDebug: false,
      background: "transparent",#"rgb(20, 21, 31)",
    }
  })

  state.runner = Matter.Runner.create(JsObject{fps: fps})
  Matter.Runner.run(state.runner, state.engine)

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

  state.ground = Matter.Bodies.rectangle(0, 0, state.canvasSize.x * 1000, groundHeight * 2, 
    JsObject{zIndex: -1, friction: 1, frictionStatic: 1, isStatic: true, 
      label: cstring"Ground", collisionFilter: JsObject{category: 2, mask: 3}, 
      render: JsObject{fillStyle: cstring""}
    }
  ) # 350, 495, 1200
  state.ground.xratio = 0.5
  state.ground.yratio = 1

  state.thingy = Matter.Bodies.rectangle(state.canvasSize.x / 2, 
    state.canvasSize.y * 0.6, 20, 80, 
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
        # Remnder KaTex expressions before since onImagesLoaded updates them
        renderMathInElement(document.body.toJs)
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
      "min-height: 300px; outline: none", tabindex = "0"):
      text "Matter-js simulation"
      proc onclick(e: Event, n: VNode) = 
        n.dom.focus()
      # Doing this because I saw it on matter-js's Matter.Render._createCanvas
      proc oncontextmenu(ev: Event, _: VNode) = ev.preventDefault()
      proc ondragstart(ev: Event, _: VNode) = ev.preventDefault()

    # class is col-8 to be the same size as #div
    tdiv(class = "col-8", style = toCss "background: radial-gradient(ellipse at bottom, rgb(23, 34, 68) 0%, rgb(19, 9, 53) 100%);" & 
      "position: absolute; top: 0; left: 0; height: 100%; z-index: -10;"):
      tdiv(id = "stars", class = "stars")
      tdiv(id = "stars2", class = "stars")
      tdiv(id = "stars3", class = "stars")

proc renderFormulasAccordion(state: var ParabolaState): VNode =
  let liStyle = "margin-top: 20px;".toCss

  buildHtml tdiv(class = "container"):
    tdiv(id = "maxheight", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-1", hidden = true, checked = false)
      label(class = "accordion-header tooltip tooltip-bottom", `for` = "accordion-f-1", 
        `data-tooltip` = cstring state.lang.maxHeight, 
        `disabled-data-tooltip` = cstring state.lang.disabledMaxHeight):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(h_{max} = h + \dfrac{v_{iy}^{2}}{2g} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(id = "mh1"): 
            text r"\(h_{max} = h + \dfrac{(v)^{2}}{2\:\cdot\:10.1}\)"
          li(id = "mh2", style = liStyle):
            text r"\(h_{max} = h + \dfrac{v}{g}\)"
          li(id = "mh4", style = liStyle):
            text r"\(h_{max} = h + a = d\)"

    tdiv(class = "accordion", id = "timeflight"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-2", hidden = true, checked = false)
      label(id = "l_f-2", class = "accordion-header tooltip", `for` = "accordion-f-2", 
        `data-tooltip` = cstring state.lang.timeOfFlight):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(t_{f} = \dfrac{v_{iy}\:+\:\sqrt{v_{iy}^{2}\:+\:2gh}}{g} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(id = "tf1"): 
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

    tdiv(class = "accordion", id = "maxrangediv"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-3", hidden = true, checked = false)
      label(id = "l_f-3", class = "accordion-header tooltip", `for` = "accordion-f-3", 
        `data-tooltip` = cstring state.lang.maxRange):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(x_{max} = v_{ix}\:\cdot\:t_f = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(id = "maxRange", style = "list-style-type: none;".toCss):
          li(): 
            text r"\(x_{max} = v\:\cdot\:t = d\)"

proc renderStateAccordion(state: var ParabolaState): VNode = 
  proc changeHeightTo(h: float) = 
    if not state.startedRendering: return

    var h = h.fromMuDistance().round(state.floatPrecision).
      clamp(0.0..state.canonYRange.b)

    state.moveCanonTo(state.canvasSize.y - 
      groundHeight.float - h + state.canonYDiff)
    state.calcTrajectory()
  
  proc changeSpeedTo(s: float) = 
    if not state.startedRendering: return
  
    var s = s.fromMuSpeed().round(state.floatPrecision)
    state.trajectory.state.setSpeed(s)
    state.calcTrajectory()

  proc changeGravTo(g: float) = 
    if not state.startedRendering: return
  
    var g = g.clamp(0.7, 23.1).fromMuAcceleration().round(state.floatPrecision)
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
        label(class = "form-label", `for` = "state-input-h"): text state.lang.height
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-h", 
          step = cstring state.inputStep):
          proc onchange(e: Event, n: VNode) = 
            var h = 0.0
            discard parseFloat($n.value, h)
            changeHeightTo(h)

          proc onwheel(e: Event, n: VNode) = 
            e.preventDefault()

            var h = 0.0
            discard parseFloat($n.value, h)
            if e.toJs.wheelDelta.to(float) > 0: h += 1
            else: h -= 1

            changeHeightTo(h)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-a"): text state.lang.angle
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-a", 
          step = "1"):
          proc onchange(e: Event, n: VNode) = 
            if not state.startedRendering: return

            var a = 0

            discard parseInt($n.value, a)

            if a < 0:
              a = clamp(360 + a, 0..359)
            elif a > 359:
              a = clamp(a - 360, 0..359)

            state.rotateCanon(degToRad(
              state.canon.normalizedAngleDeg() - a.float
            ))
            state.calcTrajectory()

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-s"): text state.lang.speed
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-s", 
          step = cstring state.inputStep):
          proc onchange(e: Event, n: VNode) = 
            var s = 0.0
            discard parseFloat($n.value, s)
            changeSpeedTo(s)

          proc onwheel(e: Event, n: VNode) = 
            e.preventDefault()

            var s = 0.0
            discard parseFloat($n.value, s)
            if e.toJs.wheelDelta.to(float) > 0: s += 1
            else: s -= 1

            changeSpeedTo(s)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-vx"): text state.lang.vx
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-vx", 
          readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "state-input-vy"): text state.lang.vy
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "state-input-vy", 
          readonly = true)

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
              text state.lang.gravity
              proc onclick() = 
                let ele = getElementById("accordion-g")
                ele.checked = not ele.checked
                onGAccordChange(ele.checked)

          tdiv(class = "col-9 col-sm-12"):
            input(class = "form-input form-inline", `type` = "number", id = "state-input-g", 
              step = cstring state.inputStep):
              proc onchange(e: Event, n: VNode) = 
                var g = 0.0
                discard parseFloat($n.value, g)
                changeGravTo(g)

              proc onwheel(e: Event, n: VNode) = 
                e.preventDefault()
                var g = 0.0
                discard parseFloat($n.value, g)
                if e.toJs.wheelDelta.to(float) > 0: g += 1
                else: g -= 1
                changeGravTo(g)

      tdiv(class = "accordion-body"):
        for e, (name, gravity) in state.gravities:
          button(`type` = "button", class = "btn", onclick = onPlanetClick(gravity),
            style = "display: inline;".toCss):
            text name

    # To disable form submit on enter https://stackoverflow.com/questions/895171/prevent-users-from-submitting-a-form-by-hitting-enter#comment93893498_51507806
    input(`type` = "submit", disabled = true, style = "display: none;".toCss, `aria-hidden` = true)

    tdiv(id = "vix", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f--1", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f--1", 
        `data-tooltip` = cstring state.lang.vix, style = "padding: 0 0 0.6rem;".toCss):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(v_{ix} = v\:\cdot\:\cos{\alpha} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(): 
            text r"\(v_{ix} = v\:\cdot\:\cos{a} = d\)"
    
    tdiv(id = "viy", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-0", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f-0", 
        `data-tooltip` = cstring state.lang.viy, style = "padding: 0 0 0.6rem;".toCss):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(v_{iy} = v\:\cdot\:\sin{\alpha} = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(): 
            text r"\(v_{iy} = v\:\cdot\:\sin{a} = d\)"

proc renderPointAccordion(state: var ParabolaState): VNode =
  #let (show, point) = state.currentPoint()

  let liStyle = "margin-top: 20px;".toCss

  proc changeXTo(x: float) = 
    if not state.startedRendering or state.trajectory.points.len == 0: return

    var x = x.fromMuDistance().round(state.floatPrecision)

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

  proc changeTTo(t: float) = 
    if not state.startedRendering or state.trajectory.points.len == 0: return

    var t = t.round(state.floatPrecision)

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
        label(class = "form-label", `for` = "point-input-x"): text state.lang.x
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-x", 
          step = cstring state.inputStep):
          proc onchange(ev: Event, n: VNode) = 
            var x = 0.0

            discard parseFloat($n.value, x)
            changeXTo(x)

          proc onwheel(e: Event, n: VNode) = 
            e.preventDefault()
            var x = 0.0
            discard parseFloat($n.value, x)
            if e.toJs.wheelDelta.to(float) > 0: x += 1
            else: x -= 1
            changeXTo(x)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-y"): text state.lang.y
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-y", 
          step = cstring state.inputStep, onchange = onInputYChange, readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-y"): text state.lang.t
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-t", 
          step = cstring state.inputStep):
          proc onchange(ev: Event, n: VNode) = 
            var t = 0.0

            discard parseFloat($n.value, t)
            changeTTo(t)

          proc onwheel(e: Event, n: VNode) = 
            e.preventDefault()
            var t = 0.0
            discard parseFloat($n.value, t)
            if e.toJs.wheelDelta.to(float) > 0: t += 0.1
            else: t -= 0.1
            changeTTo(t)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-vx"): text state.lang.vx
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-vx", 
          readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-vy"): text state.lang.vy
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-vy", 
          readonly = true)

    tdiv(class = "form-group"): 
      tdiv(class = "col-3 col-sm-12"):
        label(class = "form-label", `for` = "point-input-s"): text state.lang.speed
      tdiv(class = "col-9 col-sm-12"):
        input(class = "form-input form-inline", `type` = "number", id = "point-input-s", 
          readonly = true)

    tdiv(class = "form-group"): 
      label(class = "form-switch"):
        input(`type` = "checkbox", id = "point-input-f", 
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
        italic(class = "form-icon")
        text state.lang.followBullet

    # To disable form submit on enter https://stackoverflow.com/questions/895171/prevent-users-from-submitting-a-form-by-hitting-enter#comment93893498_51507806
    input(`type` = "submit", disabled = true, style = "display: none;".toCss, `aria-hidden` = true)

    tdiv(id = "x", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-x", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f-x", 
        `data-tooltip` = cstring state.lang.x, `disabled-data-tooltip` = cstring state.lang.noPoint):
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
        `data-tooltip` = cstring state.lang.y, `disabled-data-tooltip` = cstring state.lang.noPoint):
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

    label(id = "vx", class = "accordion-header tooltip", `data-tooltip` = cstring state.lang.vx, 
      style = toCss "margin-bottom: 0.6rem; margin-left: 1rem;"):
      text r"\(v_{x} = v_{xy} = d\)"

    tdiv(id = "vy", class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-f-vy", hidden = true, checked = false)
      label(class = "accordion-header tooltip", `for` = "accordion-f-vy", 
        `data-tooltip` = cstring state.lang.vy, `disabled-data-tooltip` = cstring state.lang.noPoint):
        italic(class = "icon icon-arrow-right mr-1")
        text r"\(v_{y} = v_{iy}\:-\:g\:\cdot\:t = d\)"

      tdiv(class = "accordion-body", style = formulaAccordionBodyStyle):
        ul(style = "list-style-type: none;".toCss):
          li(): 
            text r"\(v_{y} = v\:-\:g\:\cdot\:t\)"
          li(style = liStyle): 
            text r"\(v_{y} = v\:-\:a = b\)"

proc addTrajectory(state: var ParabolaState) = 
  if state.startedRendering and state.trajectories.len < trajectoryStrokeStyles.len:
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

proc renderSettingsModal(state: var ParabolaState): VNode = 
  proc onClickStep(t: float): auto = 
    proc(e: Event, n: VNode) = 
      e.preventDefault()
      state.engine.timing.timeScale = timeScale * t

  buildHtml tdiv(class = "modal", id = "settings-modal"):
    a(class = "modal-overlay", `aria-label`="Close"):
      proc onclick() = 
        getElementById("settings-modal").classList.remove("active")

    tdiv(class = "modal-container"):
      tdiv(class = "modal-header"):
        a(class = "btn btn-clear float-right", `aria-label`="Close"):
          proc onclick() = 
            getElementById("settings-modal").classList.remove("active")

        tdiv(class = "modal-title h5"): text state.lang.settings

      tdiv(class = "modal-body"):
        tdiv(class = "content"):
          form(class = "form-horizontal"):
            tdiv(class = "form-group"): 
              tdiv(class = "col-3 col-sm-12"):
                label(class = "form-label", `for` = "settings-ts"): text state.lang.timeScale
              tdiv(class = "col-9 col-sm-12"):
                ul(class = "step", id = "timesteps"):
                  for t in timeSteps:
                    li(class = cstring class({"active": not state.engine.isNil and state.engine.timing.timeScale.to(float) == timeScale * t},
                      "step-item")):
                      a(href = "#", text &"{t}×", onclick = onClickStep(t))

            tdiv(class = "form-group"): 
              tdiv(class = "col-3 col-sm-12"):
                label(class = "form-label", `for` = "settings-ts"): text state.lang.lang
              tdiv(class = "col-9 col-sm-12"):
                select(class = "form-select", id = "langSelect"):
                  var e = 0
                  for l in Locale:
                    option(value = cstring $e, text $l)
                    inc e 

                  proc onchange(e: Event, n: VNode) = 
                    var i = 0
                    discard parseInt($n.value, i)
                    state.lang = Locale(i)
                    if not kxi.surpressRedraws: redraw(kxi)

            tdiv(class = "form-group"): 
              label(class = "form-switch"):
                input(`type` = "checkbox", id = "settings-v", 
                  checked = true):
                  proc onchange(ev: Event, n: VNode) = 
                    state.canon.showVArrow = n.dom.checked

                italic(class = "form-icon")
                text state.lang.showVArrow

            tdiv(class = "form-group"): 
              label(class = "form-switch"):
                input(`type` = "checkbox", id = "settings-vx", 
                  checked = true):
                  proc onchange(ev: Event, n: VNode) = 
                    state.canon.showVxArrow = n.dom.checked

                italic(class = "form-icon")
                text state.lang.showVxArrow

            tdiv(class = "form-group"): 
              label(class = "form-switch"):
                input(`type` = "checkbox", id = "settings-vy", 
                  checked = true):
                  proc onchange(ev: Event, n: VNode) = 
                    state.canon.showVyArrow = n.dom.checked

                italic(class = "form-icon")
                text state.lang.showVyArrow

            tdiv(class = "form-group"): 
              label(class = "form-switch"):
                input(`type` = "checkbox", id = "settings-er", 
                  checked = true):
                  proc onchange(ev: Event, n: VNode) = 
                    state.showFormulaResults = n.dom.checked
                    state.updateFormulaAccordion()
                    state.updatePointAccordion()
                    state.updateStateAccordion()

                italic(class = "form-icon")
                text state.lang.showFormulaResults

            tdiv(class = "form-group"): 
              label(class = "form-switch"):
                input(`type` = "checkbox", id = "settings-sa", 
                  checked = false):
                  proc onchange(ev: Event, n: VNode) = 
                    toggleStarsAnimation(n.dom.checked)

                italic(class = "form-icon")
                text state.lang.starsAnimation

            tdiv(class = "form-group"): 
              tdiv(class = "col-3 col-sm-12"):
                label(class = "form-label", `for` = "settings-bl"):
                  text state.lang.bulletsLimit
              tdiv(class = "col-9 col-sm-12 tooltip tooltip-left", `data-tooltip` = cstring $state.canon.bulletsLimit):
                input(class = "slider", `type` = "range", id = "settings-bl", 
                  min = "1", max = "50", value = cstring $state.canon.bulletsLimit, step = "1"):
                  proc onchange(e: Event, n: VNode) = 
                    var v = 0
                    discard parseInt($n.value, v)
                    state.canon.bulletsLimit = clamp(v, 1, 50)
                    n.dom.setAttr("value", n.value)

                  proc oninput(e: Event, n: VNode) = 
                    n.dom.parentElement.setAttr("data-tooltip", n.value)

      tdiv(class = "modal-footer"):
        text state.lang.aboutMsg(config.version)
        a(href = cstring config.website): text "GitHub"
        text "."

proc renderTrajectories(state: var ParabolaState): VNode = 
  proc onRadioChange(e: int): auto = 
    proc() = 
      if state.startedRendering and e in state.trajectories:
        state.currentTrajectory = e

        state.rotateCanon(degToRad(state.canon.normalizedAngleDeg() - state.trajectory.state.angleDeg))
        state.moveCanonTo(state.canvasSize.y - groundHeight.float - 
          state.trajectory.state.height + state.canonYDiff)
        state.engine.gravity.y = state.trajectory.state.gravity.y
        state.calcTrajectory()

  proc onRemoveClick(e: int): auto = 
    proc() = 
      if state.startedRendering and state.trajectories.len > 1 and e in state.trajectories:
        state.trajectories.delete(e)
        if state.currentTrajectory > state.trajectories.high:
          state.currentTrajectory = state.trajectories.high

        state.moveCanonTo(state.canvasSize.y - 
          groundHeight.float - state.trajectory.state.height + state.canonYDiff)
        state.rotateCanon(degToRad(state.canon.normalizedAngleDeg() - state.trajectory.state.angleDeg))
        state.engine.gravity.y = state.trajectory.state.gravity.y
        state.calcTrajectory()

        if state.frozen:
          state.unfreeze()

        if not kxi.surpressRedraws: redraw(kxi)

  buildHtml tdiv(class = "form-horizontal", style = "margin: 0rem 0rem -0.3rem 1.3rem;".toCss):
    tdiv(class = "form-group"):
      tdiv(class = "col-3"):
        label(class = "form-label tooltip tooltip-right", `data-tooltip` = cstring state.lang.trajTooltip):
          text state.lang.trajecs

      tdiv(class = "col-7", id = "traj-radios"): 
        if state.trajectories.len < trajectoryStrokeStyles.len:
          button(class = "btn btn-action btn-sm", style = "margin-right: 0.5rem;".toCss):
            italic(class = "icon icon-plus")
            proc onclick() = state.addTrajectory()

        for e, t in state.trajectories:
          let checked = state.currentTrajectory == e
          let color = trajectoryStrokeStyles[t.color]
          label(class = "form-radio form-inline", ondblclick = onRemoveClick(e)):
            input(`type`  = "radio", name = "trajectory",
              onchange = onRadioChange(e), checked = checked)
            italic(class = "form-icon", style = toCss &"background-color: {color}; border-color: {color}")

      tdiv(class = "col-2", style = toCss "padding-right: 0.2rem; display: flex; justify-content: flex-end;"):
        button(class = "btn btn-action btn-sm", style = toCss "border: none;"):
          span(class = "material-symbols-outlined"): text "help"
          proc onclick() = 
            discard
            #getElementById("settings-modal").classList.add("active")

        button(class = "btn btn-action btn-sm", style = toCss "border: none;"):
          span(class = "material-symbols-outlined"): text "settings"
          proc onclick() = 
            getElementById("settings-modal").classList.add("active")

    state.renderSettingsModal()

proc renderRightDiv(state: var ParabolaState): VNode =
  buildHtml tdiv(class = "column col-4", style = toCss "overflow: auto; height: 100%; " & 
      "scrollbar-width: thin;"):

    state.renderTrajectories()

    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-1", hidden = true, checked = true)
      label(class = "accordion-header", `for` = "accordion-1"):
        italic(class = "icon icon-arrow-right mr-1")
        text state.lang.iniState
      tdiv(class = "accordion-body", style = "padding-left: 2em;".toCss):
        state.renderStateAccordion()

    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-2", hidden = true, checked = true)
      label(class = "accordion-header", `for` = "accordion-2"):
        italic(class = "icon icon-arrow-right mr-1")
        text state.lang.point
      tdiv(class = "accordion-body", style = "padding-left: 2em;".toCss):
        state.renderPointAccordion()

    tdiv(class = "accordion"):
      input(`type` = "checkbox", name  = "accordion-checkbox", 
        id = "accordion-3", hidden = true, checked = true)
      label(class = "accordion-header", `for` = "accordion-3"):
        italic(class = "icon icon-arrow-right mr-1")
        text state.lang.formulas
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
