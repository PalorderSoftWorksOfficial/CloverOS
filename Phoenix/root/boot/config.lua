rootDirectory = "/root"
defaultentry = "Phoenix"
timeout = 10
backgroundcolor = colors.black
selectcolor = colors.orange
titlecolor = colors.lightGray
bootArgs = "root=" .. rootDirectory

include("config.lua.d/*")
