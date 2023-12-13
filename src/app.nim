import std/[re, os]

import prologue, prologue/middlewares/[staticfile, utils]

from config import nil

const karaxHtml = readFile("public/karax.html") %
  {
    "title": config.title,
    # "timestamp": encodeUrl(CompileDate & CompileTime),
    # "ga": config.ga
  }.newStringTable()

proc home(ctx: Context) {.async.} =
  # resp ctx.
  resp htmlResponse karaxHtml

var app = newApp(
  settings = newSettings(port = Port config.port, appName = config.title, debug = true),
  middlewares = @[staticFileMiddleware("public"), debugRequestMiddleware(), debugResponseMiddleware()],
)
app.get("/", home)
app.run()

