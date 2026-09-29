-- CloverOS system info app: real data only, no fake hardware readouts.
-- deps injected by runtime/desktop.lua: window, kernel, paths
local M = {}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local kernel = deps.kernel

	local function buildLines()
		local version = "unknown"
		pcall(function()
			version = dofile(fs.combine(CLOVER_ROOT, "etc/version.lua")).version()
		end)
		local peripherals = {}
		if peripheral then
			for _, name in ipairs(peripheral.getNames()) do
				peripherals[#peripherals + 1] = name .. ":" .. peripheral.getType(name)
			end
		end
		local lines = {
			"CloverOS " .. version,
			"kernel:  " .. (kernel and kernel.version() or "unknown"),
			"host:    " .. os.version(),
			"comp id: " .. os.getComputerID(),
			"label:   " .. tostring(os.getComputerLabel() or "(none)"),
			"uptime:  " .. string.format("%.1f min", (kernel and kernel.uptime() or os.clock()) / 60),
			"disk:    " .. tostring(fs.getFreeSpace("/")) .. " bytes free",
			"http:    " .. (http and "enabled" or "disabled"),
			"perms:   " .. (#peripherals > 0 and table.concat(peripherals, ", ") or "none"),
		}
		return lines
	end

	local lines = buildLines()

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			for i, line in ipairs(lines) do
				if i + 1 > win.frame.h - 1 then
					break
				end
				term.setCursorPos(2, i + 1)
				term.write(line:sub(1, win.frame.w - 3))
			end
			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write("R:refresh")
			term.setTextColor(colors.white)
		end,
		onKey = function(w, key)
			if key == keys.r then
				lines = buildLines()
			end
		end,
		onChar = function(w, ch) end,
		onClose = function() end,
	}
end

return M
