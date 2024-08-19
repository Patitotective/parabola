import std/[options, sugar, re, os] # logging
import prologue, prologue/middlewares/[staticfile, utils]

import config as _

# addHandler newConsoleLogger(fmtStr = "")

proc getKarax(ctx: Context) {.async.} =
  resp htmlResponse readFile("public/karax.html") %
    {
      "title": config.title,
      "frontend": "/public/js/frontend.js",
      "style": "/public/css/style.css",
      "favicon": "/public/img/favicon.ico",
      "katexcss": "/public/js/katex/katex.min.css",
      "katex": "/public/js/katex/katex.min.js",
      "katexauto": "/public/js/katex/contrib/auto-render.min.js",
      "matterwrap": "/public/js/matter-wrap/matter-wrap.min.js",
      "matterjs": "/public/js/matter-js/matter.min.js",
      "googlecss": "/public/css/google-icons.css",
      # "timestamp": encodeUrl(CompileDate & CompileTime),
      # "ga": config.ga
    }.newStringTable()

var app = newApp(
  settings = newSettings(port = Port config.port, appName = config.title, debug = true),
  middlewares = @[staticFileMiddleware("public")]#, debugRequestMiddleware(), debugResponseMiddleware()],
)
app.get("/", getKarax)
app.run()

