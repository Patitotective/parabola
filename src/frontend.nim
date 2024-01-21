import std/[dom, json, asyncjs, jsffi, math, jsconsole, enumerate]
import karax/[karax, kajax, karaxdsl, vdom, vstyles]

import matter
import frontend/[utils, user]

type
  State = ref object
    prevTitle*: cstring # Title of the previous page when using navigateTo()
    location*: Location

const deltaTime = 16.666

proc deepCopy(l: Location): Location =
  Location(
    hash: l.hash,
    host: l.host,
    hostname: l.hostname,
    href: l.href,
    pathname: l.pathname,
    port: l.port,
    protocol: l.protocol,
    search: l.search,
    origin: l.origin,
  )
proc newState(): State =
  State(location: window.location.deepCopy(), prevTitle: document.title)

proc jsToInt(o: JsObject): JsObject {.importjs: "~~#".}

proc structuredClone(o: JsObject): JsObject {.importjs: "structuredClone(#)".}

proc jstring(s: string): JsObject = toJs(cstring s)

proc print(o: varargs[JsObject, structuredClone]) {.importjs: "console.log(@)".}

proc forceToVelocity(force: float64, mass: float64): float64 = 
  let acceleration = force * mass
  acceleration * deltaTime

proc cloneAllBodies*(world: JsObject): seq[JsObject] = 
  structuredClone(Composite.allBodies(world)).to(seq[JsObject])

var state = newState()
var engine, mrender, bullet, ground, runner: JsObject
# var oldBullet: JsObject
var trail = newSeq[JsObject]() # @[JsObject{x: 465.0760299519404, y: 465.07603022971864}]#

proc loadMatter() = 
  engine = Engine.create()
  mrender = Render.create(JsObject{
    canvas: getElementById("canvas"), 
    engine: engine,
    options: JsObject{
      width: 500,
      height: 500,
      showAngleIndicator: true,
      background: "rgb(20, 21, 31)",
    }
  })
  Render.run(mrender)

  runner = Runner.create(JsObject{delta: deltaTime})
  Runner.run(runner, engine)

  bullet = Bodies.circle(400, 300, 20, JsObject{isStatic: false})

  Composite.add(engine.world, toJs [bullet, 
    # Walls
    Bodies.rectangle(250, 10, 500, 20, JsObject{isStatic: true}),
    Bodies.rectangle(495, 250, 20, 500, JsObject{isStatic: true}),
    Bodies.rectangle(250, 495, 500, 20, JsObject{isStatic: true}),
    Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true})

  ])

  Events.on(mrender, "afterRender", proc() =
    Render.startViewTransform(mrender)
    mrender.context.globalAlpha = 0.7

    for i in trail:
      mrender.context.fillStyle = cstring"orange"
      mrender.context.fillRect(i.x, i.y, 2, 2)

    mrender.context.globalAlpha = 1
    Render.endViewTransform(mrender)
  )
  
proc renderHome(params: Params): VNode =
  buildHtml(tdiv):
    text "Welcome to my grado project"

proc renderSimulation(params: Params): VNode =
  buildHtml(tdiv):
    button():
      text "Start the simulation"
      proc onclick()  =
        if engine.isNil:
          loadMatter()
        else:
          engine.timing.timeScale = 1
      
    button():
      text "Stop the simulation"
      proc onclick() = 
        engine.timing.timeScale = 0

    button():
      text "Rotate"
      proc onclick() = 
        Body.rotate(bullet, 1)

    button():
      text "Trajectory"
      proc onclick() = 
        # let oldBullet = bullet.structuredClone()
        let bodies = cloneAllBodies(engine.world)
        # print jstring"before force", oldBullet, bullet
        Body.applyForce(bullet, bullet.position, JsObject{x: cos(bullet.angle.to(float64)) * 0.08, y: sin(bullet.angle.to(float64)) * 0.08})
        # print jstring"after force", oldBullet, bullet

        trail.setLen(0)
        for i in 1..100:
          trail.add JsObject{x: jsToInt bullet.position.x, y: jsToInt bullet.position.y}
          # `.()`(Engine, "_bodiesApplyGravity", toJs [bullet], engine.gravity)
          # Body.update(bullet, 5)
          Engine.update(engine)

        for (e, b) in enumerate Composite.allBodies(engine.world):
          assert b.id == bodies[e].id
          b.anglePrev = oldb.anglePrev
          b.force = oldb.force
          b.torque = oldb.torque
          Body.setVelocity(b, oldb.velocity)
          Body.setAngularVelocity(b, oldb.angularVelocity)
          Body.setAngle(b, oldb.angle)
          Body.setPosition(b, oldb.position)

        # print jstring"before restore", oldBullet, bullet
        # bullet.anglePrev = oldBullet.anglePrev
        # bullet.force = oldBullet.force
        # bullet.torque = oldBullet.torque
        # Body.setVelocity(bullet, oldBullet.velocity)
        # Body.setAngularVelocity(bullet, oldBullet.angularVelocity)
        # Body.setAngle(bullet, oldBullet.angle)
        # Body.setPosition(bullet, oldBullet.position)
        # print jstring"after restore", oldBullet, bullet

        # let vx = forceToVelocity(cos(bullet.angle.to(float64)) * 0.08, bullet.mass.to(float64)) 
        # let vy = forceToVelocity(sin(bullet.angle.to(float64)) * 0.08, bullet.mass.to(float64)) 
        # let g = engine.gravity.y.to(float64) * engine.gravity.scale.to(float64)
        # echo (vx: vx, vy: vy)

        # trail.setLen(0)
        # for i in 1..50:
        #   let t = (i.float64 / 2) * deltaTime
        #   trail.add Vector.add(bullet.position, JsObject{x: vx * t, y: 0.5 * g * t.pow(2) + vy * t})
        

    button():
      text "Send ball flying"
      proc onclick() = 
        # Body.setStatic(bullet, false)
        # Body.setPosition(bullet, JsObject{x: 400, y: 300})
        # Body.setSpeed(bullet, JsObject{x: -15, y: -10})
        Body.applyForce(bullet, bullet.position, JsObject{x: cos(bullet.angle.to(float64)) * 0.08, y: sin(bullet.angle.to(float64)) * 0.08})

    canvas(id = "canvas"):#style = "width: 500px; height: 500px; background: rgb(20, 21, 31) 0% 0% / contain".toCss):
      text "Matter-js simulation"

proc render(): VNode =
  result = buildHtml(tdiv):
    # renderHeader()
    state.location.route([
      r("/s/1", renderSimulation),
      r("/", renderHome),
    ])

window.onPopState = proc(event: Event) =
  # This event is usually only called when the user moves back in history.
  # echo (old: state.location.href, new: window.location.href)
  document.title = state.prevTitle
  if state.location.href != window.location.href:
    state = newState() # Reload the state to remove stale data.
  else:
    state.location = window.location.deepCopy()

  redraw()

# window.onload = proc(event: Event) = loadMatter()

setRenderer render

