-- CloverOS GNOME panel: the top bar, system status indicators, and menus.
-- Pure rendering plus hit testing; runtime/desktop.lua owns the event loop.
local M = {}

local function dateString(fmt)
	local ok, value = pcall(os.date, fmt)
	if ok and type(value) == "string" then
		return value
	end
	return ""
end

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

function M.new(deps)
	deps = deps or {}
	local self = {
		users = deps.users,
		ui = deps.ui,
		kernel = deps.kernel,
		system = deps.system,
		apps = deps.apps or {},
		focusedTitle = "",
		menu = nil,
		items = {},
		zones = {},
		height = 1,
	}

	-- ---------- system status ----------
	function self:statusLines()
		local lines = {}
		local peripherals = {}
		-- the system layer keeps a live view of the hardware; fall back to
		-- the kernel's snapshot when the session did not create one
		if self.system and self.system.state then
			peripherals = self.system.state.peripherals or {}
		elseif self.kernel and self.kernel.peripherals then
			local ok, list = pcall(self.kernel.peripherals)
			if ok and type(list) == "table" then
				peripherals = list
			end
		end

		local network, volume, battery = "offline", "n/a", "n/a"
		if self.system and type(self.system.summary) == "function" then
			local ok, summary = pcall(self.system.summary, self.system)
			if ok and type(summary) == "string" and summary ~= "" then
				network = summary
			end
		else
			for _, p in ipairs(peripherals) do
				if p.type == "wifi" then
					network = "wifi"
				elseif p.type == "modem" then
					network = "modem"
				end
			end
		end
		for _, p in ipairs(peripherals) do
			if p.type == "speaker" then
				volume = "available"
			elseif p.type == "energy" then
				battery = "present"
			end
		end

		lines[#lines + 1] = { label = "Network", value = network }
		if self.system and self.system.state then
			local gps = self.system.state.gps
			if gps and gps.present then
				local where = "no fix"
				if gps.lat ~= nil and gps.lon ~= nil then
					where = string.format("%.2f, %.2f", gps.lat, gps.lon)
				end
				lines[#lines + 1] = { label = "GPS", value = (gps.open and where or ("closed, " .. where)) }
			end
			local rednet = self.system.state.rednet
			if rednet and rednet.present then
				lines[#lines + 1] = {
					label = "Rednet",
					value = string.format("%d open, %d sent, %d received",
						rednet.open, rednet.sent, rednet.received),
				}
			end
			local storage = self.system.state.storage
			if storage and (storage.disks > 0 or storage.space) then
				lines[#lines + 1] = {
					label = "Disks",
					value = tostring(storage.disks) .. " attached"
						.. (storage.space and (", " .. tostring(storage.space) .. " free") or ""),
				}
			end
		end
		lines[#lines + 1] = { label = "Volume", value = volume }
		lines[#lines + 1] = { label = "Battery", value = battery }
		if self.users then
			local name = self.users:currentName()
			lines[#lines + 1] = { label = "User", value = (name ~= "" and name) or "none" }
		end
		if self.kernel and self.kernel.status then
			local ok, info = pcall(self.kernel.status)
			if ok and type(info) == "table" then
				lines[#lines + 1] = {
					label = "System",
					value = tostring(info.name or "CloverOS") .. " " .. tostring(info.version or ""),
				}
			end
		end
		return lines
	end

	-- Compact one-line summary for the top bar. The status menu carries the
	-- detail; this is only what fits in a single row next to the clock.
	function self:statusText()
		local parts = {}
		if self.system and type(self.system.summary) == "function" then
			local ok, summary = pcall(self.system.summary, self.system)
			if ok and type(summary) == "string" and summary ~= "" then
				parts[#parts + 1] = summary
			end
		end
		if not self.system then
			local lines = self:statusLines()
			parts[#parts + 1] = (lines[1] and lines[1].value) or "offline"
		end
		local state = self.system and self.system.state
		if state then
			if state.gps and state.gps.lat ~= nil then
				parts[#parts + 1] = "gps"
			end
			if state.rednet and state.rednet.open > 0 then
				parts[#parts + 1] = "rn" .. state.rednet.open
			end
		end
		return "[" .. table.concat(parts, "] [") .. "]"
	end

	function self:userName()
		if self.users and self.users.currentName then
			return self.users:currentName()
		end
		return ""
	end

	function self:clockText()
		return dateString("%a %d %b  %H:%M")
	end

	-- ---------- menus ----------
	function self:appMenuItems()
		local items = {
			{ label = "Show Applications", action = "applications" },
		}
		for _, app in ipairs(self.apps) do
			items[#items + 1] = { label = app.title, action = "launch", appId = app.id }
		end
		items[#items + 1] = { separator = true }
		items[#items + 1] = { label = "Settings", action = "launch", appId = "settings" }
		items[#items + 1] = { label = "About CloverOS", action = "launch", appId = "help" }
		return items
	end

	function self:userMenuItems()
		return {
			{ label = self:userName() ~= "" and self:userName() or "Not signed in", header = true },
			{ separator = true },
			{ label = "Settings", action = "launch", appId = "settings" },
			{ label = "System Info", action = "launch", appId = "sysinfo" },
			{ separator = true },
			{ label = "Log Out", action = "logout" },
			{ label = "Switch User", action = "logout" },
			{ label = "Restart", action = "reboot" },
			{ label = "Shut Down", action = "shutdown" },
		}
	end

	function self:statusMenuItems()
		local items = {}
		for _, line in ipairs(self:statusLines()) do
			items[#items + 1] = { label = line.label .. ": " .. line.value, info = true }
		end
		items[#items + 1] = { separator = true }
		items[#items + 1] = { label = "System Settings", action = "launch", appId = "settings" }
		items[#items + 1] = { label = "System Info", action = "launch", appId = "sysinfo" }
		return items
	end

	function self:openMenu(name)
		if self.menu == name then
			self:closeMenu()
			return false
		end
		if name == "app" then
			return self:openMenuAt("app", self:appMenuItems())
		elseif name == "user" then
			return self:openMenuAt("user", self:userMenuItems())
		elseif name == "status" then
			return self:openMenuAt("status", self:statusMenuItems())
		end
		return false
	end

	-- open an explicit item list; x0 anchors the menu (default: panel edge)
	function self:openMenuAt(name, items, x0)
		self.items = items or {}
		self.menu = name or "custom"
		self.menuX = x0
		self.selection = nil
		return true
	end

	function self:closeMenu()
		self.menu = nil
		self.menuX = nil
		self.items = {}
		self.selection = nil
	end

	-- menu item under (x, y); rows start at the bar height
	function self:menuHit(x, y)
		if not self.menu then
			return nil
		end
		local _, h = term.getSize()
		local x0, w = self:menuOrigin()
		local row = y - self.height
		if row < 1 or row > #self.items then
			return nil
		end
		if x < x0 or x >= x0 + w then
			return nil
		end
		return self.items[row]
	end

	function self:menuOrigin()
		local w = 32
		local _, screenW = term.getSize()
		if self.menuX then
			return math.max(1, math.min(self.menuX, screenW - w + 1)), w
		end
		local x0 = 1
		if self.menu == "user" or self.menu == "status" then
			x0 = math.max(1, screenW - w)
		end
		return x0, w
	end

	-- ---------- drawing ----------
	-- Works out what the bar shows for a screen `w` columns wide. Split out
	-- from drawBar so the fitting rule is testable without a terminal: the
	-- bar is one row, and term.write wraps when it overflows.
	function self:barLayout(w)
		local activities = " Activities "
		local clock = self:clockText()
		local user = self:userName()
		local status = self:statusText()
		-- shrink the optional parts until the right-hand block fits
		local available = w - #activities - 2
		if #status + #clock + #user + 6 > available then
			status = truncate(status, math.max(0, math.min(#status, available - #clock - #user - 6)))
		end
		if #status + #clock + #user + 6 > available then
			user = truncate(user, math.max(0, available - #status - #clock - 6))
		end
		local right = status .. "  " .. clock .. "  " .. user .. " "
		return {
			activities = activities,
			status = status,
			clock = clock,
			user = user,
			x = math.max(#activities + 2, w - #right + 1),
		}
	end

	function self:drawBar()
		local w, h = term.getSize()
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
		term.setCursorPos(1, 1)
		term.clearLine()

		-- left: Activities (opens the overview, like the GNOME super key)
		local layout = self:barLayout(w)
		term.setTextColor(self.menu == "app" and colors.lightGray or colors.white)
		term.write(layout.activities)
		self.zones.activities = { x1 = 1, x2 = #layout.activities }

		-- right: status, clock, user
		local rx = layout.x
		term.setCursorPos(rx, 1)
		term.setTextColor(self.menu == "status" and colors.lightGray or colors.white)
		term.write(layout.status)
		self.zones.status = { x1 = rx, x2 = rx + #layout.status - 1 }
		local cx = rx + #layout.status + 2
		term.setCursorPos(cx, 1)
		term.write(layout.clock)
		self.zones.clock = { x1 = cx, x2 = cx + #layout.clock - 1 }
		local ux = cx + #layout.clock + 2
		term.setCursorPos(ux, 1)
		term.setTextColor(self.menu == "user" and colors.lightGray or colors.white)
		term.write(layout.user .. " ")
		self.zones.user = { x1 = ux, x2 = ux + #layout.user }
		term.setTextColor(colors.white)

		-- centre: focused window title
		if self.focusedTitle and self.focusedTitle ~= "" then
			local space = rx - self.zones.activities.x2 - 2
			local title = truncate(self.focusedTitle, math.max(0, math.floor(space / 2)))
			if #title > 0 then
				term.setCursorPos(math.max(1, self.zones.activities.x2 + 1
					+ math.floor((space - #title) / 2)), 1)
				term.setTextColor(colors.lightGray)
				term.write(title)
				term.setTextColor(colors.white)
			end
		end
		return h
	end

	function self:drawMenu()
		if not self.menu then
			return
		end
		local x0, width = self:menuOrigin()
		local _, h = term.getSize()
		for i, item in ipairs(self.items) do
			local y = self.height + i
			if y > h then
				break
			end
			term.setCursorPos(x0, y)
			term.setBackgroundColor(colors.black)
			term.clearLine()
			if item.separator then
				term.setTextColor(colors.gray)
				term.write(" " .. string.rep("-", width - 2) .. " ")
			else
				local label = truncate(" " .. item.label, width)
				if item == self.selection then
					term.setBackgroundColor(colors.blue)
					term.setTextColor(colors.white)
				elseif item.header or item.info then
					term.setBackgroundColor(colors.black)
					term.setTextColor(colors.lightGray)
				else
					term.setBackgroundColor(colors.black)
					term.setTextColor(colors.white)
				end
				term.write(label .. string.rep(" ", math.max(0, width - #label)))
				term.setTextColor(colors.white)
			end
			term.setBackgroundColor(colors.black)
		end
	end

	function self:draw()
		self:drawBar()
		self:drawMenu()
	end

	-- ---------- hit testing ----------
	function self:hit(x, y)
		if y <= self.height then
			local z = self.zones
			if z.activities and x >= z.activities.x1 and x <= z.activities.x2 then
				return { zone = "activities" }
			elseif z.user and x >= z.user.x1 and x <= z.user.x2 then
				return { zone = "user" }
			elseif z.status and x >= z.status.x1 and x <= z.status.x2 then
				return { zone = "status" }
			elseif z.clock and x >= z.clock.x1 and x <= z.clock.x2 then
				return { zone = "clock" }
			end
			return { zone = "bar" }
		end
		local item = self:menuHit(x, y)
		if item then
			return { zone = "menu", item = item }
		end
		return { zone = "panel" }
	end

	function self:highlight(item)
		self.selection = item
	end

	return self
end

return M
