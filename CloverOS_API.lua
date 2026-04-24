-- CloverOS API module
-- Provides basic OS metadata, installer support, and a small mirrored terminal API.
---@diagnostic disable: undefined-global
-- luacheck: globals fs shell term colors peripheral read write os

local module = {}
local fs = fs
local shell = shell
local term = term
local colors = colors
local peripheral = peripheral
local read = read
local write = write
local monitor = peripheral.find("monitor")

local function findRoot()
  if fs.exists("/CloverOS_API.lua") and fs.exists("/CloverOS_OS.lua") then
    return "/"
  end

  for i = 0, 99 do
    local root = "/disk" .. (i == 0 and "" or i)
    if fs.exists(root .. "/CloverOS_API.lua") and fs.exists(root .. "/CloverOS_OS.lua") then
      return root
    end
  end

  return nil
end

local function pathCombine(...)
  local parts = { ... }
  local path = parts[1] or ""
  for i = 2, #parts do
    local part = parts[i]
    if string.sub(part, 1, 1) == "/" then
      path = part
    else
      path = fs.combine(path, part)
    end
  end
  return path
end

local ROOT = findRoot()

local function loadFilesystemModule()
  if not ROOT then
    return nil
  end

  local fsPath = pathCombine(ROOT, "etc", "filesystem", "main.lua")
  if not fs.exists(fsPath) then
    return nil
  end

  local ok, result = pcall(dofile, fsPath)
  if ok and type(result) == "table" then
    return result
  end
  return nil
end

local function writeToMirrors(text)
  write(text)
  if monitor then
    monitor.write(text)
  end
end

local function clearMirrors()
  term.clear()
  term.setCursorPos(1, 1)
  if monitor then
    monitor.clear()
    monitor.setCursorPos(1, 1)
  end
end

local function setCursorMirrors(x, y)
  term.setCursorPos(x, y)
  if monitor then
    monitor.setCursorPos(x, y)
  end
end

local function readMirrored(hidden)
  if hidden then
    return read("*")
  end
  return read()
end

local GDI = {}

function GDI.setColor(color)
  term.setTextColor(color)
  if monitor then
    monitor.setTextColor(color)
  end
end

function GDI.setBGColor(color)
  term.setBackgroundColor(color)
  if monitor then
    monitor.setBackgroundColor(color)
  end
end

function GDI.setCursor(x, y)
  setCursorMirrors(x, y)
end

function GDI.clear(bg)
  if bg then
    GDI.setBGColor(bg)
  end
  clearMirrors()
end

function GDI.text(x, y, text, fg, bg)
  if fg then
    GDI.setColor(fg)
  end
  if bg then
    GDI.setBGColor(bg)
  end
  GDI.setCursor(x, y)
  writeToMirrors(text)
end

function GDI.rect(x, y, w, h, fg, bg)
  for row = 0, h - 1 do
    GDI.text(x, y + row, string.rep(" ", w), fg, bg)
  end
end

function GDI.box(x, y, w, h, title, fg, bg)
  GDI.rect(x, y, w, h, fg, bg)
  if w > 1 and h > 1 then
    GDI.text(x, y, "+" .. string.rep("-", math.max(0, w - 2)) .. "+", fg, bg)
    for row = 1, h - 2 do
      GDI.text(x, y + row, "|" .. string.rep(" ", math.max(0, w - 2)) .. "|", fg, bg)
    end
    GDI.text(x, y + h - 1, "+" .. string.rep("-", math.max(0, w - 2)) .. "+", fg, bg)
    if title then
      GDI.text(x + 2, y, title, colors.cyan, bg)
    end
  end
end

function module.version()
  return "CloverOS v1.0.0"
end

function module.author()
  return "CloverOS Team"
end

function module.runInstaller()
  shell.run("wget", "run", "https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua")
end

function module.findRoot()
  return ROOT
end

function module.getMonitor()
  return monitor
end

module.GDI = GDI
module.filesystem = loadFilesystemModule()

return module
