import std/[jsffi, math]

import matter

const
  parabolaIconSvg* = """
    <svg
       width="24"
       height="24"
       viewBox="0 0 6.3499999 6.35"
       version="1.1"
       id="svg1"
       inkscape:version="1.3.2 (1:1.3.2+202311252150+091e20ef0f)"
       sodipodi:docname="parabola.svg"
       xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
       xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
       xmlns="http://www.w3.org/2000/svg"
       xmlns:svg="http://www.w3.org/2000/svg">
      <sodipodi:namedview
         id="namedview1"
         pagecolor="#ffffff"
         bordercolor="#000000"
         borderopacity="0.25"
         inkscape:showpageshadow="2"
         inkscape:pageopacity="0.0"
         inkscape:pagecheckerboard="0"
         inkscape:deskcolor="#d1d1d1"
         inkscape:document-units="mm"
         inkscape:zoom="22.627417"
         inkscape:cx="4.0879611"
         inkscape:cy="13.457126"
         inkscape:window-width="1920"
         inkscape:window-height="1006"
         inkscape:window-x="0"
         inkscape:window-y="0"
         inkscape:window-maximized="1"
         inkscape:current-layer="layer1" />
      <defs id="defs1"/>
      <g
         inkscape:label="Layer 1"
         inkscape:groupmode="layer"
         id="layer1">
        <path
           style="fill:none;stroke:#000000;stroke-width:0.68;stroke-dasharray:1.36,0.68;stroke-dashoffset:0"
           d="m 0.36912046,6.0312671 c 0.0157364,-0.063138 0.0314718,-0.125759 0.0472082,-0.1878409 0.0157364,-0.062103 0.0314718,-0.1236465 0.0472082,-0.1846722 0.0157364,-0.061026 0.0312564,-0.121534 0.0469928,-0.1814818 0.0157364,-0.059969 0.0314718,-0.1193999 0.0472082,-0.1783131 0.0157364,-0.058913 0.0314718,-0.1172658 0.0472082,-0.1751227 0.0157364,-0.057835 0.0314718,-0.1151534 0.0472082,-0.1719325 0.0157364,-0.056779 0.0314718,-0.1130192 0.0469928,-0.1687421 0.0157364,-0.055723 0.0314718,-0.1109067 0.0472082,-0.1655733 0.0157364,-0.054645 0.0314718,-0.1087727 0.0472082,-0.162383 0.0157364,-0.053589 0.0314719,-0.1066602 0.0472082,-0.1591927 0.0157364,-0.052532 0.0314718,-0.1045477 0.0472082,-0.1560023 0.0155201,-0.051476 0.0312564,-0.1024352 0.0469928,-0.1528337 0.0157364,-0.05042 0.0314718,-0.1003011 0.0472082,-0.1496433 0.0157364,-0.049363 0.0314718,-0.098189 0.0472082,-0.1464745 0.015736,-0.048286 0.031472,-0.096054 0.047208,-0.1432842 0.015736,-0.047229 0.031256,-0.09392 0.046993,-0.1400938 0.015736,-0.046152 0.031472,-0.091786 0.047208,-0.1369036 0.015736,-0.045095 0.031472,-0.089674 0.047208,-0.1337133 0.015736,-0.044061 0.031472,-0.087562 0.047208,-0.1305445 0.015736,-0.042983 0.031472,-0.085449 0.046993,-0.1273756 0.015736,-0.041905 0.031472,-0.083294 0.047208,-0.1241639 0.015736,-0.04087 0.031472,-0.081181 0.047208,-0.1209951 0.015736,-0.039792 0.031472,-0.079068 0.047208,-0.1178048 0.015736,-0.038736 0.031472,-0.076934 0.047208,-0.1146144 0.015521,-0.03768 0.031256,-0.074822 0.046993,-0.1114456 0.015736,-0.036624 0.031472,-0.072688 0.047208,-0.1082554 0.015736,-0.035546 0.031472,-0.070575 0.047208,-0.105065 0.015736,-0.03449 0.031472,-0.068463 0.047208,-0.1018963 0.015736,-0.033434 0.031256,-0.066328 0.046993,-0.098706 0.015736,-0.032355 0.031472,-0.064194 0.047208,-0.095516 0.015736,-0.0313 0.031472,-0.062082 0.047208,-0.092325 0.015736,-0.030244 0.031472,-0.059969 0.047208,-0.089157 0.015736,-0.029187 0.031472,-0.057835 0.046993,-0.085966 0.015736,-0.028131 0.031472,-0.055723 0.047208,-0.082776 0.015736,-0.027075 0.031472,-0.05361 0.047208,-0.079607 0.015736,-0.025997 0.031472,-0.051476 0.047208,-0.076417 0.015736,-0.024941 0.031472,-0.049342 0.046993,-0.073227 0.015736,-0.023885 0.031472,-0.047229 0.047208,-0.070036 0.015736,-0.022828 0.031472,-0.045117 0.047208,-0.066867 0.015736,-0.021772 0.031472,-0.042983 0.047208,-0.063677 0.015736,-0.0206937 0.031472,-0.0408704 0.047208,-0.0605081 0.01552,-0.0196377 0.031256,-0.0387364 0.046993,-0.0572961 0.015736,-0.0185817 0.031472,-0.0366244 0.047208,-0.0541281 0.015736,-0.0175248 0.031472,-0.0345115 0.047208,-0.0509592 0.015736,-0.0164477 0.031472,-0.0323555 0.047208,-0.0477472 0.015736,-0.0153908 0.031256,-0.0302435 0.046993,-0.0445783 0.015736,-0.0143348 0.031472,-0.0281306 0.047208,-0.0413883 0.015736,-0.0132788 0.031472,-0.0260186 0.047208,-0.0382194 0.015736,-0.0122008 0.031472,-0.0238626 0.047208,-0.0350074 0.015736,-0.0111448 0.031472,-0.0217717 0.046993,-0.0318605 0.015736,-0.0100668 0.031472,-0.0196157 0.047208,-0.0286485 0.015736,-0.009011 0.031472,-0.0175037 0.047208,-0.0254796 0.015736,-0.007957 0.031472,-0.0153697 0.047208,-0.0222676 0.015736,-0.006902 0.031472,-0.0132788 0.047208,-0.0191207 0.01552,-0.005821 0.031257,-0.0111448 0.046993,-0.0159087 0.015736,-0.004785 0.031472,-0.009029 0.047208,-0.0127398 0.015736,-0.003703 0.031472,-0.006902 0.047208,-0.00955 0.015736,-0.002649 0.031472,-0.004785 0.047208,-0.00638 0.015736,-0.001577 0.031257,-0.002649 0.046993,-0.003172 0.015736,-5.3891e-4 0.031472,-5.3891e-4 0.047208,0 0.015736,5.1736e-4 0.031472,0.001595 0.047208,0.003172 0.015736,0.001595 0.031472,0.003731 0.047208,0.00638 0.015736,0.002649 0.031472,0.005839 0.046993,0.00955 0.015736,0.003703 0.031472,0.007957 0.047208,0.0127398 0.015736,0.004767 0.031472,0.0100888 0.047208,0.0159087 0.015736,0.005839 0.031472,0.0122219 0.047208,0.0191207 0.015736,0.006902 0.031472,0.0143137 0.047208,0.0222676 0.01552,0.007975 0.031256,0.0164688 0.046993,0.0254796 0.015736,0.009029 0.031472,0.0185817 0.047208,0.0286485 0.015736,0.0100879 0.031472,0.0207157 0.047208,0.0318605 0.015736,0.0111228 0.031472,0.0228066 0.047208,0.0350074 0.015736,0.0122008 0.031257,0.0249406 0.046993,0.0382194 0.015736,0.0132568 0.031472,0.0270526 0.047208,0.0413883 0.015736,0.0143348 0.031472,0.0291875 0.047208,0.0445783 0.015736,0.0153908 0.031472,0.0312995 0.047208,0.0477472 0.015736,0.0164477 0.031472,0.0334335 0.046993,0.0509592 0.015736,0.0175037 0.031472,0.0355464 0.047208,0.0541281 0.015736,0.0185597 0.031472,0.0376584 0.047208,0.0572961 0.015736,0.0196377 0.031472,0.0398144 0.047208,0.0605081 0.015736,0.020694 0.031472,0.041905 0.047208,0.063677 0.015521,0.021751 0.031256,0.044039 0.046993,0.066867 0.015736,0.022807 0.031472,0.046152 0.047208,0.070036 0.015736,0.023885 0.031472,0.048286 0.047208,0.073227 0.015736,0.024941 0.031472,0.05042 0.047208,0.076417 0.015736,0.025997 0.031256,0.052532 0.046993,0.079607 0.015736,0.027054 0.031472,0.054645 0.047208,0.082776 0.015736,0.028131 0.031472,0.056779 0.047208,0.085966 0.015736,0.029188 0.031472,0.058913 0.047208,0.089157 0.015736,0.030243 0.031472,0.061026 0.046993,0.092325 0.015736,0.031322 0.031472,0.06316 0.047208,0.095516 0.015736,0.032378 0.031472,0.065272 0.047208,0.098706 0.015736,0.033433 0.031472,0.067406 0.047208,0.1018963 0.015736,0.03449 0.031472,0.069519 0.047208,0.105065 0.01552,0.035547 0.031256,0.071631 0.046993,0.1082554 0.015736,0.036624 0.031472,0.073765 0.047208,0.1114456 0.015736,0.03768 0.031472,0.075878 0.047208,0.1146144 0.015736,0.038736 0.031472,0.078012 0.047208,0.1178048 0.015736,0.039792 0.031256,0.080125 0.046993,0.1209951 0.015736,0.040849 0.031472,0.082259 0.047208,0.1241639 0.015736,0.041927 0.031472,0.084393 0.047208,0.1273756 0.015736,0.042983 0.031472,0.086484 0.047208,0.1305445 0.015736,0.044039 0.031472,0.088618 0.046993,0.1337133 0.015736,0.045117 0.031472,0.090752 0.047208,0.1369036 0.015736,0.046173 0.031472,0.092886 0.047208,0.1400938 0.015736,0.047229 0.031472,0.094998 0.047208,0.1432842 0.015736,0.048286 0.031472,0.097111 0.046993,0.1464745 0.015736,0.049342 0.031472,0.099223 0.047208,0.1496433 0.015736,0.050398 0.031472,0.1013574 0.047208,0.1528337 0.015736,0.051454 0.031472,0.1034698 0.047208,0.1560023 0.015736,0.052532 0.031472,0.1056039 0.047208,0.1591927 0.015521,0.05361 0.031256,0.107738 0.046993,0.162383 0.015736,0.054666 0.031472,0.1098505 0.047208,0.1655733 0.015736,0.055723 0.031472,0.1119631 0.047208,0.1687421 0.015736,0.056779 0.031472,0.1140972 0.047208,0.1719325 0.015736,0.057857 0.031256,0.1162311 0.046993,0.1751227 0.015736,0.058913 0.031472,0.1183437 0.047208,0.1783131 0.015736,0.059948 0.031472,0.1204561 0.047208,0.1814818 0.015736,0.061026 0.031472,0.1225687 0.047208,0.1846722 0.015733,0.062082 0.031469,0.1247027 0.046989,0.1878409"
           title="(1/(4.0*0.75))*(x*x)"
           id="path4"
           sodipodi:nodetypes="ccscscscccscccsscccscscscscssccssccsscccscccssscsscccsccssccccscccsccccscsssccssccssscsssccsscssssccsccccscccscssssssssc" />
      </g>
    </svg>
  """

