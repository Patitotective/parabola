import std/[math, jsffi, dom, jsconsole, enumerate, with, strformat, asyncjs]
import karax/[karax, karaxdsl, vdom, vstyles]

import matter, utils

type
  Exercise = object
    pos: tuple[x, y: int]
    angle: int # Degrees
    angleRad: float
    speed: int
    velocity: tuple[x, y: float]

  ExerciseStatus = enum
    esStart # Not launched yet
    esStarted # In the air
    esEnd # Touched something and stopped

proc initExercise(pos: tuple[x, y: int], angle: int, speed: int): Exercise = 
  let angleRad = degToRad(float angle)
  Exercise(pos: pos, angle: angle, angleRad: angleRad, speed: speed, velocity: speedToVelRad(float speed, angleRad))

const
  deltaTime = 1000 / 60 # 60fps, 60 times in one second (1000 milliseconds)
  secPerFrame = 1 / 60
  canvasWidth = 700
  canvasHeight = 500
  floorHeight = 20
  timeScale = 0.65

let
  wrapObject = JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: canvasWidth, y: undefined}} # To avoid boilerplate

var
  engine*, mrender*, bullet, floor, ground*, runner*: JsObject
  constraint*, mconstraint*, mouse*: JsObject
  canvas*: Element

  trail = newSeq[JsVector]()
  mConstraintDragEnded*: bool # True when you release the mouse constraint

  # The first exercise is the default exercise and it is modifed as you modify the bullet
  exercises = @[initExercise(pos = (canvasWidth div 2, 0), angle = 0, speed = 20), initExercise(pos = (50, 0), angle = 48, speed = 30)]
  curExercise = 0
  exerciseStatus: ExerciseStatus
  exerciseTotalTime: float
  paused = false # Is engine.timing.timeScale == 0?

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
      width: canvasWidth,
      height: canvasHeight,
      showAngleIndicator: false,
      background: "rgb(20, 21, 31)",
    }
  })
  Render.run(mrender)

  runner = Runner.create(JsObject{delta: deltaTime})
  Runner.run(runner, engine)

  # Create and add all bodies to the world
  bullet = Bodies.circle(300, 300, 25, JsObject{isStatic: false, frictionAir: 0, friction: 1, plugin: JsObject{wrap: wrapObject}})

  Body.setInertia(bullet, Infinity)
  # Body.setAngle(bullet, degToRad(180d))

  # constraint = Constraint.create(JsObject{pointA: jsVector(400, 300), bodyB: bullet, length: 30, stiffness: 0.1})

  floor = Bodies.rectangle(350, 495, 1200, floorHeight, JsObject{isStatic: true})

  mouse = Mouse.create(canvas)
  mconstraint = MouseConstraint.create(engine, JsObject{mouse: mouse})

  Composite.add(engine.world, toJs [bullet, mconstraint,
    # Walls
     Bodies.rectangle(350, -200, 1000, 20, JsObject{isStatic: true}), # up
    # Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}), # right
    floor, # down
    # Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}), # left
    # Thingy
    Bodies.rectangle(500, 350, 20, 80, JsObject{isStatic: false, plugin: JsObject{wrap: wrapObject}})

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
      drawArrow(mrender.context, pos.x, pos.y, pos.x + (bullet.velocity.x * toJs 10), pos.y + (bullet.velocity.y * toJs 10), toJs 5, toJs cstring"white")

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

## Since matter measures y from the top of the screen, here we "normalize" it so that the 0 starts at the floor
proc normalizeY(y: int): int =
  -y + (floor.position.y.to(int) - (floorHeight div 2) - bullet.circleRadius.to(int))

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
  buildHtml tdiv(style = "float: left; width: 40%;".toCss):
    p(text r"\(t_f = \frac{2 \cdot v_i \cdot \sin(\theta)}{g}\)", style = "font-size: 80px;".toCss)

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

  buildHtml tdiv(style = "float: right; width: 40%;".toCss):
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
      verbatim """
<svg
   width="24"
   height="24"
   viewBox="0 0 6.3499999 6.35"
   version="1.1"
   id="svg1"
   inkscape:version="1.3.2 (1:1.3.2+202311252150+091e20ef0f)"
   sodipodi:docname="parabola.svg"
   xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
   xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
   xmlns="http://www.w3.org/2000/svg"
   xmlns:svg="http://www.w3.org/2000/svg">
  <sodipodi:namedview
     id="namedview1"
     pagecolor="#ffffff"
     bordercolor="#000000"
     borderopacity="0.25"
     inkscape:showpageshadow="2"
     inkscape:pageopacity="0.0"
     inkscape:pagecheckerboard="0"
     inkscape:deskcolor="#d1d1d1"
     inkscape:document-units="mm"
     inkscape:zoom="22.627417"
     inkscape:cx="4.0879611"
     inkscape:cy="13.457126"
     inkscape:window-width="1920"
     inkscape:window-height="1006"
     inkscape:window-x="0"
     inkscape:window-y="0"
     inkscape:window-maximized="1"
     inkscape:current-layer="layer1" />
  <defs
     id="defs1" />
  <g
     inkscape:label="Layer 1"
     inkscape:groupmode="layer"
     id="layer1">
    <path
       style="fill:none;stroke:#000000;stroke-width:0.68;stroke-dasharray:1.36,0.68;stroke-dashoffset:0"
       d="m 0.36912046,6.0312671 c 0.0157364,-0.063138 0.0314718,-0.125759 0.0472082,-0.1878409 0.0157364,-0.062103 0.0314718,-0.1236465 0.0472082,-0.1846722 0.0157364,-0.061026 0.0312564,-0.121534 0.0469928,-0.1814818 0.0157364,-0.059969 0.0314718,-0.1193999 0.0472082,-0.1783131 0.0157364,-0.058913 0.0314718,-0.1172658 0.0472082,-0.1751227 0.0157364,-0.057835 0.0314718,-0.1151534 0.0472082,-0.1719325 0.0157364,-0.056779 0.0314718,-0.1130192 0.0469928,-0.1687421 0.0157364,-0.055723 0.0314718,-0.1109067 0.0472082,-0.1655733 0.0157364,-0.054645 0.0314718,-0.1087727 0.0472082,-0.162383 0.0157364,-0.053589 0.0314719,-0.1066602 0.0472082,-0.1591927 0.0157364,-0.052532 0.0314718,-0.1045477 0.0472082,-0.1560023 0.0155201,-0.051476 0.0312564,-0.1024352 0.0469928,-0.1528337 0.0157364,-0.05042 0.0314718,-0.1003011 0.0472082,-0.1496433 0.0157364,-0.049363 0.0314718,-0.098189 0.0472082,-0.1464745 0.015736,-0.048286 0.031472,-0.096054 0.047208,-0.1432842 0.015736,-0.047229 0.031256,-0.09392 0.046993,-0.1400938 0.015736,-0.046152 0.031472,-0.091786 0.047208,-0.1369036 0.015736,-0.045095 0.031472,-0.089674 0.047208,-0.1337133 0.015736,-0.044061 0.031472,-0.087562 0.047208,-0.1305445 0.015736,-0.042983 0.031472,-0.085449 0.046993,-0.1273756 0.015736,-0.041905 0.031472,-0.083294 0.047208,-0.1241639 0.015736,-0.04087 0.031472,-0.081181 0.047208,-0.1209951 0.015736,-0.039792 0.031472,-0.079068 0.047208,-0.1178048 0.015736,-0.038736 0.031472,-0.076934 0.047208,-0.1146144 0.015521,-0.03768 0.031256,-0.074822 0.046993,-0.1114456 0.015736,-0.036624 0.031472,-0.072688 0.047208,-0.1082554 0.015736,-0.035546 0.031472,-0.070575 0.047208,-0.105065 0.015736,-0.03449 0.031472,-0.068463 0.047208,-0.1018963 0.015736,-0.033434 0.031256,-0.066328 0.046993,-0.098706 0.015736,-0.032355 0.031472,-0.064194 0.047208,-0.095516 0.015736,-0.0313 0.031472,-0.062082 0.047208,-0.092325 0.015736,-0.030244 0.031472,-0.059969 0.047208,-0.089157 0.015736,-0.029187 0.031472,-0.057835 0.046993,-0.085966 0.015736,-0.028131 0.031472,-0.055723 0.047208,-0.082776 0.015736,-0.027075 0.031472,-0.05361 0.047208,-0.079607 0.015736,-0.025997 0.031472,-0.051476 0.047208,-0.076417 0.015736,-0.024941 0.031472,-0.049342 0.046993,-0.073227 0.015736,-0.023885 0.031472,-0.047229 0.047208,-0.070036 0.015736,-0.022828 0.031472,-0.045117 0.047208,-0.066867 0.015736,-0.021772 0.031472,-0.042983 0.047208,-0.063677 0.015736,-0.0206937 0.031472,-0.0408704 0.047208,-0.0605081 0.01552,-0.0196377 0.031256,-0.0387364 0.046993,-0.0572961 0.015736,-0.0185817 0.031472,-0.0366244 0.047208,-0.0541281 0.015736,-0.0175248 0.031472,-0.0345115 0.047208,-0.0509592 0.015736,-0.0164477 0.031472,-0.0323555 0.047208,-0.0477472 0.015736,-0.0153908 0.031256,-0.0302435 0.046993,-0.0445783 0.015736,-0.0143348 0.031472,-0.0281306 0.047208,-0.0413883 0.015736,-0.0132788 0.031472,-0.0260186 0.047208,-0.0382194 0.015736,-0.0122008 0.031472,-0.0238626 0.047208,-0.0350074 0.015736,-0.0111448 0.031472,-0.0217717 0.046993,-0.0318605 0.015736,-0.0100668 0.031472,-0.0196157 0.047208,-0.0286485 0.015736,-0.009011 0.031472,-0.0175037 0.047208,-0.0254796 0.015736,-0.007957 0.031472,-0.0153697 0.047208,-0.0222676 0.015736,-0.006902 0.031472,-0.0132788 0.047208,-0.0191207 0.01552,-0.005821 0.031257,-0.0111448 0.046993,-0.0159087 0.015736,-0.004785 0.031472,-0.009029 0.047208,-0.0127398 0.015736,-0.003703 0.031472,-0.006902 0.047208,-0.00955 0.015736,-0.002649 0.031472,-0.004785 0.047208,-0.00638 0.015736,-0.001577 0.031257,-0.002649 0.046993,-0.003172 0.015736,-5.3891e-4 0.031472,-5.3891e-4 0.047208,0 0.015736,5.1736e-4 0.031472,0.001595 0.047208,0.003172 0.015736,0.001595 0.031472,0.003731 0.047208,0.00638 0.015736,0.002649 0.031472,0.005839 0.046993,0.00955 0.015736,0.003703 0.031472,0.007957 0.047208,0.0127398 0.015736,0.004767 0.031472,0.0100888 0.047208,0.0159087 0.015736,0.005839 0.031472,0.0122219 0.047208,0.0191207 0.015736,0.006902 0.031472,0.0143137 0.047208,0.0222676 0.01552,0.007975 0.031256,0.0164688 0.046993,0.0254796 0.015736,0.009029 0.031472,0.0185817 0.047208,0.0286485 0.015736,0.0100879 0.031472,0.0207157 0.047208,0.0318605 0.015736,0.0111228 0.031472,0.0228066 0.047208,0.0350074 0.015736,0.0122008 0.031257,0.0249406 0.046993,0.0382194 0.015736,0.0132568 0.031472,0.0270526 0.047208,0.0413883 0.015736,0.0143348 0.031472,0.0291875 0.047208,0.0445783 0.015736,0.0153908 0.031472,0.0312995 0.047208,0.0477472 0.015736,0.0164477 0.031472,0.0334335 0.046993,0.0509592 0.015736,0.0175037 0.031472,0.0355464 0.047208,0.0541281 0.015736,0.0185597 0.031472,0.0376584 0.047208,0.0572961 0.015736,0.0196377 0.031472,0.0398144 0.047208,0.0605081 0.015736,0.020694 0.031472,0.041905 0.047208,0.063677 0.015521,0.021751 0.031256,0.044039 0.046993,0.066867 0.015736,0.022807 0.031472,0.046152 0.047208,0.070036 0.015736,0.023885 0.031472,0.048286 0.047208,0.073227 0.015736,0.024941 0.031472,0.05042 0.047208,0.076417 0.015736,0.025997 0.031256,0.052532 0.046993,0.079607 0.015736,0.027054 0.031472,0.054645 0.047208,0.082776 0.015736,0.028131 0.031472,0.056779 0.047208,0.085966 0.015736,0.029188 0.031472,0.058913 0.047208,0.089157 0.015736,0.030243 0.031472,0.061026 0.046993,0.092325 0.015736,0.031322 0.031472,0.06316 0.047208,0.095516 0.015736,0.032378 0.031472,0.065272 0.047208,0.098706 0.015736,0.033433 0.031472,0.067406 0.047208,0.1018963 0.015736,0.03449 0.031472,0.069519 0.047208,0.105065 0.01552,0.035547 0.031256,0.071631 0.046993,0.1082554 0.015736,0.036624 0.031472,0.073765 0.047208,0.1114456 0.015736,0.03768 0.031472,0.075878 0.047208,0.1146144 0.015736,0.038736 0.031472,0.078012 0.047208,0.1178048 0.015736,0.039792 0.031256,0.080125 0.046993,0.1209951 0.015736,0.040849 0.031472,0.082259 0.047208,0.1241639 0.015736,0.041927 0.031472,0.084393 0.047208,0.1273756 0.015736,0.042983 0.031472,0.086484 0.047208,0.1305445 0.015736,0.044039 0.031472,0.088618 0.046993,0.1337133 0.015736,0.045117 0.031472,0.090752 0.047208,0.1369036 0.015736,0.046173 0.031472,0.092886 0.047208,0.1400938 0.015736,0.047229 0.031472,0.094998 0.047208,0.1432842 0.015736,0.048286 0.031472,0.097111 0.046993,0.1464745 0.015736,0.049342 0.031472,0.099223 0.047208,0.1496433 0.015736,0.050398 0.031472,0.1013574 0.047208,0.1528337 0.015736,0.051454 0.031472,0.1034698 0.047208,0.1560023 0.015736,0.052532 0.031472,0.1056039 0.047208,0.1591927 0.015521,0.05361 0.031256,0.107738 0.046993,0.162383 0.015736,0.054666 0.031472,0.1098505 0.047208,0.1655733 0.015736,0.055723 0.031472,0.1119631 0.047208,0.1687421 0.015736,0.056779 0.031472,0.1140972 0.047208,0.1719325 0.015736,0.057857 0.031256,0.1162311 0.046993,0.1751227 0.015736,0.058913 0.031472,0.1183437 0.047208,0.1783131 0.015736,0.059948 0.031472,0.1204561 0.047208,0.1814818 0.015736,0.061026 0.031472,0.1225687 0.047208,0.1846722 0.015733,0.062082 0.031469,0.1247027 0.046989,0.1878409"
       title="(1/(4.0*0.75))*(x*x)"
       id="path4"
       sodipodi:nodetypes="ccscscscccscccsscccscscscscssccssccsscccscccssscsscccsccssccccscccsccccscsssccssccssscsssccsscssssccsccccscccscssssssssc" />
  </g>
</svg>
      """
      #img(src = "/public/img/parabola.svg", alt = "Parabola Trajectory")
      proc onclick() = discard calcTrajectory()
      #text "Trajectory"


    button():
      span(class = "material-symbols-outlined", text "north_east")
      proc onclick() =
        sendBulletFlying()

    canvas(id = "canvas", style = fmt"width: {canvasWidth}px; height: {canvasHeight}px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

    tdiv(id = "exercises", style = "height: 200px; overflow-y: auto;".toCss):
      for e, exercise in exercises:
        if e == 0: continue # First exercise is the default exercise

        button(onclick = exerciseOnClick(e)):
          text &"#{e} angle = {exercise.angle} vi = {exercise.speed} pos = ({exercise.pos.x}, {exercise.pos.x})"

proc render*(): VNode =
  buildHtml tdiv(style = "width: 100%; justify-content: center; align-items: center;".toCss):
    renderTextDiv()
    renderSimDiv()

document.addEventListener("keyup", proc (event: Event) =
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


