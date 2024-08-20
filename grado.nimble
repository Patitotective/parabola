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
  mkDir "dist/css"
  cpFile "public/css/style.css", "dist/css/style.css"
  cpFile "public/css/google-icons.css", "dist/css/google-icons.css"
  cpFile "public/css/google-icons.woff2", "dist/css/google-icons.woff2"
  cpDir "public/img", "dist/img"

  cpDir "public/js/matter-wrap", "dist/matter-wrap"
  cpDir "public/js/matter-js", "dist/matter-js"
  
  mkDir "dist/katex/contrib"
  cpDir "public/js/katex/fonts", "dist/katex/fonts"

  cpFile "public/js/katex/katex.min.js", "dist/katex/katex.min.js"
  cpFile "public/js/katex/katex.min.css", "dist/katex/katex.min.css"
  cpFile "public/js/katex/contrib/auto-render.min.js", "dist/katex/contrib/auto-render.min.js"

  writeFile "dist/index.html", readFile("public/karax.html") %
    {
      "title": config.title,
      "frontend": "./app.js",
      "style": "./css/style.css",
      "favicon": "./img/favicon.ico",
      "matterwrap": "./matter-wrap/matter-wrap.min.js",
      "matterjs": "./matter-js/matter.min.js",
      "katexcss": "./katex/katex.min.css",
      "katex": "./katex/katex.min.js",
      "katexauto": "./katex/contrib/auto-render.min.js",
      "googlecss": "./css/google-icons.css"
      # "timestamp": encodeUrl(CompileDate & CompileTime),
      # "ga": config.ga
    }.newStringTable()

task htmlpage, "Generates a single html page":
  htmljsTask()
  cssTask()
  makedistTask()

task rhtmlpage, "Generates a release version single html page":
  cssTask()
  exec "nim js -d:relativePath -d:release --out:dist/app.js src/frontend"

  makedistTask()
