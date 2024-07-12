import std/os
import sass

import config as _

proc buildCSS*(cssFilename = "style") =
  let publicLoc = "public"
  var includePaths: seq[string] = @[]
  # Check for a styles override.
  var hostname = config.hostname
  if not dirExists(hostname):
    hostname = "localhost.local"

  let dir = getCurrentDir() / hostname / "public"
  includePaths.add(dir / "css")
  createDir(publicLoc / "images")
  let logo = publicLoc / "images" / "logo.png"
  removeFile(logo)
  createSymlink(
    dir / "images" / "logo.png",
    logo
  )

  let cssLoc = publicLoc / "css"
  sass.compileFile(
    cssLoc / (cssFilename & ".sass"),
    cssLoc / (cssFilename & ".css"),
    includePaths=includePaths
  )

when isMainModule:
  buildCSS()
  echo("CSS Built successfully")