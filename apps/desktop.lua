-- CloverOS launcher app: opens the other applications from the desktop.
-- deps injected by runtime/desktop.lua: window, desktop, gui
local M = {}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local desktop = deps.desktop

	local apps = {
		{ label = "Terminal", id = "terminal" },
		{ label = "Files", id = "files" },
		{ label = "Settings", id = "settings" },
		{ label = "System Info", id = "sysinfo" },
	}

	local status = "choose an application"

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			for i, app in ipairs(apps) do
				local y = 2 + i
				term.setCursorPos(3, y)
				term.setBackgroundColor(colors.blue)
				term.setTextColor(colors.white)
				term.write(" " .. app.label .. " ")
				term.setBackgroundColor(colors.gray)
			end
			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write(status)
			term.setTextColor(colors.white)
		end,
		onMouse = function(w, ev)
			if ev[1] ~= "mouse_click" then
				return
			end
			local row = ev[4] - win.frame.position.y
			local idx = row - 2
			if apps[idx] then
				if desktop then
					desktop:openApp(apps[idx].id)
				end
				status = "opened " .. apps[idx].label
			end
		end,
		onGuiEvent = function(w, ge) end,
		onKey = function(w, key) end,
		onChar = function(w, ch) end,
		onClose = function() end,
	}
end

return M
