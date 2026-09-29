-- CloverOS Software: the graphical front end to the apt package manager.
-- Browse and search the catalog, then install or remove packages.
-- deps injected by runtime/desktop.lua: window, packages, kernel
local M = {}

local CATEGORIES = {
	{ id = "all", title = "All" },
	{ id = "installed", title = "Installed" },
	{ id = "available", title = "Available" },
}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local packages = deps.packages

	local state = {
		category = "all",
		query = "",
		rows = {},
		selected = 1,
		status = "",
		offset = 0,
	}

	local function listPackages()
		local names = packages:catalogNames()
		table.sort(names)
		local rows = {}
		for _, name in ipairs(names) do
			local installed = packages:isInstalled(name)
			if state.category == "all"
				or (state.category == "installed" and installed)
				or (state.category == "available" and not installed) then
				if state.query == "" or tostring(name):lower():find(state.query, 1, true) then
					rows[#rows + 1] = { name = name, installed = installed }
				end
			end
		end
		return rows
	end

	local function refresh()
		state.rows = listPackages()
		if state.selected > #state.rows then
			state.selected = math.max(1, #state.rows)
		end
	end

	refresh()

	local function describe(row)
		if not row then
			return ""
		end
		local info = packages:info(row.name)
		local description = (info and info.description) or "no description"
		local state_ = row.installed and "installed" or "available"
		return string.format("%-10s %-14s %s", row.name, state_, description)
	end

	local function installSelected()
		local row = state.rows[state.selected]
		if not row then
			return
		end
		local ok, err = packages:install(row.name)
		if ok then
			state.status = "installed " .. row.name
		else
			state.status = "install failed: " .. tostring(err)
		end
		refresh()
	end

	local function removeSelected()
		local row = state.rows[state.selected]
		if not row then
			return
		end
		local ok, err = packages:remove(row.name)
		if ok then
			state.status = "removed " .. row.name
		else
			state.status = "remove failed: " .. tostring(err)
		end
		refresh()
	end

	local function rowArea()
		local top = 4
		local bottom = win.frame.h - 2
		return top, math.max(1, bottom - top + 1)
	end

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()

			-- category tabs
			local x = 2
			for _, cat in ipairs(CATEGORIES) do
				local label = " " .. cat.title .. " "
				term.setCursorPos(x, 1)
				term.setBackgroundColor(cat.id == state.category and colors.blue or colors.lightGray)
				term.setTextColor(colors.black)
				term.write(label)
				term.setBackgroundColor(colors.gray)
				term.setTextColor(colors.white)
				x = x + #label + 1
			end
			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, 2)
			term.write("search: " .. state.query .. "_")
			term.setTextColor(colors.white)

			local top, visible = rowArea()
			for i = 0, visible - 1 do
				local index = state.offset + i + 1
				local row = state.rows[index]
				if not row then
					break
				end
				term.setCursorPos(2, top + i)
				term.setBackgroundColor(index == state.selected and colors.blue or colors.gray)
				term.setTextColor(colors.white)
				term.write((" " .. describe(row) .. " "):sub(1, win.frame.w - 3))
				term.setBackgroundColor(colors.gray)
			end

			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write("up/down move  i install  x remove  / search  F5 refresh")
			term.setTextColor(colors.white)
			term.setCursorPos(2, win.frame.h)
			term.write(state.status)
		end,
		onMouse = function(w, ev)
			if ev[1] ~= "mouse_click" then
				return
			end
			local top, visible = rowArea()
			local row = ev[4] - top
			if row >= 0 and row < visible and state.rows[state.offset + row + 1] then
				state.selected = state.offset + row + 1
			end
		end,
		onKey = function(w, key, ctrl)
			if key == keys.up then
				state.selected = math.max(1, state.selected - 1)
			elseif key == keys.down then
				state.selected = math.min(math.max(1, #state.rows), state.selected + 1)
			elseif key == keys.f5 then
				refresh()
			elseif key == keys.i then
				installSelected()
			elseif key == keys.x then
				removeSelected()
			elseif key == keys.slash then
				state.query = ""
			elseif key == keys.backspace then
				state.query = state.query:sub(1, -2)
				refresh()
			end
		end,
		onChar = function(w, ch)
			if ch == nil or ch == "" or state.query == false then
				return
			end
			state.query = state.query .. ch
			refresh()
		end,
		onClose = function() end,
	}
end

return M
