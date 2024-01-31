import std/[dom, json, asyncjs, jsffi, math, jsconsole, enumerate, sugar, strformat, strutils, tables]
import karax/[karax, kajax, karaxdsl, vdom, vstyles]

import matter
import frontend/[utils, user, patterns]
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

var state = newState()

proc renderHome(params: Params): VNode =
  buildHtml(tdiv):
    text "Welcome to my grado project"

# proc renderSimulation(params: Params): VNode = 
#   buildHtml(tdiv):

const simulations = [
  (load: parabola.load, render: parabola.render), 
]

proc render(): VNode =
  result = buildHtml(tdiv):
    # renderHeader()
    state.location.route([
      r("/s/@id", proc(params: Params): VNode = 
        try:
          state.simulationIndex = params["id"].parseInt()
          if state.simulationIndex in simulations.low..simulations.high:
            simulations[state.simulationIndex].render(params)
          else:
            renderError404()
        except ValueError:
          renderError404()
      ),
      r("/", renderHome)
    ])

proc postRender() = 
  if not state.matterLoaded and state.simulationIndex in simulations.low..simulations.high:
    simulations[state.simulationIndex].load()
    state.matterLoaded = true

window.onPopState = proc(event: Event) =
  # This event is usually only called when the user moves back in history.
  # echo (old: state.location.href, new: window.location.href)
  document.title = state.prevTitle
  if state.location.href != window.location.href:
    state = newState() # Reload the state to remove stale data.
  else:
    state.location = window.location.deepCopy()

  redraw()

# window.onload = proc(event: Event) = loadMatter()

setRenderer render, clientPostRenderCallback = postRender

