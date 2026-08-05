defaultentry = "CraftOS"
timeout = 10
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
local KERNEL = pick(ROOT .. "/boot/kernel.lua", ROOT .. "/kernel.lua", "/boot/kernel.lua")
local KERNELAPI = pick(ROOT .. "/boot/kernel_nullboot.lua", ROOT .. "/kernel_nullboot.lua", "/boot/kernel_nullboot.lua")
local BIOS = pick(ROOT .. "/boot/bios.lua", ROOT .. "/bios.lua", "/boot/bios.lua")

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

if BIOS then
	menuentry("ACI SETUP UTILITY (BIOS)")({
		description("Boot into BIOS"),
		chainloader(BIOS),
	})
end

menuentry("CraftOS")({
	description("Boot into CraftOS."),
	craftos,
})