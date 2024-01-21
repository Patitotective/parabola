import std/[logging, options, sugar, re, os]

import prologue, prologue/middlewares/[staticfile, utils]
import norm/[model, sqlite]

import types
from config import nil

addHandler newConsoleLogger(fmtStr = "")

var dbConn = open(":memory:", "", "", "")
dbConn.createTables(newLink())

var
  user = newUser("Cristobal Riaga", "@Patitotective", "https://avatars.githubusercontent.com/u/79225325?v=4", "I really like the Nim programming language.")
  twitterLink = newLink("https://twitter.com/Patitotective", "fa-brands fa-x-twitter", "Twitter", user)
  githubLink = newLink("https://github.com/Patitotective", "fa-brands fa-github-alt", "GitHub", user)

dbConn.insert user
dbConn.insert twitterLink
dbConn.insert githubLink

proc getUser(ctx: Context) {.async.} =
  let id = ctx.getPathParams("id", 0)

  var links = @[newLink()]
  dbConn.select(links, "User.id = ?", $id)

  var user = newUser()
  dbConn.select(user, "id = ?", $id)

  var json = %* user
  json["links"] = %* links

  resp jsonResponse json

proc getKarax(ctx: Context) {.async.} =
  resp htmlResponse readFile("public/karax.html") %
    {
      "title": config.title,
      # "timestamp": encodeUrl(CompileDate & CompileTime),
      # "ga": config.ga
    }.newStringTable()

proc getAuthConfig(ctx: Context) {.async.} =
  resp jsonResponse parseJson(readFile("auth_config.json"))

var app = newApp(
  settings = newSettings(port = Port config.port, appName = config.title, debug = true),
  middlewares = @[staticFileMiddleware("public"), debugRequestMiddleware(), debugResponseMiddleware()],
)
app.get("/auth_config.json", getAuthConfig)
app.get("/api/u/{id}", getUser)
app.get("/*$", getKarax)
app.run()

