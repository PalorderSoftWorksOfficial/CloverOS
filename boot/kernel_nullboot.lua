-- Legacy entry: run the main CloverOS kernel
local function findKernel()
  if fs.exists("/boot/kernel.lua") then
    return "/boot/kernel.lua"
  end
  for i = 0, 99 do
    local r = "/disk" .. (i == 0 and "" or tostring(i))
    local p = r .. "/boot/kernel.lua"
    if fs.exists(p) then
      return p
    end
  end
  return nil
end

local p = findKernel()
if not p then
  error("boot/kernel.lua not found")
end
dofile(p)
