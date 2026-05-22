-- CloverOS GNU/Linux userspace for CC:Tweaked
-- Requires global `kernel` from boot/kernel.lua
if not kernel then
  error("CloverOS: kernel API not loaded. Boot via startup.lua -> boot/kernel.lua")
end

local fs = kernel.fs
local function findRoot()
  if fs.exists("/os/init.lua") then
    return "/"
  end
  for i = 0, 99 do
    local r = "/disk" .. (i == 0 and "" or tostring(i))
    if fs.exists(r .. "/os/init.lua") then
      return r
    end
  end
  return "/"
end

local root = findRoot()
local path = fs.combine(root, "os/init.lua")
local h = fs.open(path, "r")
if not h then
  error("CloverOS: os/init.lua not found at " .. path)
end
local src = h.readAll()
h.close()
local chunk, err = load(src, "@os/init.lua", "t", _ENV)
if not chunk then
  error("CloverOS init failed: " .. tostring(err))
end
local ok, runErr = pcall(chunk)
if not ok then
  error("CloverOS init: " .. tostring(runErr))
end
