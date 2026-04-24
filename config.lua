-- CloverOS boot menu configuration
local function safeFindKernel(fileName)
  for i = 0, 99 do
    local d = "/disk" .. (i == 0 and "" or i)
    local p = d .. "/" .. fileName
    if fs.exists(p) then
      return p
    end
  end

  if fs.exists("/" .. fileName) then
    return "/" .. fileName
  end

  error("Kernel not found: " .. fileName)
end

local cloverKernel = safeFindKernel("boot/kernel.lua")

defaultentry = "CloverOS"
timeout = 5
backgroundcolor = colors.black
selectcolor = colors.orange
titlecolor = colors.lightGray

menuentry "CloverOS" {
  description "Boot CloverOS normally.",
  kernel(cloverKernel)
}

menuentry "CraftOS" {
  description "Boot into CraftOS.",
  craftos,
}

