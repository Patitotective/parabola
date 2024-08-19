import std/strtabs
import src/config as _

# Package

version       = config.version
author        = "Patitotective"
description   = "A projectile motion simulator website (only html)"
license       = "MIT"
srcDir        = "src"
skipExt       = @["nim"]
bin           = @["app"]


# Dependencies

requires "nim >= 2.0.0"
requires "karax == 1.2.2"
requires "prologue == 0.6.4"
requires "sass == 0.2.0"
requires "kdl == 2.0.1"
requires "ni18n == 0.1.0"

task css, "Builds the CSS":
  exec "nimble c -r --mm:refc src/buildcss"

task frontendjs, "Compiles the frontend to JavaScript":
  exec "nim js --outdir:public/js src/frontend"

task frontend, "Compiles the frontend to JavaScript and builds the CSS":
  exec "nimble css"
  exec "nimble frontendjs"

task htmljs, "Generates single html page's JavaScript":
  exec "nim js -d:relativePath --out:dist/app.js src/frontend"

task makedist, "Creates the dist directory":
  mkDir "dist"

  cpFile "public/css/style.css", "dist/style.css"
  cpDir "public/img", "dist/img"

  cpDir "public/js/matter-wrap", "dist/matter-wrap"
  cpDir "public/js/matter-js", "dist/matter-js"
  
  mkDir "dist/mathjax/input"
  #mkDir "dist/mathjax/a11y"

  #cpFile "public/js/mathjax/a11y/explorer.js", "dist/mathjax/a11y/explorer.js"
  #cpFile "public/js/mathjax/a11y/semantic-enrich.js", "dist/mathjax/a11y/semantic-enrich.js"
  #cpFile "public/js/mathjax/a11y/sre.js", "dist/mathjax/a11y/sre.js"
  #cpFile "public/js/mathjax/a11y/complexity.js", "dist/mathjax/a11y/complexity.js"
  #cpFile "public/js/mathjax/a11y/assistive-mml.js", "dist/mathjax/a11y/assistive-mml.js"

  cpFile "public/js/mathjax/input/mml.js", "dist/mathjax/input/mml.js"
  cpFile "public/js/mathjax/tex-chtml.js", "dist/mathjax/tex-chtml.js"

  writeFile "dist/index.html", readFile("public/karax.html") %
    {
      "title": config.title,
      "frontend": "./app.js",
      "style": "./style.css",
      "favicon": "./img/favicon.ico",
      "mathjax": "./mathjax/tex-chtml.js",
      "matterwrap": "./matter-wrap/matter-wrap.min.js",
      "matterjs": "./matter-js/matter.min.js",
      # "timestamp": encodeUrl(CompileDate & CompileTime),
      # "ga": config.ga
    }.newStringTable()

task htmlpage, "Generates a single html page":
  cssTask()
  htmljsTask()
  makedistTask()

task rhtmlpage, "Generates a single html page":
  exec "nimble c -r -d:release --mm:refc src/buildcss"
  exec "nim js -d:relativePath -d:release --out:dist/app.js src/frontend"

  makedistTask()
