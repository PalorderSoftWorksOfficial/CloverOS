defaultentry = "CloverOS Ubuntu"
timeout = 3
backgroundcolor = colors.black
selectcolor = colors.orange
titlecolor = colors.lightGray

local function findCloverRoot()
	if fs.exists("/CloverOS_OS.lua") and fs.exists("/boot/kernel.lua") then
		return "/"
	end

	for i = 0, 99 do
		local root = "/disk" .. (i == 0 and "" or i)
		if fs.exists(fs.combine(root, "CloverOS_OS.lua")) and fs.exists(fs.combine(root, "boot/kernel.lua")) then
			return root
		end
	end

	return "/"
end

local function pick(...)
	for i = 1, select("#", ...) do
		local path = select(i, ...)
		if path and fs.exists(path) then
			return path
		end
	end
	return nil
end

local ROOT = findCloverRoot()
local KERNEL = pick(fs.combine(ROOT, "boot/kernel.lua"), "/boot/kernel.lua")
local KERNELAPI = pick(ROOT .. "/boot/kernel_nullboot.lua", "/boot/kernel_nullboot.lua")

if KERNEL then
	menuentry("CloverOS Ubuntu")({
		description("Boot CloverOS."),
		chainloader(KERNEL),
	})
else
	defaultentry = "CraftOS"
end

if KERNELAPI then
	menuentry("Load kernel API")({
		description([[Load the kernel without booting.]]),
		chainloader(KERNELAPI),
	})
end

menuentry("CraftOS")({
	description("Boot into CraftOS."),
	craftos,
})