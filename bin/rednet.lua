-- rednet: talk to other CloverOS computers over rednet.
--
-- The inbox is filled by the system layer while a desktop session is running,
-- so `rednet inbox` in a text shell shows whatever the session captured.
local root = CLOVER_ROOT or fs.getDir(shell.getRunningProgram())
local ok, system = pcall(function()
	return dofile(fs.combine(root, "runtime/system.lua"))
end)
if not ok or type(system) ~= "table" then
	print("rednet: system layer unavailable")
	return
end

local sys = system.attach(root)
if not sys then
	print("rednet: cannot locate the CloverOS root")
	return
end

local net = sys.state.rednet
local action = select(1, ...)

local function usage()
	print("usage: rednet <status|open|close|send|inbox> [args]")
end

if action == nil or action == "status" then
	print("rednet:   " .. (net.present and "attached" or "not attached"))
	print("channels: " .. tostring(net.open) .. " open")
	print("sent:     " .. tostring(net.sent))
	print("received: " .. tostring(net.received))
	print("computer: " .. tostring(os.getComputerID()))
elseif action == "open" or action == "close" then
	local sideArg = select(2, ...)
	local side = tonumber(sideArg) or 1
	local done, err
	if action == "open" then
		done, err = sys:rednetOpen(side)
	else
		done, err = sys:rednetClose(side)
	end
	if not done then
		print("rednet: " .. tostring(err))
		return
	end
	-- each command is its own process, so the counters only mean anything
	-- if they are written back for the next one
	sys:save()
	print("rednet: channel " .. side .. " " .. action .. "ed")
elseif action == "send" then
	local message = select(2, ...)
	if not message or message == "" then
		print("usage: rednet send <message> [channel]")
		return
	end
	local sideArg = select(3, ...)
	local side = tonumber(sideArg) or 1
	local done, err = sys:rednetSend(message, side)
	if not done then
		print("rednet: " .. tostring(err))
		return
	end
	sys:save()
	print("rednet: sent on channel " .. side)
elseif action == "inbox" then
	local inbox = sys:inbox()
	if #inbox == 0 then
		print("rednet: inbox is empty")
		return
	end
	print(string.format("%-6s %-14s %s", "from", "received", "message"))
	for _, entry in ipairs(inbox) do
		print(string.format("%-6s %-14s %s", tostring(entry.from), tostring(entry.at), entry.message))
	end
	print("--- " .. #inbox .. " message(s); 'rednet inbox clear' to empty ---")
elseif action == "clear" then
	local dropped = sys:clearInbox()
	sys:save()
	print("rednet: cleared " .. dropped .. " message(s)")
else
	usage()
end
