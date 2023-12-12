import std/[tables, dom, uri]
import karax/[kbase, karax, karaxdsl, vdom, compact, jstrutils]
import jester/patterns

from config import nil

type
  Params = Table[string, string]
  Route = object
    path: string
    renderProc: proc (params: Params): VNode

proc r(path: string, renderProc: proc (params: Params): VNode): Route = Route(path: path, renderProc: renderProc)

proc route(routes: openarray[Route]): VNode =
  # Current URL path
  let path = if window.location.pathname.len == 0: "/" else: $window.location.pathname  
  let appPath = if config.appPath == "/": "" else: config.appPath

  for route in routes:
    let pattern = (appPath & route.path).parsePattern()
    var (matched, params) = pattern.match(path)

    for (k, v) in decodeQuery($window.location.search):
      params[k] = v
    
    if matched:
      return route.renderProc(params)

  return buildHtml(tdiv(text "Unmatched route: " & path))#renderError("Unmatched route: " & path, Http500)

proc renderHome(params: Params): VNode =
  buildHtml(tdiv(id="home")):
    text "Hello Home"
    button:
      text "Click me"
      proc onclick() = 
        window.history.pushState(0, cstring"", "/sub");

proc renderSub(params: Params): VNode =
  buildHtml(tdiv(id="home")):
    text "Hello Sub"
    button:
      text "Go back"
      proc onclick() = 
        window.history.pushState(0, cstring"", cstring"/");

proc render(): VNode =
  result = buildHtml(tdiv):
    # renderHeader()
    route([
      r("/", renderHome),
      r("/sub", renderSub),
    ])

setRenderer render

