import std/[jsffi, math]

import matter

var
  Infinity* {.importjs, nodecl.}: JsObject
  MathJax* {.importjs, nodecl.}: JsObject
  undefined* {.importjs, nodecl.}: JsObject
  Object* {.importjs, nodecl.}: JsObject

proc jsSleep*(ms: int) {.importjs: "await new Promise(r => setTimeout(r, #))".}

proc jsFloatToInt*(o: JsObject): JsObject {.importjs: "~~#".}

proc structuredClone*(o: JsObject): JsObject {.importjs: "structuredClone(#)".}

proc jstring*(s: string): JsObject = toJs(cstring s)

proc clonePrint*(o: JsObject) {.importjs: "console.log(structuredClone(#))".}

proc clonePrint*(o: varargs[JsObject, structuredClone]) {.importjs: "console.log(@)".}

proc print*(o: JsObject) {.importjs: "console.log(@)".}

proc print*(o: varargs[JsObject]) {.importjs: "console.log(@)".}

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

proc jsonStringify*(o: JsObject): JsObject {.importjs: "JSON.stringify(@, getCircularReplacer(), 2)".}

proc jsonPrint*(o: JsObject) {.importjs: "console.log(JSON.parse(JSON.stringify(@, getCircularReplacer())))".}

proc jsonPrint*(o: varargs[JsObject, jsonClone]) {.importjs: "console.log(@)".}

proc distance*(v1, v2: JsObject): JsObject =
  JsObject{x: abs((v1.x - v2.x).to(float64)), y: abs((v1.y - v2.y).to(float64))}

proc forceToVelocity*(force: float64, mass: float64, deltaTime = 16.666): float64 =
  let acceleration = force * mass
  acceleration * deltaTime

proc cloneAllBodies*(world: JsObject): seq[JsObject] =
  structuredClone(Composite.allBodies(world)).to(seq[JsObject])

proc speedToVelDeg*(speed, angleDeg: float): tuple[x, y: float] = 
  let angleRad = degToRad(angleDeg)
  (x: cos(angleRad) * speed, y: sin(angleRad) * speed)

proc speedToVelRad*(speed, angleRad: float): tuple[x, y: float] = 
  (x: cos(angleRad) * speed, y: sin(angleRad) * speed)

# Taken from https://codepen.io/chanthy/pen/WxQoVG
{.emit: """
function drawArrow(ctx, fromx, fromy, tox, toy, arrowWidth, color){
    //variables to be used when creating the arrow
    var headlen = 10;
    var angle = Math.atan2(toy-fromy,tox-fromx);
 
    ctx.save();
    ctx.strokeStyle = color;
 
    //starting path of the arrow from the start square to the end square
    //and drawing the stroke
    ctx.beginPath();
    ctx.moveTo(fromx, fromy);
    ctx.lineTo(tox, toy);
    ctx.lineWidth = arrowWidth;
    ctx.stroke();
 
    //starting a new path from the head of the arrow to one of the sides of
    //the point
    ctx.beginPath();
    ctx.moveTo(tox, toy);
    ctx.lineTo(tox-headlen*Math.cos(angle-Math.PI/7),
               toy-headlen*Math.sin(angle-Math.PI/7));
 
    //path from the side point of the arrow, to the other side point
    ctx.lineTo(tox-headlen*Math.cos(angle+Math.PI/7),
               toy-headlen*Math.sin(angle+Math.PI/7));
 
    //path from the side point back to the tip of the arrow, and then
    //again to the opposite side point
    ctx.lineTo(tox, toy);
    ctx.lineTo(tox-headlen*Math.cos(angle-Math.PI/7),
               toy-headlen*Math.sin(angle-Math.PI/7));
 
    //draws the paths created above
    ctx.stroke();
    ctx.restore();
}
"""}

proc drawArrow*(ctx, fromx, fromy, tox, toy, arrowWidth, color: JsObject) {.importjs: "drawArrow(@)".} 

#proc drawArrow*(ctx: JsObject, fromPos, toPos: JsVector, arrowWidth: float, color: string) = 
#  drawArrow(ctx, JsObject(fromPos).x, JsObject(fromPos).y, JsObject(toPos).x, JsObject(toPos).y, toJs arrowWidth, toJs color.cstring)
