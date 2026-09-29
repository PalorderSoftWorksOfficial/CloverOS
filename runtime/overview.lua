-- CloverOS GNOME overview: the Activities screen (app grid, search, window
-- strip) and the alt+tab window switcher. Rendering plus hit testing only;
-- runtime/desktop.lua performs the actions.
local M = {}

local function truncate(text, width)
	text = tostring(text or "")
	if width <= 0 then
		return ""
	end
	if #text <= width then
		return text
	end
	if width <= 3 then
		return text:sub(1, width)
	end
	return text:sub(1, width - 3) .. "..."
end

local function matches(app, query)
	if query == "" then
		return true
	end
	return tostring(app.title):lower():find(query, 1, true) ~= nil
		or tostring(app.id):lower():find(query, 1, true) ~= nil
end

function M.new(deps)
	deps = deps or {}
	local self = {
		apps = deps.apps or {},
		gui = deps.gui,
		desktop = deps.desktop,
		mode = nil, -- "overview" | "switcher"
		query = "",
		cells = {},
		selected = 1,
		windows = {},
	}

	function self:isOpen()
		return self.mode ~= nil
	end

	function self:visibleApps()
		local out = {}
		for _, app in ipairs(self.apps) do
			if matches(app, self.query) then
				out[#out + 1] = app
			end
		end
		return out
	end

	function self:openOverview()
		self.mode = "overview"
		self.query = ""
		self.cells = {}
	end

	function self:openSwitcher()
		self.windows = self.gui and self.gui:listWindows() or {}
		if #self.windows == 0 then
			return false
		end
		self.mode = "switcher"
		self.selected = self.selected % #self.windows + 1
		return true
	end

	function self:close()
		self.mode = nil
		self.query = ""
		self.cells = {}
	end

	-- ---------- input ----------
	function self:onChar(ch)
		if self.mode == "overview" and ch and ch ~= "" then
			self.query = self.query .. ch
			return true
		end
		return false
	end

	function self:onBackspace()
		if self.mode == "overview" and #self.query > 0 then
			self.query = self.query:sub(1, -2)
			return true
		end
		return false
	end

	function self:cycle()
		if self.mode ~= "switcher" or #self.windows == 0 then
			return false
		end
		self.selected = self.selected % #self.windows + 1
		return true
	end

	function self:currentWindow()
		return self.windows[self.selected]
	end

	function self:currentApp()
		local apps = self:visibleApps()
		return apps[1]
	end

	-- ---------- drawing ----------
	local function dimScreen(shade)
		local w, h = term.getSize()
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
		term.setCursorPos(1, 1)
		for y = 1, h do
			term.clearLine()
			term.setCursorPos(1, y)
			term.write(string.rep(shade and " " or " ", w))
		end
	end

	local function fillBlock(x, y, w, h, color)
		term.setBackgroundColor(color)
		for dy = 0, h - 1 do
			term.setCursorPos(x, y + dy)
			term.write(string.rep(" ", w))
		end
		term.setBackgroundColor(colors.black)
	end

	function self:drawSwitcher()
		local w, h = term.getSize()
		local count = #self.windows
		local boxW = math.min(40, w - 4)
		local x0 = math.floor((w - boxW) / 2) + 1
		local y0 = math.max(1, math.floor((h - count - 2) / 2))
		term.setBackgroundColor(colors.black)
		for i = 1, count do
			local y = y0 + i
			local win = self.windows[i]
			term.setCursorPos(x0, y)
			term.setBackgroundColor(i == self.selected and colors.blue or colors.black)
			term.setTextColor(colors.white)
			local label = truncate(" " .. tostring(win.title or "window"), boxW - 2)
			term.write(label .. string.rep(" ", math.max(0, boxW - #label)))
			term.setBackgroundColor(colors.black)
		end
		term.setTextColor(colors.lightGray)
		term.setCursorPos(x0, y0 + count + 1)
		term.write(" alt+tab to cycle, enter to switch, esc to cancel")
		term.setTextColor(colors.white)
	end

	function self:drawOverview()
		local w, h = term.getSize()
		dimScreen(false)

		-- search entry
		term.setCursorPos(2, 2)
		term.setBackgroundColor(colors.gray)
		term.setTextColor(colors.white)
		local entry = " " .. (self.query ~= "" and self.query or "Type to search...")
		term.write(truncate(entry, w - 4) .. "_")
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)

		-- app grid (GNOME 40 favourites dash)
		local apps = self:visibleApps()
		self.cells = {}
		local cols = 4
		local cellW = math.floor((w - 2) / cols)
		local gridTop = 4
		local gridBottom = h - 4
		for i, app in ipairs(apps) do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local x = 2 + col * cellW
			local y = gridTop + row * 2
			if y + 1 > gridBottom then
				break
			end
			fillBlock(x, y, math.max(3, cellW - 1), 1, colors.purple)
			term.setCursorPos(x, y)
			term.setTextColor(colors.white)
			local label = truncate(app.title, math.max(1, cellW - 3))
			term.write(" " .. label)
			self.cells[#self.cells + 1] = {
				kind = "app", appId = app.id, x = x, y = y, w = math.max(3, cellW - 1), h = 2,
			}
		end

		-- open windows strip
		term.setTextColor(colors.lightGray)
		term.setCursorPos(2, h - 3)
		term.write("Open Windows")
		term.setTextColor(colors.white)
		local wins = self.gui and self.gui:listWindows() or {}
		local tileW = math.floor((w - 2) / math.max(1, math.min(#wins, 3)))
		for i, win in ipairs(wins) do
			if i > 3 then
				break
			end
			local x = 2 + (i - 1) * tileW
			fillBlock(x, h - 2, math.max(3, tileW - 1), 1, colors.blue)
			term.setCursorPos(x, h - 2)
			term.setTextColor(colors.white)
			term.write(" " .. truncate(win.title, math.max(1, tileW - 4)))
			self.cells[#self.cells + 1] = {
				kind = "window", win = win, x = x, y = h - 2, w = math.max(3, tileW - 1), h = 1,
			}
		end

		-- "show applications" button
		term.setCursorPos(2, h)
		term.setBackgroundColor(colors.gray)
		term.setTextColor(colors.white)
		term.write(" Show Applications ")
		term.setBackgroundColor(colors.black)
		self.cells[#self.cells + 1] = { kind = "applications", x = 2, y = h, w = 18, h = 1 }

		-- hint line
		term.setCursorPos(21, h)
		term.setTextColor(colors.lightGray)
		term.write(truncate("esc to close, type to filter apps", w - 21))
		term.setTextColor(colors.white)
	end

	function self:draw()
		if self.mode == "switcher" then
			self:drawSwitcher()
		elseif self.mode == "overview" then
			self:drawOverview()
		end
	end

	-- ---------- hit testing ----------
	function self:hit(x, y)
		if self.mode == "switcher" then
			local w, h = term.getSize()
			local boxW = math.min(40, w - 4)
			local x0 = math.floor((w - boxW) / 2) + 1
			local y0 = math.max(1, math.floor((h - #self.windows - 2) / 2))
			local row = y - y0
			if x >= x0 and x < x0 + boxW and row >= 1 and row <= #self.windows then
				return { kind = "window", win = self.windows[row] }
			end
			return nil
		end
		if self.mode ~= "overview" then
			return nil
		end
		for _, cell in ipairs(self.cells) do
			if x >= cell.x and x < cell.x + cell.w and y >= cell.y and y < cell.y + cell.h then
				return { kind = cell.kind, appId = cell.appId, win = cell.win }
			end
		end
		return nil
	end

	return self
end

return M
