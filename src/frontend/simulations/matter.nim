## This module implements some types, variables and procedures to ease the use of matter-js

import std/[jsffi, math]

var
  Matter* {.importjs, nodecl.}: JsObject
  MatterWrap* {.importjs, nodecl.}: JsObject
  Body*, Vector*, Engine*, Render*, Runner*, Bodies*, Bounds*, Events*, Composite*, MouseConstraint*, Mouse*, Constraint*: JsObject

# This function is used to load Matter's aliases
# since when using plugins you should reload aliases
proc loadMatterAliases*() =
  Body = Matter.Body
  Vector = Matter.Vector
  Engine = Matter.Engine
  Render = Matter.Render
  Runner = Matter.Runner
  Bodies = Matter.Bodies
  Bounds = Matter.Bounds
  Events = Matter.Events
  Composite = Matter.Composite
  MouseConstraint = Matter.MouseConstraint
  Mouse = Matter.Mouse
  Constraint = Matter.Constraint

type
  Vec* = tuple[x, y: float]

proc createEngine*(options: JsObject = nil): JsObject {.importjs: "Matter.Engine.create(#)".}
proc createRender*(options: JsObject): JsObject {.importjs: "Matter.Render.create(#)".}
proc jsVec*(x, y: SomeNumber or JsObject): JsObject = JsObject{x: x, y: y}
proc jsVec*(v: Vec): JsObject = JsObject{x: v.x, y: v.y}

proc setY*(body: JsObject, y: SomeNumber) = 
  Body.setPosition(body, JsObject{x: body.position.x, y: y})

proc setX*(body: JsObject, x: SomeNumber) = 
  Body.setPosition(body, JsObject{y: body.position.y, x: x})

proc setPos*(body: JsObject, x, y: SomeNumber or JsObject) = 
  Body.setPosition(body, JsObject{x: x, y: y})

proc getX*(body: JsObject): float = 
  body.position.x.to(float)

proc getY*(body: JsObject): float = 
  body.position.y.to(float)

proc getPos*(body: JsObject): tuple[x, y: float] = 
  (body.position.x.to(float), body.position.y.to(float))

proc vec*(v: JsObject): Vec = 
  (x: v.x.to(float), y: v.y.to(float))

proc vec*(x, y: JsObject): Vec = 
  (x: x.to(float), y: y.to(float))

proc vec*(x, y: float): Vec = 
  (x: x, y: y)

proc `*`*(v1, v2: Vec): Vec =
  (x: v1.x * v2.x, y: v1.y * v2.y)

proc `+`*(v1, v2: Vec): Vec =
  (x: v1.x + v2.x, y: v1.y + v2.y)

proc `-`*(v1, v2: Vec): Vec =
  (x: v1.x - v2.x, y: v1.y - v2.y)

proc `/`*(v1, v2: Vec): Vec =
  (x: v1.x / v2.x, y: v1.y / v2.y)

proc `*`*(v1: Vec, v2: float): Vec =
  (x: v1.x * v2, y: v1.y * v2)

proc `+`*(v1: Vec, v2: float): Vec =
  (x: v1.x + v2, y: v1.y + v2)

proc `-`*(v1: Vec, v2: float): Vec =
  (x: v1.x - v2, y: v1.y - v2)

proc `/`*(v1: Vec, v2: float): Vec =
  (x: v1.x / v2, y: v1.y / v2)

proc distance*(v1, v2: Vec): float = 
  sqrt(abs((v2.x - v1.x)^2 + (v2.y - v1.y)^2))

proc distanceInt*(v1, v2: Vec): int = 
  int sqrt(abs((v2.x - v1.x)^2 + (v2.y - v1.y)^2))

proc distanceSquared*(v1, v2: Vec): float = 
  (v2.x - v1.x)^2 + (v2.y - v1.y)^2
