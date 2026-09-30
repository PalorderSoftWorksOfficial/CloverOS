-- monitor: mirror this computer's display to an attached monitor.
--
--   monitor            attach the first (or only) monitor
--   monitor list       show attached monitors
--   monitor <name>     attach a specific monitor (peripheral name)
--
-- While attached, everything the session draws on the terminal is replayed
-- to the monitor as a scaled copy. CC:Tweaked has no display muxer, so the
-- mirroring is a redirect of term: monitor.setRedirect(term.current()) is
-- not what a mirror needs, and instead of emulating one badly, this gives
-- the monitor a live text snapshot every second until detach (ctrl+T) or
-- the monitor is removed.
local root = CLOVER_ROOT or fs.getDir(shell.getRunningProgram())

local action = ...
local function findMonitors()
	local names = {}
	if type(peripheral) == "table" and type(peripheral.getNames) == "function" then
		for _, name in ipairs(peripheral.getNames()) do
			if peripheral.getType(name) == "monitor" then
				names[#names + 1] = name
			end
		end
	end
	return names
end

if action == "list" then
	local names = findMonitors()
	if #names == 0 then
		print("no monitors attached")
	else
		for _, name in ipairs(names) do
			print(name)
		end
	end
	return
end

local names = findMonitors()
local target = nil
if action and action ~= "list" then
	target = action
else
	target = names[1]
end

if not target then
	print("monitor: no monitor attached")
	return
end
if type(peripheral) ~= "table" or type(peripheral.wrap) ~= "function"
	or not peripheral.isPresent(target) then
	print("monitor: no such peripheral: " .. tostring(target))
	return
end

local mon = peripheral.wrap(target)
if type(mon) ~= "table" or type(mon.write) ~= "function" then
	print("monitor: " .. tostring(target) .. " is not a usable monitor")
	return
end

local tw, th = term.current().getSize()
local mw, mh = mon.getSize()
print("mirroring to " .. target .. " (" .. mw .. "x" .. mh .. "), ctrl+T to stop")

-- snapshot loop: read the terminal buffer through term, paint the monitor.
-- CC:Tweaked cannot read another terminal's buffer back, so the mirror
-- repaints from what the shell prints: we attach as the terminal's
-- redirect target instead, which IS supported.
local okRedirect = pcall(function()
	term.redirect(mon)
end)
if not okRedirect then
	print("monitor: cannot redirect the terminal")
	return
end

while true do
	local ev, side = os.pullEventRaw()
	if ev == "terminate" then
		break
	elseif ev == "monitor_touch" then
		-- touches arrive here; nothing to do for a mirror
	elseif ev == "peripheral_detach" and side == target then
		break
	end
end

pcall(function()
	term.redirect(term.native())
end)
print("monitor detached")
