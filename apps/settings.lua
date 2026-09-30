-- CloverOS settings app: hostname, session info and appearance, persisted
-- via kernel.config and the per-user theme config.
-- deps injected by runtime/desktop.lua: window, kernel, session, desktop,
-- paths, theme, themeCfg, notify
local M = {}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local kernel = deps.kernel
	local session = deps.session
	local desktop = deps.desktop
	local paths = deps.paths
	local theme = deps.theme
	local themeCfg = deps.themeCfg
	local notify = deps.notify

	local cfg = { showClock = true }
	if kernel and kernel.config then
		cfg = kernel.config.loadOrCreate("settings", cfg)
		kernel.config.save("settings")
	end

	local status = "settings"
	local history = {}

	local function applyTheme(key, value)
		if themeCfg then
			themeCfg[key] = value
		end
		if desktop and desktop.saveTheme then
			desktop.saveTheme()
		end
		status = key .. ": " .. tostring(value)
	end

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(2, 2)
			term.setTextColor(colors.yellow)
			term.write("CloverOS Settings")
			term.setTextColor(colors.white)

			-- ---------- session ----------
			local label = os.getComputerLabel() or "(none)"
			term.setCursorPos(2, 4)
			term.write("hostname: " .. label)
			term.setCursorPos(2, 5)
			term.write("user:     " .. tostring(session and session.users:currentName() or "unknown"))
			term.setCursorPos(2, 6)
			term.write("storage:  " .. tostring(fs.getFreeSpace("/") or "?") .. " bytes free")
			term.setCursorPos(2, 7)
			term.write("clock:    " .. (cfg.showClock and "on" or "off"))

			-- ---------- appearance ----------
			local mode = (themeCfg and themeCfg.mode) or "dark"
			local accent = (themeCfg and themeCfg.accent) or "orange"
			local wallpaper = (themeCfg and themeCfg.wallpaper) or "aubergine"
			term.setTextColor(colors.yellow)
			term.setCursorPos(2, 9)
			term.write("Appearance")
			term.setTextColor(colors.white)
			term.setCursorPos(2, 10)
			term.write("style:     " .. mode .. "  (D to switch)")
			term.setCursorPos(2, 11)
			term.write("accent:    " .. accent .. "  (A to cycle)")
			term.setCursorPos(2, 12)
			term.write("wallpaper: " .. wallpaper:sub(1, win.frame.w - 15))

			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write("L:set host  C:clock  D:style  A:accent  K:logout")
			term.setTextColor(colors.white)

			term.setCursorPos(2, 14)
			term.setTextColor(colors.lime)
			term.write(status:sub(1, win.frame.w - 3))
			term.setTextColor(colors.white)
		end,
		onKey = function(w, key)
			if key == keys.c then
				cfg.showClock = not cfg.showClock
				if kernel and kernel.config then
					kernel.config.save("settings")
				end
				status = "clock " .. (cfg.showClock and "on" or "off")
			elseif key == keys.d and themeCfg then
				applyTheme("mode", themeCfg.mode == "dark" and "light" or "dark")
			elseif key == keys.a and theme and themeCfg then
				applyTheme("accent", theme.nextAccent(themeCfg.accent))
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
