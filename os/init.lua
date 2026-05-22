-- CloverOS userspace init — GNU/Linux on CC:Tweaked (kernel API)
local fs = kernel.fs

local function findRoot()
  if fs.exists("/CloverOS_OS.lua") and fs.exists("/boot/kernel.lua") then
    return "/"
  end
  for i = 0, 99 do
    local r = "/disk" .. (i == 0 and "" or tostring(i))
    if fs.exists(r .. "/CloverOS_OS.lua") and fs.exists(r .. "/boot/kernel.lua") then
      return r
    end
  end
  return "/"
end

local function loadModule(root, path, env)
  env = env or {}
  env.fs = fs
  env.kernel = kernel
  setmetatable(env, { __index = _G })
  local full = fs.combine(root, path)
  local h = fs.open(full, "r")
  if not h then
    error("missing module: " .. full)
  end
  local src = h.readAll()
  h.close()
  local chunk, err = load(src, "@" .. full, "t", env)
  if not chunk then
    error(err)
  end
  return chunk()
end

local ROOT = findRoot()
local rootfs = loadModule(ROOT, "os/rootfs.lua", {})
rootfs.setup(fs, ROOT, kernel)

local accountsMod = loadModule(ROOT, "os/accounts.lua", {})
local accounts = accountsMod.load(fs, ROOT)
local bootMod = loadModule(ROOT, "os/boot.lua", { term = kernel.term, colors = colors })
local shMod = loadModule(ROOT, "os/sh.lua", {})

local monitor = kernel.peripheral.find("monitor")

local function readInput(prompt, hidden)
  return kernel.input.line(prompt, hidden)
end

local Terminal = {}
function Terminal.clear()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  if monitor then
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
  end
  term.clear()
end
function Terminal.write(t)
  term.write(t)
end
function Terminal.print(...)
  print(...)
end
function Terminal.centerText(y, text, fg, bg)
  if fg then
    term.setTextColor(fg)
  end
  if bg then
    term.setBackgroundColor(bg)
  end
  kernel.ui.centerText(y, text)
  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)
end

local settingsLoaded = false
local editionSettings = {}
if settings then
  editionSettings.softinstall = settings.get("softinstall", false)
  editionSettings.autoLogin = settings.get("autoLogin", false)
  editionSettings.envType = settings.get("envType", "cct")
  settingsLoaded = true
end

local ctx = {
  root = ROOT,
  kernel = kernel,
  fs = fs,
  process = kernel.process,
  term = kernel.term,
  path = kernel.path,
  colors = colors,
  accounts = accounts,
  Terminal = Terminal,
  readInput = readInput,
  settingsLoaded = settingsLoaded,
  editionSettings = editionSettings,
  currentUser = nil,
}

bootMod.run(ctx)

if not (settingsLoaded and editionSettings.autoLogin) then
  accountsMod.login(ctx)
else
  ctx.currentUser = "root"
end

shMod.start(ctx)

local nativeTerm = kernel.term.native()
if nativeTerm and type(nativeTerm.setCursorBlink) == "function" then
  nativeTerm.setCursorBlink(true)
end
