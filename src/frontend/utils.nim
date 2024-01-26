import std/[tables, uri, dom]
import karax/[karaxdsl, vdom]

import patterns
from ../config import nil

type
  Params* = Table[string, string]

  Route* = object
    path*: string
    renderProc*: proc (params: Params): VNode

proc navigateTo*(uri: cstring) =
  window.history.pushState(0, cstring"", uri)

  # Fire the popState event.
  dom.window.dispatchEvent(dom.newEvent("popstate"))

proc renderError404*(): VNode =
  buildHtml(tdiv):
    text "Couldn't find the page you were looking for"
    text "Error 404"

proc r*(path: string, renderProc: proc (params: Params): VNode): Route = Route(path: path, renderProc: renderProc)

proc route*(loc: Location, routes: openarray[Route]): VNode =
  # path is the current URL path
  let path = if loc.pathname.len == 0: "/" else: $loc.pathname
  let appPath = if config.appPath == "/": "" else: config.appPath

  for route in routes:
    let pattern = (appPath & route.path).parsePattern()
    var (matched, params) = pattern.match(path)

    for (k, v) in decodeQuery($loc.search):
      params[k] = v

    if matched:
      return route.renderProc(params)

  return renderError404()#buildHtml(tdiv(text "Unmatched route: " & path))#renderError("Unmatched route: " & path, Http500)

