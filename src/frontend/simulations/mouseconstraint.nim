import std/[jsffi]

import matter

Matter.MouseConstraint.onmousedown = proc(mouseCons, bodies: JsObject) = 
  let
    mouse = mouseCons.mouse
    cons = mouseCons.constraint
    body = mouseCons.body

  if to(not cons.bodyB, bool):
    for body in bodies.to(seq[JsObject]):
      if Matter.Bounds.contains(body.bounds, mouse.position).to(bool) and 
        Matter.Detector.canCollide(body.collisionFilter, mouseCons.collisionFilter).to(bool):
        var i = if body.parts.length.to(int) > 1: 1 else: 0
        while i < body.parts.length.to(int):
          let part = body.parts[i]
          if Matter.Vertices.contains(part.vertices, mouse.position).to(bool):
            cons.pointA = mouse.position
            mouseCons.body = body
            cons.bodyB = mouseCons.body
            cons.pointB = jsVec(mouse.position.x - body.position.x, 
              mouse.position.y - body.position.y)
            cons.angleB = body.angle

            Matter.Sleeping.set(body, false)
            Matter.Events.trigger(mouseCons, "startdrag", JsObject{mouse: mouse, body: body})

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
    body = mouseCons.body

  if to(cons.bodyB, bool):
    Matter.Sleeping.set(cons.bodyB, false)
    cons.pointA = mouse.position
