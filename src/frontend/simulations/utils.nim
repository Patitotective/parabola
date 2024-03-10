import std/jsffi

import ../../matter

var
  infinity* {.importjs: "Infinity", nodecl.}: JsObject
  MathJax* {.importjs: "MathJax", nodecl.}: JsObject
  undefined* {.importjs: "undefined".}: JsObject

proc jsFloatToInt*(o: JsObject): JsObject {.importjs: "~~#".}

proc structuredClone*(o: JsObject): JsObject {.importjs: "structuredClone(#)".}

proc jstring*(s: string): JsObject = toJs(cstring s)

proc print*(o: JsObject) {.importjs: "console.log(structuredClone(#))".}

proc print*(o: varargs[JsObject, structuredClone]) {.importjs: "console.log(@)".}

{.emit: """
function getCircularReplacer() {
  const ancestors = [];
  return function (key, value) {
    if (typeof value !== "object" || value === null) {
      return value;
    }
    // `this` is the object that value is contained in,
    // i.e., its direct parent.
    while (ancestors.length > 0 && ancestors.at(-1) !== this) {
      ancestors.pop();
    }
    if (ancestors.includes(value)) {
      return "[Circular]";
    }
    ancestors.push(value);
    return value;
  };
}
""".}

proc jsonClone*(o: JsObject): JsObject {.importjs: "JSON.parse(JSON.stringify(#, getCircularReplacer()))".}

proc jsonPrint*(o: varargs[JsObject, jsonClone]) {.importjs: "console.log(@)".}

proc distance*(v1, v2: JsObject): JsObject = 
  JsObject{x: abs((v1.x - v2.x).to(float64)), y: abs((v1.y - v2.y).to(float64))}

proc forceToVelocity*(force: float64, mass: float64, deltaTime = 16.666): float64 = 
  let acceleration = force * mass
  acceleration * deltaTime

proc cloneAllBodies*(world: JsObject): seq[JsObject] = 
  structuredClone(Composite.allBodies(world)).to(seq[JsObject])

