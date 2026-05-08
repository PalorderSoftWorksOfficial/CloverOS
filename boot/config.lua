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

local function findKernel(root)
	local candidates = {
		root .. "/boot/kernel.lua",
		root .. "/kernel.lua",
		"/kernel.lua",
	}

	for _, path in ipairs(candidates) do
		if fs.exists(path) then
			return path
		end
	end

	return nil
end

local ROOT = findCloverRoot()
local KERNEL = findKernel(ROOT)

menuentry("CloverOS")({
	description("Boot CloverOS."),
	chainloader(KERNEL),
})

menuentry("CraftOS")({
	description("Boot into CraftOS."),
	craftos,
})