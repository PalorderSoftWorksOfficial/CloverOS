---@diagnostic disable: undefined-global
-- CloverOS startup — loads API and kernel (GNU/Linux userspace)
local function findCloverRoot()
  if fs.exists("/CloverOS_API.lua") and fs.exists("/boot/kernel.lua") then
    return "/"
  end
  for i = 0, 99 do
    local root = "/disk" .. (i == 0 and "" or i)
    if fs.exists(root .. "/CloverOS_API.lua") and fs.exists(root .. "/boot/kernel.lua") then
      return root
    end
  end
  return nil
end

local root = findCloverRoot()
if not root then
  error("CloverOS root not found. Install CloverOS on this computer's disk.")
end

local ok, api = pcall(dofile, root .. "/CloverOS_API.lua")
if ok and type(api) == "table" then
  if _G then
    rawset(_G, "CloverOS_API", api)
    rawset(_G, "CloverOS", api)
  end
  if _ENV and _ENV ~= _G then
    rawset(_ENV, "CloverOS_API", api)
    rawset(_ENV, "CloverOS", api)
  end
else
  error("Failed to load CloverOS_API: " .. tostring(api))
end

local kernelPath = root .. "/boot/kernel.lua"
if not fs.exists(kernelPath) then
  error("boot/kernel.lua not found")
end
shell.run(kernelPath)
