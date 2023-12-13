import std/[tables, dom, uri]
import karax/[kbase, karax, karaxdsl, vdom, compact, jstrutils]
import jester/patterns

from config import nil

type
  State = ref object
    prevTitle*: cstring # Title of the previous page when using navigateTo()
    location*: Location

proc deepCopy(l: Location): Location =
  Location(
    hash: l.hash,
    host: l.host,
    hostname: l.hostname,
    href: l.href,
    pathname: l.pathname,
    port: l.port,
    protocol: l.protocol,
    search: l.search
  )

proc newState(): State =
  State(location: window.location.deepCopy(), prevTitle: document.title)

var state = newState()

proc navigateTo*(uri: cstring) =
  window.history.pushState(0, cstring"", uri)

  # Fire the popState event.
  dom.window.dispatchEvent(dom.newEvent("popstate"))

proc onPopState(event: dom.Event) =
  # This event is usually only called when the user moves back in history.
  # echo (old: state.location.href, new: window.location.href)
  document.title = state.prevTitle
  if state.location.href != window.location.href:
    state = newState() # Reload the state to remove stale data.
  else:
    state.location = window.location.deepCopy()

  redraw()

type
  Params = Table[string, string]
  Route = object
    path: string
    renderProc: proc (params: Params): VNode

proc r(path: string, renderProc: proc (params: Params): VNode): Route = Route(path: path, renderProc: renderProc)

proc route(routes: openarray[Route]): VNode =
  # path is the current URL path
  let path = if state.location.pathname.len == 0: "/" else: $state.location.pathname
  let appPath = if config.appPath == "/": "" else: config.appPath

  for route in routes:
    let pattern = (appPath & route.path).parsePattern()
    var (matched, params) = pattern.match(path)

    for (k, v) in decodeQuery($state.location.search):
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
        navigateTo("/sub")

proc renderSub(params: Params): VNode =
  buildHtml(tdiv(id="home")):
    text "Hello Sub"
    button:
      text "Go back"
      proc onclick() =
        navigateTo("/")

proc render(): VNode =
  result = buildHtml(tdiv):
    # renderHeader()
    route([
      r("/", renderHome),
      r("/sub", renderSub),
    ])

window.onPopState = onPopState
setRenderer render

