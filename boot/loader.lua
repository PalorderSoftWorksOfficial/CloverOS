local CLOVER_ROOT = ...
CLOVER_ROOT = fs.combine(CLOVER_ROOT or "/", "")

_G.CLOVER_ROOT = CLOVER_ROOT

local function fail(message)
	printError("CloverOS boot failed: " .. tostring(message))
	printError("Press ctrl+T to restart, or reinstall with: install")
	while true do
		local _, ev = os.pullEventRaw()
		-- only an explicit interrupt reboots; typed keys must not loop the boot
		if ev == "terminate" then
			os.reboot()
		end
	end
end

local function findRoot()
	if fs.exists(fs.combine("/", "CloverOS_OS.lua")) and fs.exists(fs.combine("/", "boot/kernel.lua")) then
		return "/"
	end
	for i = 0, 99 do
		local root = "/disk" .. (i == 0 and "" or i)
		if fs.exists(fs.combine(root, "CloverOS_OS.lua")) and fs.exists(fs.combine(root, "boot/kernel.lua")) then
			return root
		end
	end
	return nil
end

local kernelPath = fs.combine(CLOVER_ROOT, "boot/kernel.lua")
if not fs.exists(kernelPath) then
	fail("kernel not found at " .. kernelPath)
end

local kernelModule = dofile(kernelPath)
if not kernelModule then
	fail("kernel failed to load: " .. tostring(err))
end

if type(kernelModule) ~= "table" then
	fail("kernel did not initialize (got " .. type(kernelModule) .. ")")
end

_G.kernel = kernelModule
kernelModule.boot()

local osEntry = fs.combine(CLOVER_ROOT, "CloverOS_OS.lua")
if not fs.exists(osEntry) then
	fail("runtime entry " .. osEntry .. " is missing")
end

local ok2, err2 = pcall(dofile, osEntry)
if not ok2 then
	if err2 == "Terminated" then
		return
	end
	fail("runtime failed: " .. tostring(err2))
end
