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

task frontend, "Compiles the frontend to JavaScript":
  exec "nimble c -r --mm:refc src/buildcss"
  exec "nim js --outdir:public/js src/frontend"

