import std/[re, os]

import prologue, prologue/middlewares/utils

from config import nil

# var
#   karaxHtml: string

# proc initialize() =
#   # randomize()

#   # config = loadConfig()
#   # if len(config.recaptchaSecretKey) > 0 and len(config.recaptchaSiteKey) > 0:
#   #   captcha = initReCaptcha(config.recaptchaSecretKey, config.recaptchaSiteKey)
#   # else:
#   #   doAssert config.isDev, "Recaptcha required for production!"
#   #   warn("No recaptcha secret key specified.")

#   # mailer = newMailer(config)

#   # db = open(connection=config.dbPath, user="", password="",
#   #             database="nimforum")
#   # isFTSAvailable = db.getAllRows(sql("SELECT name FROM sqlite_master WHERE " &
#   #     "type='table' AND name='post_fts'")).len == 1

#   # buildCSS(config)

#   # Read karax.html and set its properties.
#   karaxHtml = readFile("public/karax.html") %
#     {
#       "title": config.title,
#       # "timestamp": encodeUrl(CompileDate & CompileTime),
#       # "ga": config.ga
#     }.newStringTable()

# initialize()

# routes:
#   get re"/(.*)":
#     # Ignore requests that have a dot, like "not-existing-file.json"
#     cond request.matches[0].splitFile.ext == ""

#     {.cast(gcsafe).}:
#       resp karaxHtml

proc readKaraxHtml(): string =
  readFile("public/karax.html") %
    {
      "title": config.title,
      # "timestamp": encodeUrl(CompileDate & CompileTime),
      # "ga": config.ga
    }.newStringTable()

proc home(ctx: Context) {.async.} =
  # resp ctx.
  resp readKaraxHtml()

var app = newApp(
  settings = newSettings(port = config.port, appName = config.title),
  middlewares = @[debugRequestMiddleware(), debugResponseMiddleware()],
)
app.get("/", home)
waitFor app.run()

