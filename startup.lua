---@diagnostic disable: undefined-global
-- luacheck: globals fs shell
local function findCloverRoot()
  if fs.exists("/CloverOS_API.lua") and fs.exists("/boot/pxboot.lua") then
    return "/"
  end

  for i = 0, 99 do
    local root = "/disk" .. (i == 0 and "" or i)
    if fs.exists(root .. "/CloverOS_API.lua") and fs.exists(root .. "/boot/pxboot.lua") then
      return root
    end
  end

  return nil
end

local root = findCloverRoot()
if not root then
  error("CloverOS root not found. Ensure CloverOS is installed on a mounted disk.")
end

local bootloader = root .. "/boot/pxboot.lua"
if not fs.exists(bootloader) then
  error("Bootloader missing: " .. bootloader)
end

shell.run(bootloader)
