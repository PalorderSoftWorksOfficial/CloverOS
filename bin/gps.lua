-- gps: where this computer thinks it is.
--
-- CC:Tweaked's GPS is a peripheral that has to be opened before it produces
-- a position, so this can toggle it the way a real tool would.
local root = CLOVER_ROOT or fs.getDir(shell.getRunningProgram())
local ok, system = pcall(function()
	return dofile(fs.combine(root, "runtime/system.lua"))
end)
if not ok or type(system) ~= "table" then
	print("gps: system layer unavailable")
	return
end

local sys = system.attach(root)
if not sys then
	print("gps: cannot locate the CloverOS root")
	return
end

local gps = sys.state.gps
local action = ...

local function report()
	print("gps:    " .. (gps.present and "attached" or "not attached"))
	if not gps.present then
		return
	end
	print("state:  " .. (gps.open and "open" or "closed"))
	if gps.lat ~= nil and gps.lon ~= nil then
		print(string.format("fix:    %.6f, %.6f", gps.lat, gps.lon))
		if gps.altitude then
			print(string.format("alt:    %.1f", gps.altitude))
		end
	else
		print("fix:    none yet")
	end
end

if action == "open" or action == "close" then
	if not gps.present then
		print("gps: no GPS attached")
		return
	end
	local p = type(peripheral) == "table" and type(peripheral.find) == "function"
		and peripheral.find("gps") or nil
	if not p or type(p[action]) ~= "function" then
		print("gps: " .. action .. " is not supported here")
		return
	end
	local result = p[action](p)
	if result == false then
		print("gps: " .. action .. " failed")
		return
	end
	print("gps: " .. action .. " succeeded")
	return
elseif action ~= nil and action ~= "status" then
	print("usage: gps [status|open|close]")
	return
end

report()
