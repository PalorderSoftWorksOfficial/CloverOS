-- CloverOS startup: locate the installation, then run the kernel loader.
-- This file is the CraftOS entrypoint; it must never be overwritten by the OS.

local function fail(message)
	printError("CloverOS startup: " .. tostring(message))
	printError("Reinstall with: install")
	error("CloverOS cannot start", 0)
end

local function findRoot()
	if fs.exists("/CloverOS_OS.lua") and fs.exists("/boot/kernel.lua") then
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

local root = findRoot()
if not root then
	fail("installation not found (looked in / and /disk*)")
end

local loader = fs.combine(root, "boot/loader.lua")
if not fs.exists(loader) then
	fail("boot/loader.lua is missing from " .. root)
end

local ok, err = pcall(dofile, loader, root)
if not ok then
	if err == "Terminated" then
		return
	end
	fail("boot failed: " .. tostring(err))
end
