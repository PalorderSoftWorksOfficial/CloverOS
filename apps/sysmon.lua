-- CloverOS System Monitor: what this machine and session are doing.
-- deps injected by runtime/desktop.lua: window, kernel, paths, system
local M = {}

-- Format a byte count the way df would, in the biggest unit that fits.
function M.formatBytes(n)
	n = tonumber(n)
	if not n then
		return "?"
	end
	local units = { "B", "KB", "MB", "GB" }
	local i = 1
	while n >= 1024 and i < #units do
		n = n / 1024
		i = i + 1
	end
	if i == 1 then
		return string.format("%d %s", n, units[i])
	end
	return string.format("%.1f %s", n, units[i])
end

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local kernel = deps.kernel
	local system = deps.system

	local function lines()
		local out = {}
		local ok, version = pcall(dofile, fs.combine(CLOVER_ROOT or "/", "etc/version.lua"))
		local versionText = (ok and type(version) == "table") and version.version() or "?"
		out[#out + 1] = "CloverOS " .. versionText
		out[#out + 1] = "host:    " .. tostring(os.version())
		out[#out + 1] = "id:      " .. tostring(os.getComputerID())
		out[#out + 1] = "label:   " .. tostring(os.getComputerLabel() or "(none)")
		local clock = kernel and kernel.uptime and kernel.uptime() or os.clock()
		out[#out + 1] = "uptime:  " .. string.format("%.1f min", clock / 60)
		out[#out + 1] = "disk:    " .. M.formatBytes(fs.getFreeSpace("/")) .. " free"

		-- hardware, from the live system layer when the session has one
		if system and system.state then
			local state = system.state
			local net = state.network or {}
			out[#out + 1] = "net:     " .. tostring(net.interface) .. " "
				.. (net.connected and "online" or "offline")
			out[#out + 1] = "rednet:  " .. tostring(state.rednet and state.rednet.open or 0) .. " open"
			out[#out + 1] = "devices: " .. tostring(state.peripherals and #state.peripherals or 0)
		else
			out[#out + 1] = "net:     session has no hardware layer"
		end

		-- services, from the kernel service table
		if kernel and kernel.service and kernel.service.list then
			local running = 0
			local names = kernel.service.list()
			for _, name in ipairs(names) do
				if kernel.service.isRunning(name) then
					running = running + 1
				end
			end
			out[#out + 1] = "units:   " .. tostring(running) .. "/" .. tostring(#names) .. " active"
		end
		return out
	end

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(2, 2)
			term.setTextColor(colors.yellow)
			term.write("System Monitor")
			term.setTextColor(colors.white)
			local rows = lines()
			for i, line in ipairs(rows) do
				if i + 3 > win.frame.h - 3 then
					break
				end
				term.setCursorPos(2, i + 3)
				term.write(line:sub(1, win.frame.w - 3))
			end
			-- live tail of the journal, three lines worth
			if kernel and kernel.journal then
				local journal = kernel.journal("info")
				term.setTextColor(colors.lightGray)
				for i = 1, 3 do
					local line = journal[#journal - 3 + i]
					if line then
						term.setCursorPos(2, win.frame.h - 4 + i)
						term.write(("| " .. line):sub(1, win.frame.w - 3))
					end
				end
			end
			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write("R:refresh")
			term.setTextColor(colors.white)
		end,
		onKey = function() end,
		onChar = function() end,
		onClose = function() end,
	}
end

return M
