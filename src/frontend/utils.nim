import karax/[karaxdsl, vdom]

proc renderError404*(): VNode =
  buildHtml(tdiv):
    text "Couldn't find the page you were looking for"
    text "Error 404"

