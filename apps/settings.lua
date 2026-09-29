-- CloverOS settings app: hostname and session info, persisted via kernel.config.
-- deps injected by runtime/desktop.lua: window, kernel, session, desktop
local M = {}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local kernel = deps.kernel
	local session = deps.session
	local desktop = deps.desktop

	local cfg = { showClock = true }
	if kernel and kernel.config then
		cfg = kernel.config.loadOrCreate("settings", cfg)
		kernel.config.save("settings")
	end

	local status = "settings"
	local history = {}

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(2, 2)
			term.setTextColor(colors.yellow)
			term.write("CloverOS Settings")
			term.setTextColor(colors.white)

			local label = os.getComputerLabel() or "(none)"
			term.setCursorPos(2, 4)
			term.write("hostname: " .. label)
			term.setCursorPos(2, 5)
			term.write("user:     " .. tostring(session and session.users:currentName() or "unknown"))
			term.setCursorPos(2, 6)
			term.write("storage:  " .. tostring(fs.getFreeSpace("/") or "?") .. " bytes free")
			term.setCursorPos(2, 7)
			term.write("clock:    " .. (cfg.showClock and "on" or "off"))

			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write("L:set host  C:clock  K:logout")
			term.setTextColor(colors.white)

			term.setCursorPos(2, 9)
			term.setTextColor(colors.lime)
			term.write(status:sub(1, win.frame.w - 3))
			term.setTextColor(colors.white)
		end,			onKey = function(w, key)
				if key == keys.c then
					cfg.showClock = not cfg.showClock
					if kernel and kernel.config then
						kernel.config.save("settings")
					end
					status = "clock " .. (cfg.showClock and "on" or "off")
				elseif key == keys.k then
					if desktop then
						desktop.requestLogout = true
					end
				end
			end,
		onChar = function(w, ch) end,
		onClose = function() end,
	}
end

return M
