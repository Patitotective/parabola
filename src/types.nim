import norm/model

type
  Link* = ref object of Model
    link*, icon*, text*: string
    user*: User

  User* = ref object of Model
    name*: string # Display name
    username*: string # @username
    logo*: string # URL to the logo image
    about*: string

proc newUser*(name, username, logo, about = ""): User =
  User(name: name, username: username, logo: logo, about: about)

proc newLink*(link, icon, text = "", user = newUser()): Link =
  Link(link: link, icon: icon, text: text, user: user)


