local CLOVER_ROOT = ...
CLOVER_ROOT = fs.combine(CLOVER_ROOT or "/", "")

_G.CLOVER_ROOT = CLOVER_ROOT

-- ---------- boot menu ----------
-- A GRUB-style choice before the kernel comes up: normal, text mode, or
-- safe mode (text, no init units). It must never trap a booting machine:
-- every failure path boots normally after the timeout, and a corrupted
-- display cannot stop the loader.

_G.CLOVER_BOOT_MODE = "normal"

local MODES = {
	{ key = "1", id = "normal", label = "CloverOS (graphical desktop)" },
	{ key = "2", id = "text", label = "CloverOS (text mode)" },
	{ key = "3", id = "safe", label = "CloverOS (safe mode: text, no services)" },
}

local function drawMenu()
	term.clear()
	term.setCursorPos(1, 1)
	term.setTextColor(colors.yellow)
	term.write("CloverOS boot menu")
	term.setTextColor(colors.white)
	for i, mode in ipairs(MODES) do
		term.setCursorPos(1, i + 2)
		term.write(mode.key .. ") " .. mode.label)
	end
	term.setCursorPos(1, #MODES + 4)
	term.setTextColor(colors.lightGray)
	term.write("Press 1-3 (default 1 in 3s)...")
	term.setTextColor(colors.white)
end

local function bootMenu()
	local ok = pcall(function()
		drawMenu()
		local keyNames = { "one", "two", "three" }
		local deadline = os.clock() + 3
		while os.clock() < deadline do
			local ev, param = os.pullEventRaw()
			if ev == "key" then
				for i, mode in ipairs(MODES) do
					if keys[keyNames[i]] ~= nil and param == keys[keyNames[i]] then
						_G.CLOVER_BOOT_MODE = mode.id
						return
					end
				end
			elseif ev == "char" then
				for _, mode in ipairs(MODES) do
					if param == mode.key then
						_G.CLOVER_BOOT_MODE = mode.id
						return
					end
				end
			elseif ev == "timer" then
				-- deadline checked by the loop condition
			end
		end
	end)
	-- the menu is best-effort: on any failure boot normally
	if not ok then
		_G.CLOVER_BOOT_MODE = "normal"
	end
end

if type(term) == "table" and type(term.write) == "function"
	and type(os) == "table" and type(os.clock) == "function"
	and fs.exists(fs.combine(CLOVER_ROOT, "etc/clover/boot-menu")) then
	-- The menu is opt-in (systemctl boot-menu on) because it must own the
	-- first seconds of input to work, and a machine that boots into a
	-- scripted or headless setup would have its keystrokes eaten.
	bootMenu()
end

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

if _G.CLOVER_BOOT_MODE == "safe" then
	kernelModule.warn("safe mode: skipping session units")
end

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
