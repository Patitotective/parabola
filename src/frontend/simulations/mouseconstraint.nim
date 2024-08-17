import std/[jsffi]

import matter

when defined(nimHasUsed):
  {.used.}

Matter.MouseConstraint.onmousedown = proc(mouseCons, bodies: JsObject) = 
  let
    mouse = mouseCons.mouse
    cons = mouseCons.constraint
    body = mouseCons.body

  if to(not cons.bodyB, bool):
    for b in bodies.to(seq[JsObject]):
      if Matter.Bounds.contains(b.bounds, mouse.position).to(bool) and 
        Matter.Detector.canCollide(b.collisionFilter, mouseCons.collisionFilter).to(bool):
        var i = if b.parts.length.to(int) > 1: 1 else: 0
        while i < b.parts.length.to(int):
          let part = b.parts[i]
          if Matter.Vertices.contains(part.vertices, mouse.position).to(bool):
            cons.pointA = mouse.position
            mouseCons.body = b
            cons.bodyB = mouseCons.body
            cons.pointB = jsVec(mouse.position.x - b.position.x, 
              mouse.position.y - b.position.y)
            cons.angleB = b.angle

            Matter.Sleeping.set(b, false)
            Matter.Events.trigger(mouseCons, "startdrag", JsObject{mouse: mouse, body: b})

            break
          inc i

Matter.MouseConstraint.onmouseup = proc(mouseCons: JsObject) = 
  let
    mouse = mouseCons.mouse
    cons = mouseCons.constraint
    body = mouseCons.body

  mouseCons.body = jsNull
  cons.bodyB = mouseCons.body
  cons.pointB = jsNull

  if to(body, bool):
    Matter.Events.trigger(mouseCons, "enddrag", JsObject{mouse: mouse, body: body})

Matter.MouseConstraint.update = proc(mouseCons: JsObject) = 
  let
    mouse = mouseCons.mouse
    cons = mouseCons.constraint
    #body = mouseCons.body

  if to(cons.bodyB, bool):
    Matter.Sleeping.set(cons.bodyB, false)
    cons.pointA = mouse.position
