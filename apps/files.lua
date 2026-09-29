-- CloverOS file manager: directory navigation, open, view, create, delete.
-- deps injected by runtime/desktop.lua: window, paths, session, desktop, gui
local M = {}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local paths = deps.paths

	local cwd = "/"
	local entries = {}
	local status = "ready"
	local selected = nil

	local function refresh()
		entries = {}
		status = cwd
		if fs.isDir(cwd) then
			for _, name in ipairs(fs.list(cwd)) do
				entries[#entries + 1] = {
					name = name,
					isDir = fs.isDir(fs.combine(cwd, name)),
				}
			end
			table.sort(entries, function(a, b)
				if a.isDir ~= b.isDir then
					return a.isDir
				end
				return a.name < b.name
			end)
		else
			status = "not a directory: " .. cwd
		end
	end

	local function absPath(name)
		return fs.combine(cwd, name)
	end

	local function listRows()
		local maxRows = win.frame.h - 5
		return maxRows
	end

	local function draw()
		term.setBackgroundColor(colors.gray)
		term.setTextColor(colors.white)
		term.clear()
		term.setCursorPos(2, 2)
		term.setTextColor(colors.yellow)
		term.write(status:sub(1, win.frame.w))
		term.setTextColor(colors.white)
		local maxRows = listRows()
		for i, entry in ipairs(entries) do
			if i > maxRows then
				break
			end
			term.setCursorPos(2, i + 2)
			term.setTextColor(entry.isDir and colors.lime or colors.white)
			local marker = entry.isDir and "[D] " or "[F] "
			local line = marker .. entry.name
			if entry == selected then
				term.setTextColor(colors.black)
				term.setBackgroundColor(colors.orange)
				term.write(line:sub(1, win.frame.w - 3))
				term.setBackgroundColor(colors.gray)
			else
				term.write(line:sub(1, win.frame.w - 3))
			end
		end
		term.setTextColor(colors.lightGray)
		term.setCursorPos(1, win.frame.h - 1)
		term.write("enter:open  bs:up  del:rm  c:new  click:select")
		term.setTextColor(colors.white)
	end

	local function openEntry(entry)
		if entry.isDir then
			cwd = absPath(entry.name)
			selected = nil
			refresh()
		else
			-- view text files inside the window (edit is interactive-only)
			local target = absPath(entry.name)
			local h = fs.open(target, "r")
			if h then
				local view = { "--- " .. entry.name .. " ---" }
				for i = 1, 6 do
					local line = h.readLine()
					if not line then
						break
					end
					view[#view + 1] = line
				end
				h.close()
				status = table.concat(view, " | "):sub(1, 60)
			end
		end
	end

	return {
		onDraw = draw,
		onGuiEvent = function(w, ge)
			if ge.type == "button_click" then
				status = "button: " .. tostring(ge.id)
			end
		end,
		onKey = function(w, key)
			if key == keys.backspace then
				cwd = fs.getDir(cwd) or "/"
				selected = nil
				refresh()
			elseif key == keys.delete then
				if selected and not selected.isDir then
					fs.delete(absPath(selected.name))
					refresh()
				elseif selected then
					status = "refusing to delete directory"
				end
			elseif key == keys.c then
				local name = "new_" .. tostring(os.epoch("utc") % 10000)
				local h = fs.open(absPath(name), "w")
				if h then
					h.write("")
					h.close()
				end
				refresh()
			elseif key == keys.enter and selected then
				openEntry(selected)
			end
		end,
		onChar = function(w, ch) end,
		onMouse = function(w, ev)
			if ev[1] ~= "mouse_click" then
				return
			end
			local row = ev[4] - win.frame.position.y - 2
			local col = ev[3] - win.frame.position.x
			if col < 2 or row < 1 or row > listRows() then
				return
			end
			local entry = entries[row]
			if not entry then
				return
			end
			selected = entry
			if ev[2] == 2 then
				openEntry(entry)
			end
		end,
		onClose = function() end,
	}
end

return M
