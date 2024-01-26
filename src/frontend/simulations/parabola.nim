import std/[math, jsffi, dom, jsconsole, enumerate]
import karax/[karax, karaxdsl, vdom, vstyles]

import ../../matter, ../utils, utils

const deltaTime = 16.666

var engine*, mrender*, bullet, ground*, runner*: JsObject
var trail = newSeq[JsObject]()

proc load*() = #canvasId: string, canvasWidth, canvasHeight: int, background: string) = 
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
  
  bullet = Bodies.circle(400, 300, 25, JsObject{isStatic: false})
  Body.setAngle(bullet, degToRad(180d))

  Composite.add(engine.world, toJs [bullet, 
    # Walls
    Bodies.rectangle(250, 10, 500, 20, JsObject{isStatic: true}),
    Bodies.rectangle(495, 250, 20, 500, JsObject{isStatic: true}),
    Bodies.rectangle(250, 495, 500, 20, JsObject{isStatic: true}),
    Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}),
    # Thingy
    Bodies.rectangle(400, 350, 20, 80, JsObject{isStatic: true})

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

proc calcTrajectory() = 
  var stop = false

  let bodies = cloneAllBodies(engine.world)

  Events.on(engine, "collisionStart", 
    proc (event: JsObject) = 
      if event.pairs[0].bodyA.id == bullet.id:
        stop = true
  )

  let force = bullet.circleRadius.to(float64) / 250
  Body.applyForce(bullet, bullet.position, JsObject{x: cos(bullet.angle.to(float64)) * force, y: sin(bullet.angle.to(float64)) * force})

  trail.setLen(0)
  for i in 1..1000:
    trail.add JsObject{x: jsFloatToInt bullet.position.x, y: jsFloatToInt bullet.position.y}

    if stop:
      break

    Engine.update(engine)

  Events.off(engine, "collitionStart")

  for (e, b) in enumerate Composite.allBodies(engine.world):
    assert b.id == bodies[e].id
    let oldb = bodies[e]

    b.anglePrev = oldb.anglePrev
    b.force = oldb.force
    b.torque = oldb.torque
    Body.setPosition(b, oldb.position)
    Body.setVelocity(b, oldb.velocity)
    Body.setAngularVelocity(b, oldb.angularVelocity)
    Body.setAngle(b, oldb.angle)

proc render*(params: Params): VNode =
  result = buildHtml(tdiv):
    button():
      text "Start the simulation"
      proc onclick()  =
        # if engine.isNil:
          # loadMatter("canvas", 500, 500, "rgb(20, 21, 31)")
        # else:
          engine.timing.timeScale = 1
      
    button():
      text "Stop the simulation"
      proc onclick() = 
        engine.timing.timeScale = 0

    button():
      text "Rotate"
      proc onclick() = 
        Body.rotate(bullet, degToRad((360 / bullet.vertices.length.to(float64))*2))

    button(onclick = calcTrajectory):
      text "Trajectory"

    button():
      text "Rot & Traj"
      proc onclick() = 
        Body.rotate(bullet, degToRad((360 / bullet.vertices.length.to(float64))*2))
        echo degToRad(360 / bullet.vertices.length.to(float64))
        print bullet.angle
        calcTrajectory()

    button():
      text "Send ball flying"
      proc onclick() = 
        let force = bullet.circleRadius.to(float64) / 250
        Body.applyForce(bullet, bullet.position, JsObject{x: cos(bullet.angle.to(float64)) * force, y: sin(bullet.angle.to(float64)) * force})

    canvas(id = "canvas", style = "width: 500px; height: 500px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

