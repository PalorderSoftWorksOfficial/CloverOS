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
	return "/"
end

local ROOT = findCloverRoot()
local KERNEL = ROOT == "/" and "/kernel.lua" or ROOT .. "/kernel.lua"

menuentry("CloverOS")({
	description("Boot CloverOS."),
	chainloader(KERNEL),
})

menuentry("CraftOS")({
	description("Boot into CraftOS."),
	craftos,
})
