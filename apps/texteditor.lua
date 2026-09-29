-- CloverOS Text Editor: open and save text files from the desktop.
-- deps injected by runtime/desktop.lua: window, paths, desktop
local M = {}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local paths = deps.paths
	local desktop = deps.desktop

	local function defaultFile()
		local home = "home/" .. (deps.users and deps.users:currentName() or "user")
		local note = fs.combine(home, "notes.txt")
		if not fs.exists(note) then
			return note
		end
		return "etc/motd.txt"
	end

	local state = {
		file = deps.args and deps.args[1] or defaultFile(),
		lines = {},
		dirty = false,
		status = "",
	}

	local function loadFile()
		state.lines = {}
		state.dirty = false
		local target = paths:osPath(state.file)
		local h = fs.open(target, "r")
		if not h then
			state.status = "cannot open " .. state.file
			return
		end
		for line in h.readAll():gmatch("([^\n]*)\n?") do
			state.lines[#state.lines + 1] = line
		end
		h.close()
		state.status = "opened " .. state.file
	end

	local function saveFile()
		local target = paths:osPath(state.file)
		fs.makeDir(fs.getDir(target))
		local h = fs.open(target, "w")
		if not h then
			state.status = "cannot write " .. state.file
			return
		end
		h.write(table.concat(state.lines, "\n"))
		h.close()
		state.dirty = false
		state.status = "saved " .. state.file
	end

	loadFile()

	local function visibleRows()
		return math.max(1, win.frame.h - 3)
	end

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			local rows = visibleRows()
			for i = 1, rows do
				local line = state.lines[i]
				if line then
					term.setCursorPos(2, i)
					term.write(("%3d " .. line):sub(1, win.frame.w - 3))
				end
			end
			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write(("%s%s"):format(state.file, state.dirty and " *" or ""))
			term.setCursorPos(2, win.frame.h - 2)
			term.write("ctrl+s save  ctrl+o open  F2 new line")
			term.setTextColor(colors.white)
			term.setCursorPos(2, win.frame.h)
			term.write(state.status)
		end,
		onMouse = function(w, ev)
			if ev[1] == "mouse_click" and ev[4] == win.frame.h then
				-- click the status row cycles to the next known file
				if state.file:find("notes.txt", 1, true) then
					state.file = "etc/motd.txt"
				else
					state.file = defaultFile()
				end
				loadFile()
			end
		end,
		onKey = function(w, key, ctrl)
			if key == keys.f2 or key == keys.enter then
				state.lines[#state.lines + 1] = ""
				state.dirty = true
			elseif key == keys.backspace then
				local last = state.lines[#state.lines]
				if last and #last > 0 then
					state.lines[#state.lines] = last:sub(1, -2)
					state.dirty = true
				end
			elseif key == keys.s and ctrl then
				saveFile()
			elseif key == keys.o and ctrl then
				loadFile()
			end
		end,
		onChar = function(w, ch)
			if ch == nil or ch == "" then
				return
			end
			if #state.lines == 0 then
				state.lines[1] = ""
			end
			state.lines[#state.lines] = state.lines[#state.lines] .. ch
			state.dirty = true
		end,
		onClose = function() end,
	}
end

return M
