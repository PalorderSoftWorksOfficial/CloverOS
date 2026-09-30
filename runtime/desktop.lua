-- CloverOS GNOME desktop: top panel, Activities overview, window handling.
-- The desktop owns the single event loop; apps are pure callback objects.
-- Launched by CloverOS_OS.lua after a graphical login, or by `cloveros`
-- from the text shell (see runtime/launcher.lua).
local M = {}

local APPS = {
	{ id = "terminal", title = "Terminal", program = "apps/terminal.lua" },
	{ id = "files", title = "Files", program = "apps/files.lua" },
	{ id = "texteditor", title = "Text Editor", program = "apps/texteditor.lua" },
	{ id = "software", title = "Software", program = "apps/software.lua" },
	{ id = "settings", title = "Settings", program = "apps/settings.lua" },
	{ id = "sysinfo", title = "System Info", program = "apps/sysinfo.lua" },
	{ id = "imageviewer", title = "Image Viewer", program = "apps/imageviewer.lua" },
	{ id = "clocks", title = "Clocks", program = "apps/clocks.lua" },
	{ id = "media", title = "Media Player", program = "apps/media.lua" },
	{ id = "calculator", title = "Calculator", program = "apps/calculator.lua" },
	{ id = "help", title = "Help", program = "apps/help.lua" },
}

local CONTEXT_MENU = {
	{ label = "Open Terminal", action = "launch", appId = "terminal" },
	{ label = "Show Applications", action = "applications" },
	{ separator = true },
	{ label = "Settings", action = "launch", appId = "settings" },
	{ separator = true },
	{ label = "Log Out", action = "logout" },
	{ label = "Restart", action = "reboot" },
	{ label = "Shut Down", action = "shutdown" },
}

