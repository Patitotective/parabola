import std/[tables, json]
import karax/[kajax, karaxdsl, vdom]

import utils, ../types

type
  State = enum
    None, Sent, Received
  # UserView* = object

var state = None
var user: User
var links: seq[Link]

proc render(links: seq[Link]): VNode =
  buildHtml():
    ul():
      for l in links:
        li():
          a(href = cstring l.link, class = "link"):
            italic(class = cstring l.icon)
            text l.text

proc render(user: User, links: seq[Link]): VNode =
  buildHtml(tdiv(class = "wrap")):
    tdiv(class = "profile"):
      img(src = cstring user.logo, class = "photo")
      span(class = "profile_name", text user.name)
      span(class = "at", text user.username)

    tdiv(class = "links"):
      render(links)
      tdiv(class = "card"):
        h3(text "About Me")
        p(text user.about)

proc onResponse(status: int, response: cstring) =
  let j = parseJson($response)
  links = j["links"].to(seq[Link])
  user = j.to(User)
  state = Received

proc renderUser*(params: Table[string, string]): VNode =
  if "id" notin params:
    return renderError404()

  case state
  of None:
    ajaxGet(cstring("/api/u/" & params["id"]), [], onResponse)
    state = Sent
    buildHtml(span(text "Loading"))
  of Sent:
    buildHtml(span(text "Loading"))
  of Received:
    render(user, links)

