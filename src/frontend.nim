## This is the module that manipulates the frontend using karax

import std/[dom, json, asyncjs, jsffi, math, jsconsole, enumerate, sugar, strformat, strutils, tables]
import karax/[karax, kajax, karaxdsl, vdom, vstyles, i18n, jdict, languages]

# import matter
import frontend/[routes, utils, patterns]
from frontend/simulations/parabola import nil

type
  State = ref object
    prevTitle*: cstring # Title of the previous page when using navigateTo()
    location*: Location
    simulationIndex*: int # Current simulation index
    matterLoaded*: bool

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
  State(location: window.location.deepCopy(), prevTitle: document.title, simulationIndex: -1)

proc navigateTo(uri: cstring) =
  # Add uri to the history
  window.history.pushState(0, cstring"", uri)

  # Fire the popState event.
  dom.window.dispatchEvent(dom.newEvent("popstate"))

var state = newState()

# addTranslation(esCo, "s/0/")

proc renderHome(params: Params): VNode =
  buildHtml(tdiv):
    text "Welcome to my grado project"

# proc renderSimulation(params: Params): VNode =
#   buildHtml(tdiv):

const simulations = [
  (load: parabola.load, render: parabola.render),
]

proc render(): VNode =
  buildHtml(tdiv):
    # renderHeader()
    state.location.route([
      r("/s/@id", proc(params: Params): VNode =
        try:
          state.simulationIndex = params["id"].parseInt()
        except ValueError:
          return renderError404()

        if state.simulationIndex in simulations.low..simulations.high:
          simulations[state.simulationIndex].render()
        else:
          renderError404()
      ),
      r("/", renderHome)
    ])

proc postRender() =
  # Since matter needs to find the canvas element, if we load the simulation before karax has created the canvas element it won't work
  if not state.matterLoaded and state.simulationIndex in simulations.low..simulations.high:
    simulations[state.simulationIndex].load()
    state.matterLoaded = true

# This event is (usually only) called when the user moves back in history
# Here we fake the moving-back-in-history action so it doesn't actually reload the page
# Instead, it just refreshes the state and asks karax to redraw the page
window.onPopState = proc(event: Event) =
  # echo (old: state.location.href, new: window.location.href)
  document.title = state.prevTitle
  if state.location.href != window.location.href:
    state = newState() # Reload the state to remove stale data.
  else:
    state.location = window.location.deepCopy()

  redraw()

setRenderer render, clientPostRenderCallback = postRender