function M.new(deps)
	deps = deps or {}
	local self = {
		paths = deps.paths,
		users = deps.users,
		ui = deps.ui,
		packages = deps.packages,
		session = deps.session,
		kernel = deps.kernel,
		system = deps.system,
		gui = deps.gui,
		running = true,
		requestLogout = false,
		menuOpen = false,
		windows = {},
		ctrl = false,
		alt = false,
	}
	local okSize, tw, th = pcall(term.getSize)
	self.screenW = okSize and tw or 51
	self.screenH = okSize and th or 19
	self.overview = false
	self.contextMenu = false

	-- theme and notifications follow the same pattern as panel/overview:
	-- pure modules the desktop constructs and owns. They come first because
	-- the panel's bell and quick-settings toggles need their references.
	local themeOk, themeModule = pcall(dofile, self.paths:join("runtime", "theme.lua"))
	local notifyOk, notifyModule = pcall(dofile, self.paths:join("runtime", "notifications.lua"))
	if not (themeOk and notifyOk) then
		return nil, "CloverOS desktop: theme or notification modules missing"
	end
	self.theme = themeModule
	local userName = nil
	if self.users and type(self.users.currentName) == "function" then
		userName = self.users:currentName()
	end
	self.themeCfg = themeModule.load(self.paths, userName)
	self.notifications = notifyModule.new({ kernel = self.kernel })
	self.toast = nil
	self.toastUntil = 0
	self.volumeLevel = 50

	local panelOk, panelModule = pcall(dofile, self.paths:join("runtime", "panel.lua"))
	local overviewOk, overviewModule = pcall(dofile, self.paths:join("runtime", "overview.lua"))
	if not (panelOk and overviewOk) then
		return nil, "CloverOS desktop: GNOME shell modules missing"
	end
	self.panel = panelModule.new({
		users = self.users,
		ui = self.ui,
		kernel = self.kernel,
		apps = APPS,
		system = self.system,
		notifications = self.notifications,
		theme = self.theme,
		themeCfg = self.themeCfg,
	})
	self.overviewUi = overviewModule.new({
		apps = APPS,
		gui = self.gui,
		desktop = self,
	})

	-- windows live under the top bar, like the GNOME panel
	if self.gui and self.gui.workArea then
		self.gui.workArea = { x = 1, y = 2, w = self.screenW, h = self.screenH - 1 }
	end

	local function appById(id)
		for _, app in ipairs(APPS) do
			if app.id == id then
				return app
			end
		end
		return nil
	end

	local function notify(text)
		if self.ui and self.ui.notify then
			self.ui:notify(tostring(text))
		end
		if self.kernel and self.kernel.info then
			self.kernel.info("desktop: " .. tostring(text))
		end
		-- internal events are notifications too, so the center tells the
		-- same story as the journal
		if self.notifications then
			self.notifications:notifyText("desktop", text)
		end
	end

	-- Raise a user-facing notification: filed in the center, shown as a
	-- toast unless do-not-disturb is on, and journaled so text sessions can
	-- read what happened. This is the seam apps receive as deps.notify.
	function self:raise(item)
		local entry
		if type(item) == "table" then
			entry = self.notifications:notify(item)
		else
			entry = self.notifications:notifyText("system", item)
		end
		if entry then
			self.toast = entry
			self.toastUntil = os.clock() + 4
		end
		return entry
	end

	-- hardware hotplug becomes a notification, not a silent rescan
	if self.system and type(self.system.subscribe) == "function" then
		self.system:subscribe(function(topic, detail)
			if topic == "peripheral" then
				self:raise({ app = "hardware", title = "Device attached: " .. tostring(detail or "?") })
			elseif topic == "peripheral_detach" then
				self:raise({ app = "hardware", title = "Device removed: " .. tostring(detail or "?") })
			end
		end)
	end

	-- the application grid contents (dash), also used by the launcher
	function self:appList()
		local list = {}
		for i, app in ipairs(APPS) do
			list[i] = app
		end
		return list
	end

	function self:openApp(id, args)
		local app = appById(id)
		if not app then
			notify("unknown app: " .. tostring(id))
			return nil
		end
		for _, win in ipairs(self.windows) do
			if win.appId == id then
				self.gui:focusWindow(win)
				return win
			end
		end
		if not fs.exists(self.paths:join(app.program)) then
			notify("app missing: " .. app.program)
			return nil
		end

		local ok, win = pcall(self.gui.createWindow, self.gui, {
			title = app.title,
			w = 36,
			h = 12,
		})
		if not ok then
			notify("window failed: " .. tostring(win))
			return nil
		end

		local loaded, module = pcall(dofile, self.paths:join(app.program))
		if not loaded or type(module) ~= "table" or type(module.new) ~= "function" then
			self.gui:closeWindow(win)
			notify("app has no entrypoint: " .. app.program)
			return nil
		end

		local created, appObj = pcall(module.new, {
			window = win,
			gui = self.gui,
			paths = self.paths,
			users = self.users,
			ui = self.ui,
			packages = self.packages,
			session = self.session,
			kernel = self.kernel,
			desktop = self,
			notify = function(item)
				return self:raise(item)
			end,
			theme = self.theme,
			themeCfg = self.themeCfg,
			args = args or {},
		})
		if not created then
			self.gui:closeWindow(win)
			notify("app crashed on start: " .. tostring(appObj))
			return nil
		end

		win.appId = id
		win.appState = appObj

		local function forward(name)
			return function(win2, ...)
				local state = win2.appState
				if state and type(state[name]) == "function" then
					pcall(state[name], state, ...)
				end
			end
		end

		win.handlers.onDraw = forward("onDraw")
		win.handlers.onGuiEvent = forward("onGuiEvent")
		win.handlers.onKey = forward("onKey")
		win.handlers.onChar = forward("onChar")
		win.handlers.onMouse = forward("onMouse")
		win.handlers.onFocus = forward("onFocus")
		win.handlers.onClose = forward("onClose")

		self.windows[#self.windows + 1] = win
		notify("opened " .. app.title)
		return win
	end

	function self:closeWindow(win)
		for i, w in ipairs(self.windows) do
			if w == win then
				table.remove(self.windows, i)
				break
			end
		end
		self.gui:closeWindow(win)
		self.menuOpen = false
	end

	-- ---------- panel actions ----------
	function self:performAction(item)
		if type(item) ~= "table" then
			return
		end
		-- clicking a notification in the center dismisses it
		if item.notificationId then
			self.notifications:remove(item.notificationId)
			return
		end
		local action = item.action
		if action == "dnd" then
			self.panel:toggleDnd()
			self:refreshMenu()
		elseif action == "clearNotifications" then
			self.notifications:clear()
			self:refreshMenu()
		elseif action == "themeMode" then
			self.panel:toggleMode()
			self:saveTheme()
			self:refreshMenu()
		elseif action == "accentCycle" then
			if self.themeCfg then
				self.themeCfg.accent = self.theme.nextAccent(self.themeCfg.accent)
				self:saveTheme()
				self:refreshMenu()
			end		elseif action == "rednetToggle" then
			local state = self.system and self.system.state
			if state and state.rednet and state.rednet.present then
				if state.rednet.open > 0 then
					self.system:rednetClose()
					self:raise({ app = "network", title = "Rednet closed" })
				else
					local ok = self.system:rednetOpen()
					if ok then
						self:raise({ app = "network", title = "Rednet opened" })
					end
				end
				self:refreshMenu()
			end
		elseif action == "gpsToggle" then
			local state = self.system and self.system.state
			if state and state.gps and state.gps.present then
				state.gps.open = not state.gps.open
				self:refreshMenu()
			end
		elseif action == "volumeUp" then
			self.volumeLevel = ((self.volumeLevel or 50) + 25) % 125
			self:refreshMenu()
		elseif action == "launch" and item.appId then
			self:closeMenus()
			self:openApp(item.appId)
		elseif action == "applications" then
			self:closeMenus()
			self.overviewUi:openOverview()
			self.overview = true
		elseif action == "logout" then
			self.requestLogout = true
			self.running = false
		elseif action == "reboot" then
			self.running = false
			if self.kernel and self.kernel.reboot then
				self.kernel.reboot()
			else
				os.reboot()
			end
		elseif action == "shutdown" then
			self.running = false
			if self.kernel and self.kernel.shutdown then
				self.kernel.shutdown()
			else
				os.shutdown()
			end
		end
	end

	-- Re-render the open menu after a toggle changed its labels. panel:openMenu
	-- would close a menu reopened under the same name, so the item lists are
	-- rebuilt through openMenuAt instead.
	function self:refreshMenu()
		local name = self.panel.menu
		if name == "bell" then
			self.menuOpen = self.panel:openMenuAt("bell", self.panel:bellMenuItems())
		elseif name == "quickset" then
			self.menuOpen = self.panel:openMenuAt("quickset", self.panel:quicksetMenuItems())
		elseif name == "status" then
			self.menuOpen = self.panel:openMenuAt("status", self.panel:statusMenuItems())
		end
	end

	-- Persist the theme for the signed-in user. Best effort: a failed write
	-- only costs the user their preference until the next change.
	function self:saveTheme()
		if not (self.theme and self.themeCfg) then
			return false
		end
		local name = nil
		if self.users and type(self.users.currentName) == "function" then
			name = self.users:currentName()
		end
		return self.theme.save(self.paths, name, self.themeCfg)
	end

	function self:closeMenus()
		self.panel:closeMenu()
		self.contextMenu = false
		self.menuOpen = false
	end

	function self:toggleOverview()
		if self.overviewUi:isOpen() then
			self.overviewUi:close()
			self.overview = false
		else
			self:closeMenus()
			self.overviewUi:openOverview()
			self.overview = true
		end
	end

	-- ---------- drawing ----------
	function self:drawWallpaper()
		if self.theme then
			self.theme.draw(self.paths, self.themeCfg, self.screenW, self.screenH)
			return
		end
		local w, h = term.getSize()
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
		for y = 2, h do
			term.setCursorPos(1, y)
			term.clearLine()
			term.write(string.rep(" ", w))
		end
		term.setBackgroundColor(colors.black)
	end

	-- GNOME-style toast: one banner row directly under the panel, gone
	-- after its time expires (the run loop clears it) or the next click.
	function self:drawToast()
		local entry = self.toast
		if not entry or os.clock() >= self.toastUntil then
			return
		end
		local w = self.screenW
		local text = " " .. tostring(entry.app or "system") .. ": " .. tostring(entry.title or "")
		local width = math.min(#text, w - 2)
		local x = math.max(1, math.floor((w - width) / 2) + 1)
		term.setCursorPos(x, 2)
		term.setBackgroundColor(colors.white)
		term.setTextColor(colors.black)
		term.write(text:sub(1, width) .. string.rep(" ", math.max(0, width - #text:sub(1, width))))
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
	end

	function self:render()
		for i = #self.windows, 1, -1 do
			local win = self.windows[i]
			if not self.gui:isOpen(win) then
				table.remove(self.windows, i)
			end
		end

		local focused = self.gui.focused
		self.panel.focusedTitle = (focused and focused.title) or ""
		self.overview = self.overviewUi:isOpen() and self.overviewUi.mode == "overview"

		self.gui:render(function() self:drawWallpaper() end)
		if self.overviewUi:isOpen() then
			self.overviewUi:draw()
		end
		self.panel:draw()
		self:drawToast()
		if self.ui and self.ui.drawNotify then
			self.ui:drawNotify(self.screenH)
		end
	end

	-- ---------- input ----------
	function self:onMouseClick(ev)
		local x, y = ev[3], ev[4]
		if y <= self.panel.height then
			local hit = self.panel:hit(x, y)
			if hit and hit.zone == "menu" and hit.item then
				self.panel:highlight(hit.item)
				self:performAction(hit.item)
				if hit.item.action ~= "launch" then
					self.panel:closeMenu()
				end
			elseif hit and hit.zone == "activities" then
				self:toggleOverview()
			elseif hit and hit.zone == "user" then
				self:openMenu("user")
			elseif hit and hit.zone == "status" then
				self:openMenu("status")
			elseif hit and hit.zone == "bell" then
				self:openMenu("bell")
			elseif hit and hit.zone == "quickset" then
				self:openMenu("quickset")
			elseif hit and hit.zone == "bar" then
				self:openMenu("app")
			end
			return
		end

		if self.panel.menu or self.contextMenu then
			local hit = self.panel:hit(x, y)
			if hit and hit.zone == "menu" and hit.item and not (hit.item.separator or hit.item.info or hit.item.header) then
				self.panel:highlight(hit.item)
				self:performAction(hit.item)
			end
			self:closeMenus()
			return
		end

		if self.overviewUi:isOpen() then
			local hit = self.overviewUi:hit(x, y)
			if hit and hit.kind == "app" then
				self.overviewUi:close()
				self:openApp(hit.appId)
			elseif hit and hit.kind == "window" then
				self.overviewUi:close()
				self.gui:focusWindow(hit.win)
			elseif hit and hit.kind == "applications" then
				-- already showing every installed app
				notify("all applications are shown")
			end
			return
		end

		if ev[2] == 2 then
			-- right click on the desktop background opens the context menu
			self.panel:openMenuAt("context", CONTEXT_MENU, x)
			self.contextMenu = true
			return
		end

		self.gui:pump(ev)
	end

	function self:openMenu(name)
		self.contextMenu = false
		self.menuOpen = self.panel:openMenu(name)
	end

	-- CC:Tweaked has no keys.escape constant: the Escape key arrives as a
	-- char event carrying ESC. Hosts that do expose keys.escape (CraftOS-PC)
	-- are honoured as well, so one handler covers both.
	local ESCAPE = "\27"

	function self:handleEscape()
		if self.panel.menu or self.contextMenu then
			self:closeMenus()
		elseif self.overviewUi:isOpen() then
			self.overviewUi:close()
		end
	end

	function self:onKey(key)
		if keys.escape ~= nil and key == keys.escape then
			self:handleEscape()
			return
		end

		if self.overviewUi:isOpen() then
			if key == keys.backspace then
				self.overviewUi:onBackspace()
			elseif key == keys.enter then
				if self.overviewUi.mode == "switcher" then
					local win = self.overviewUi:currentWindow()
					self.overviewUi:close()
					if win then
						self.gui:focusWindow(win)
					end
				else
					local app = self.overviewUi:currentApp()
					self.overviewUi:close()
					if app then
						self:openApp(app.id)
					end
				end
			elseif key == keys.tab and self.overviewUi.mode == "switcher" then
				self.overviewUi:cycle()
			end
			return
		end

		if key == keys.f1 then
			self:openApp("terminal")
		elseif key == keys.f2 then
			self:openApp("files")
		elseif key == keys.f3 then
			self:openApp("settings")
		elseif key == keys.f4 then
			if self.alt then
				if self.gui.focused then
					self:closeWindow(self.gui.focused)
				end
			else
				self:openApp("sysinfo")
			end
		elseif key == keys.f5 then
			self:toggleOverview()
		elseif key == keys.f6 and self.gui.focused then
			self.gui:snap(self.gui.focused, "left")
		elseif key == keys.f7 and self.gui.focused then
			self.gui:snap(self.gui.focused, "right")
		elseif key == keys.f8 and self.gui.focused then
			local focused = self.gui.focused
			self.gui:snap(focused, focused.restoreBounds and "restore" or "max")
		elseif key == keys.f10 then
			self.requestLogout = true
			self.running = false
		elseif key == keys.tab and self.alt then
			if not self.overviewUi:isOpen() then
				self.overviewUi:openSwitcher()
			else
				self.overviewUi:cycle()
			end
		end
	end

	function self:onChar(ch)
		if ch == ESCAPE then
			self:handleEscape()
			return
		end
		if self.ctrl and self.alt and ch == "t" then
			self:openApp("terminal")
			return
		end
		if self.overviewUi:isOpen() then
			self.overviewUi:onChar(ch)
		end
	end

	-- ---------- main loop ----------
	function self:run()
		local w, h = term.getSize()
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
		term.clear()

		if self.kernel and self.kernel.info then
			self.kernel.info("desktop session started")
		end

		self:render()

		-- boot-verification marker: proves the desktop rendered; tests read it
		pcall(function()
			local marker = self.paths:join("var", "log", "desktop-booted")
			fs.makeDir(fs.getDir(marker))
			local handle = fs.open(marker, "w")
			if handle then
				handle.write(tostring(os.epoch("utc")))
				handle.close()
			end
		end)

		while self.running do
			local ev = { os.pullEventRaw() }
			local kind = ev[1]

			if kind == "terminate" then
				self.running = false
			elseif kind == "key" then
				local key = ev[2]
				if key == keys.leftCtrl or key == keys.rightCtrl then
					self.ctrl = true
				elseif key == keys.leftAlt or key == keys.rightAlt then
					self.alt = true
				else
					self:onKey(key)
				end
			elseif kind == "key_up" then
				local key = ev[2]
				if key == keys.leftCtrl or key == keys.rightCtrl then
					self.ctrl = false
				elseif key == keys.leftAlt or key == keys.rightAlt then
					-- releasing alt commits the window switcher (alt+tab)
					if self.overviewUi:isOpen() and self.overviewUi.mode == "switcher" then
						local win = self.overviewUi:currentWindow()
						self.overviewUi:close()
						if win then
							self.gui:focusWindow(win)
						end
					end
					self.alt = false
				end
			elseif kind == "char" or kind == "paste" then
				self:onChar(ev[2])
			elseif kind == "mouse_click" then
				self:onMouseClick(ev)
			elseif kind == "mouse_double_click" then
				if not self.overviewUi:isOpen() then
					self.gui:pump(ev)
				end
			elseif kind == "mouse_drag" or kind == "mouse_up" then
				if not self.overviewUi:isOpen() and not self.panel.menu then
					self.gui:pump(ev)
				end
			elseif kind == "timer" then
				-- the toast's expiry: once its time is up, drop it so the
				-- next render repaints the desktop without the banner
				if self.toast and os.clock() >= self.toastUntil then
					self.toast = nil
				end
			elseif self.system and self.system:dispatch(ev) then
				-- hardware event (modem, wifi, gps, rednet, hotplug): the
				-- system layer took it, so the window manager must not.
				-- Persist it, or a later `rednet inbox` in a text shell
				-- would never see what this session received.
				self.system:save()
				self:render()
			else
				if not self.overviewUi:isOpen() and not self.panel.menu then
					local result = self.gui:pump(ev)
					if result == "terminate" then
						self.running = false
					end
				end
			end

			if self.running then
				self:render()
			end
		end

		for i = #self.windows, 1, -1 do
			self:closeWindow(self.windows[i])
		end
		if self.kernel and self.kernel.info then
			self.kernel.info("desktop session ended")
		end
	end

	return self
end

return M
