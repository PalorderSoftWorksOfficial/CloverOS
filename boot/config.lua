defaultentry = "CloverOS"
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
local function findKernelApi(root)
	local candidates = {
		root .. "/boot/kernel_nullboot.lua",
		root .. "/kernel_nullboot.lua",
		"/kernel_nullboot.lua",
	}

	for _, path in ipairs(candidates) do
		if fs.exists(path) then
			return path
		end
	end

	return nil
end
local function findBios(root)
	local candidates = {
		root .. "/boot/kernel_nullboot.lua",
		root .. "/kernel_nullboot.lua",
		"/kernel_nullboot.lua",
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
local KERNELAPI = findKernelApi(ROOT)
local BIOS = findBios(ROOT)
menuentry("CloverOS")({
	description("Boot CloverOS."),
	chainloader(KERNEL),
})
menuentry("Load kernel API")({
	description([[
		Load the kernel without any booting
		]]),
	chainloader(KERNELAPI),
	cratos,
})
menuentry("ACI SETUP UTILITY (BIOS)")({
	description("Boot into BIOS"),
	chainloader(BIOS),
})
menuentry("CraftOS")({
	description("Boot into CraftOS."),
	craftos,
})
