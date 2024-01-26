import std/[jsffi]

var
  Matter {.importjs, nodecl.}: JsObject
  Body* = Matter.Body
  Vector* = Matter.Vector
  Engine* = Matter.Engine
  Render* = Matter.Render
  Runner* = Matter.Runner
  Bodies* = Matter.Bodies
  Events* = Matter.Events
  Composite* = Matter.Composite

proc createEngine*(options: JsObject = nil): JsObject {.importjs: "Matter.Engine.create(#)".}
proc createRender*(options: JsObject): JsObject {.importjs: "Matter.Render.create(#)".}

