-- net: report the network interface CloverOS can see.
--
-- On CC:Tweaked "the network" is whatever peripheral happens to be attached,
-- so this reads the same state the panel shows rather than guessing from the
-- presence of an http API.
local root = CLOVER_ROOT or fs.getDir(shell.getRunningProgram())
local ok, system = pcall(function()
	return dofile(fs.combine(root, "runtime/system.lua"))
end)

if not ok or type(system) ~= "table" then
	print("net: system layer unavailable")
	return
end

local sys = system.attach(root)
if not sys then
	print("net: cannot locate the CloverOS root")
	return
end

local action = ...
local net = sys:network()

local function online()
	return net.connected and "online" or "offline"
end

if action == "scan" or action == nil or action == "status" then
	print("interface: " .. tostring(net.interface))
	print("status:    " .. online())
	if net.signal then
		print("signal:    " .. tostring(net.signal) .. "/4")
	end
	print("http:      " .. (type(http) == "table" and "available" or "unavailable"))
	if #sys.state.peripherals == 0 then
		print("peripherals: none")
	else
		print("peripherals: " .. #sys.state.peripherals)
		for _, entry in ipairs(sys.state.peripherals) do
			print("  " .. entry.name .. " (" .. entry.type .. ")")
		end
	end
elseif action == "down" or action == "up" then
	if net.interface == "none" then
		print("net: no network peripheral attached")
		return
	end
	local p = type(peripheral) == "table" and type(peripheral.find) == "function"
		and peripheral.find(net.interface) or nil
	if not p or type(p.open) ~= "function" then
		print("net: " .. tostring(net.interface) .. " cannot be opened here")
		return
	end
	local result
	if action == "up" then
		result = p.open()
	else
		result = p.close()
	end
	if result == false then
		print("net: " .. action .. " failed")
		return
	end
	sys:scan()
	print("net: " .. net.interface .. " is now " .. sys:network().state)
else
	print("usage: net [status|scan|up|down]")
end
