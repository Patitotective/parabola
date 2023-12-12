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
# requires "jester >= 0.4.3"
requires "prologue >= 0.6.4"

task frontend, "Compiles the frontend to JavaScript":
  exec "nim js --outdir:public/js src/frontend"

# task backend, "Compiles & runs the backend":
  # exec "nim c src/webweb"


