---@diagnostic disable: undefined-global
-- luacheck: globals fs shell
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
  error("CloverOS root not found. Ensure CloverOS is installed on a mounted disk.")
end

-- Ensure the CloverOS API is loaded into the global environment so
-- the kernel (and CloverOS_OS) can access it as a global.
local ok, api = pcall(dofile, root .. "/CloverOS_API.lua")
if ok and type(api) == "table" then
  -- Install into globals for compatibility with code that expects them.
  -- Use rawset to avoid diagnostics about injecting fields into _G/_ENV.
  if _G then
    rawset(_G, "CloverOS_API", api); rawset(_G, "CloverOS", api)
  end
  if _ENV and _ENV ~= _G then
    rawset(_ENV, "CloverOS_API", api); rawset(_ENV, "CloverOS", api)
  end
else
  -- If the API failed to load, surface a helpful error rather than
  -- letting the kernel run in a broken state.
  error("Failed to load CloverOS_API: " .. tostring(api))
end

shell.run(root .. "/boot/kernel.lua")
