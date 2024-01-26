import std/jsffi

import ../../matter

proc jsFloatToInt*(o: JsObject): JsObject {.importjs: "~~#".}

proc structuredClone*(o: JsObject): JsObject {.importjs: "structuredClone(#)".}

proc jstring*(s: string): JsObject = toJs(cstring s)

proc print*(o: varargs[JsObject, structuredClone]) {.importjs: "console.log(@)".}

proc forceToVelocity*(force: float64, mass: float64, deltaTime = 16.666): float64 = 
  let acceleration = force * mass
  acceleration * deltaTime

proc cloneAllBodies*(world: JsObject): seq[JsObject] = 
  structuredClone(Composite.allBodies(world)).to(seq[JsObject])

