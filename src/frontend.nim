## This is the module that manipulates the frontend using karax

import std/[dom, json, asyncjs, jsffi, math, jsconsole, enumerate, sugar, strformat, strutils, tables]
import karax/[karax, kajax, karaxdsl, vdom, vstyles, jdict, languages]

# import matter
import frontend/[routes, utils, patterns]
import frontend/simulations/[parabola, utils]

type
  State = ref object
    prevTitle*: cstring # Title of the previous page when using navigateTo()
    location*: Location
    matterLoaded*: bool
    parabola*: ParabolaState

proc deepCopy(l: Location): Location =
  Location(
    hash: l.hash,
    host: l.host,
    hostname: l.hostname,
    href: l.href,
    pathname: l.pathname,
    port: l.port,
    protocol: l.protocol,
    search: l.search,
    origin: l.origin,
  )

proc newState(): State =
  result = State(location: window.location.deepCopy(), prevTitle: document.title, 
    parabola: initParabolaState()
  )
  result.parabola.addEventListeners()

proc navigateTo(uri: cstring) =
  # Add uri to the history
  window.history.pushState(0, cstring"", uri)

  # Fire the popState event.
  dom.window.dispatchEvent(dom.newEvent("popstate"))

var state = newState()

# addTranslation(esCo, "s/0/")

proc render(): VNode =
  state.parabola.render()

proc postRender() =
  # Since matter needs to find the canvas element, if we load the simulation before karax has created the canvas element it won't work
  if not state.matterLoaded:
    # Load the simulation until MathJax is done loading
    if not MathJax.typesetPromise.isNil:
      state.parabola.load()
      state.matterLoaded = true
    else:
      discard setTimeout(postRender, 300)

# This event is (usually only) called when the user moves back in history
# Here we fake the moving-back-in-history action so it doesn't actually reload the page
# Instead, it just refreshes the state and asks karax to redraw the page
window.onPopState = proc(event: Event) =
  document.title = state.prevTitle
  if state.location.href != window.location.href:
    state = newState() # Reload the state to remove stale data.
  else:
    state.location = window.location.deepCopy()

  redraw()

setRenderer render, clientPostRenderCallback = postRender

