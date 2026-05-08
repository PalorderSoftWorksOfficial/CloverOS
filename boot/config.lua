defaultentry = "CloverOS"
timeout = 5
backgroundcolor = colors.black
selectcolor = colors.orange
titlecolor = colors.lightGray
local function findCloverRoot()
	if fs.exists("/CloverOS_OS.lua") and fs.exists("/CloverOS_API.lua") then
		return "/"
	end

	for i = 0, 99 do
		local root = "/disk" .. (i == 0 and "" or i)
		if fs.exists(root .. "/CloverOS_OS.lua") and fs.exists(root .. "/CloverOS_API.lua") then
			return root
		end
	end

	return nil
end

local function joinPath(base, child)
	if base == "/" then
		return "/" .. child
	end
	return base .. "/" .. child
end

local ROOT = findCloverRoot()
if not ROOT then
	error("CloverOS root not found")
end

local KERNEL = joinPath(ROOT, "boot/kernel.lua")

if not fs.exists(KERNEL) then
	error("Kernel not found: " .. KERNEL)
end
menuentry("CloverOS")({
	description("Boot CloverOS."),
	chainloader(KERNEL),
})

menuentry("CraftOS")({
	description("Boot into CraftOS."),
	craftos,
})
