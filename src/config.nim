import std/os
import kdl, kdl/[decoder]

type
  Config* = object
    title*: string
    appPath*: string # Path where the app is: https://www.example.com/ or https://www.example.com/app
    port*: int
    hostname*: string

const configPath* {.define.} = currentSourcePath.parentDir() / "config.kdl"
const config* = configPath.parseKdlFile().decodeKdl(Config)
