## This module implements some types, variables and procedures to ease the use of matter-js

import std/[jsffi]

var
  Matter* {.importjs, nodecl.}: JsObject
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
  JsVector* = distinct JsObject

proc createEngine*(options: JsObject = nil): JsObject {.importjs: "Matter.Engine.create(#)".}
proc createRender*(options: JsObject): JsObject {.importjs: "Matter.Render.create(#)".}
proc jsVector*(x, y: SomeNumber): JsVector = JsVector JsObject{x: x, y: y}
proc jsVector*(x, y: JsObject): JsVector = JsVector JsObject{x: x, y: y}

proc `*`*(v1, v2: JsVector): JsVector =
  JsVector JsObject{x: JsObject(v1).x * JsObject(v2).x, y: JsObject(v1).y * JsObject(v2).y}

proc `+`*(v1, v2: JsVector): JsVector =
  JsVector JsObject{x: JsObject(v1).x + JsObject(v2).x, y: JsObject(v1).y + JsObject(v2).y}

proc `-`*(v1, v2: JsVector): JsVector =
  JsVector JsObject{x: JsObject(v1).x - JsObject(v2).x, y: JsObject(v1).y - JsObject(v2).y}

proc `/`*(v1, v2: JsVector): JsVector =
  JsVector JsObject{x: JsObject(v1).x / JsObject(v2).x, y: JsObject(v1).y / JsObject(v2).y}

proc `*`*(v1: JsVector, v2: float64): JsVector =
  JsVector JsObject{x: JsObject(v1).x * v2.toJs, y: JsObject(v1).y * v2.toJs}

proc `+`*(v1: JsVector, v2: float64): JsVector =
  JsVector JsObject{x: JsObject(v1).x + v2.toJs, y: JsObject(v1).y + v2.toJs}

proc `-`*(v1: JsVector, v2: float64): JsVector =
  JsVector JsObject{x: JsObject(v1).x - v2.toJs, y: JsObject(v1).y - v2.toJs}

proc `/`*(v1: JsVector, v2: float64): JsVector =
  JsVector JsObject{x: JsObject(v1).x / v2.toJs, y: JsObject(v1).y / v2.toJs}


