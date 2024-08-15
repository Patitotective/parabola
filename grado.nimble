# Package

version       = "0.1.0"
author        = "Patitotective"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
skipExt       = @["nim"]
bin           = @["app"]


# Dependencies

requires "nim >= 2.0.0"
requires "karax >= 1.2.2"
requires "prologue >= 0.6.4"
requires "sass >= 0.2.0"
requires "kdl >= 2.0.1"

task css, "Builds the CSS":
  exec "nimble c -r --mm:refc src/buildcss"

task frontendjs, "Compiles the frontend to JavaScript":
  exec "nim js --outdir:public/js src/frontend"

task frontend, "Compiles the frontend to JavaScript and builds the CSS":
  exec "nimble css"
  exec "nim frontendjs"

import std/strtabs
import src/config as _

task htmlpage, "Generates a single html page":
  exec "nimble css"
  exec "nim js -d:relativePath --out:dist/app.js src/frontend"

  mkDir "dist"
  cpFile "public/css/style.css", "dist/style.css"
  cpDir "public/img", "dist/img"

  writeFile "dist/index.html", readFile("public/karax.html") %
    {
      "title": config.title,
      "frontend": "./app.js",
      "style": "./style.css",
      "favicon": "./img/favicon.ico"
      # "timestamp": encodeUrl(CompileDate & CompileTime),
      # "ga": config.ga
    }.newStringTable()
