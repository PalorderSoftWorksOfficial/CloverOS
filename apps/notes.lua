-- CloverOS Notes: a per-user scratch pad that saves itself.
-- deps injected by runtime/desktop.lua: window, paths, users
local M = {}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local paths = deps.paths
	local users = deps.users

	local name = users and users.currentName and users:currentName() or nil
	local file = paths:join("home", name or "", ".notes.txt")

	local text = ""
	local status = "ready"
	local dirty = false

	local function load()
		if fs.exists(file) then
			local handle = fs.open(file, "r")
			if handle then
				text = handle.readAll() or ""
				handle.close()
				status = "loaded"
			end
		else
			status = "new notes"
		end
	end

	local function save()
		fs.makeDir(fs.getDir(file))
		local handle = fs.open(file, "w")
		if not handle then
			status = "cannot save"
			return
		end
		handle.write(text)
		handle.close()
		dirty = false
		status = "saved"
	end

	load()

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(2, 2)
			term.setTextColor(colors.yellow)
			term.write("Notes  " .. paths:displayPath(file):match("[^/]+$"))
			term.setTextColor(colors.white)
			-- show the text wrapped to the window, as many lines as fit
			local width = win.frame.w - 3
			local row = 4
			for _, paragraph in ipairs({ text }) do
				local line = paragraph
				while #line > 0 and row < win.frame.h - 2 do
					term.setCursorPos(2, row)
					term.write(line:sub(1, width))
					line = line:sub(width + 1)
					row = row + 1
				end
			end
			term.setTextColor((dirty and colors.orange) or colors.lime)
			term.setCursorPos(2, win.frame.h - 2)
			term.write(status)
			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write("ctrl+s: save  (typed text appends)")
			term.setTextColor(colors.white)
		end,
		onKey = function(_w, key)
			if key == keys.s and keys.holdCtrl then
				save()
			elseif key == keys.backspace then
				text = text:sub(1, -2)
				dirty = true
			elseif key == keys.enter then
				text = text .. "\n"
				dirty = true
			end
		end,
		onChar = function(_w, ch)
			if ch == "\19" then -- ctrl+s arrives as a char on some hosts
				save()
				return
			end
			text = text .. ch
			dirty = true
		end,
		onClose = function()
			if dirty then
				save()
			end
		end,
	}
end

return M