var
  Infinity* {.importjs, nodecl.}: JsObject
  MathJax* {.importjs, nodecl.}: JsObject
  undefined* {.importjs, nodecl.}: JsObject
  Object* {.importjs, nodecl.}: JsObject
  Epsilon* {.importjs: "Number.EPSILON", nodecl.}: JsObject

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
  structuredClone(Matter.Composite.allBodies(world)).to(seq[JsObject])

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
 
    //ctx.save();
    ctx.strokeStyle = color;
    ctx.fillStyle = color;
 
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
    //ctx.restore();
}
"""}

proc drawArrow*(ctx, fromx, fromy, tox, toy, arrowWidth, color: JsObject) {.importjs: "drawArrow(@)".} 

proc newImage*(): JsObject {.importjs: "new Image()".}

var maskDefault* {.importjs: "0xFFFFFFFF", nodecl.}: JsObject

proc isBetween*(c, a, b: Vec): bool = 
  return (distance(a, c) + distance(c, b)) - distance(a, b) == 0

iterator countthrough*(these: varargs[float], step: float): float {.inline.} =
  var res = these[0]
  for i in these[1..^1]:
    while res < i:
      yield res
      res += step

    yield i

proc contains*[T: not int](a: openArray[T], index: int): bool = 
  index in a.low..a.high

# MU = My Unit system
 #we do some adjustments so the numbers aren't so big...
const muMeterFactor* = 10.0

proc toMuDistance*(m: float): float = 
  m / muMeterFactor

#proc toSiTime*(t, delta: float): float = 
#  ## [delta] -> [s]
#  (t / delta) / 1000

proc toMuSpeed*(speed: float): float = 
  speed / muMeterFactor

proc toMuAcceleration*(acceleration: float): float = 
  acceleration / muMeterFactor

proc fromMuDistance*(m: float): float = 
  m * muMeterFactor

proc fromMuSpeed*(speed: float): float = 
  speed * muMeterFactor

proc fromMuAcceleration*(acceleration: float): float = 
  acceleration * muMeterFactor

proc class*(classes: varargs[tuple[name: string, present: bool]],
           defaultClasses: string = ""): string =
  result = defaultClasses & " "
  for class in classes:
    if class.present: result.add(class.name & " ")
