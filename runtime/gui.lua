-- CloverOS GUI: window manager over the vendored MC-ImGui backend.
-- Owns z-order, focus, mouse routing, and close handling. Applications are
-- callback-driven: they never pull events and never touch imgui internals.
local M = {}

function M.new(deps)
	deps = deps or {}
	local imgui = dofile(fs.combine(CLOVER_ROOT, "libs/mc-imgui.lua"))

	local self = {
		roots = {}, -- ascending z-order: index 1 is bottom
		focused = nil,
		activeMouse = nil,
		dragWin = nil, -- window whose title bar is being dragged (edge snap)
		-- area windows may occupy; the desktop shrinks it below the top bar
		workArea = nil,
	}
	local screenW, screenH = term.getSize()
	self.workArea = { x = 1, y = 1, w = screenW, h = screenH }

	local rootWindow = window.create(term.current(), 1, 1, term.getSize())
	imgui.init(rootWindow, term.current())
	self.imgui = imgui

	local function indexOf(win)
		for i, w in ipairs(self.roots) do
			if w == win then
				return i
			end
		end
		return nil
	end

	local function topWindow()
		return self.roots[#self.roots]
	end

	-- a minimized frame is only its title bar high
	local function visibleHeight(win)
		local st = win.frame.style
		return (st and st.maximised) and win.frame.h or 1
	end

	local function hitTest(x, y)
		for i = #self.roots, 1, -1 do
			local win = self.roots[i]
			local p = win.frame.position
			if x >= p.x and x < p.x + win.frame.w and y >= p.y and y < p.y + visibleHeight(win) then
				return win
			end
		end
		return nil
	end

	function self:createWindow(spec)
		spec = spec or {}
		local area = self.workArea
		local aw, ah = area.w, area.h
		local w = math.max(10, math.min(spec.w or 36, aw - 2))
		local h = math.max(3, math.min(spec.h or 14, ah - 2))
		local x = math.max(1, math.min(spec.x or 2 + (#self.roots % 4) * 4, aw - w + 1))
		local y = math.max(1, math.min(spec.y or 2 + (#self.roots % 3) * 2, ah - h + 1))

		local win = {
			title = spec.title or "window",
			hidden = false,
		}
		win.frame = self.imgui.createFrame(win.title, x, y, w, h)

		win.handlers = {
			onGuiEvent = spec.onGuiEvent,
			onKey = spec.onKey,
			onChar = spec.onChar,
			onMouse = spec.onMouse,
			onFocus = spec.onFocus,
			onClose = spec.onClose,
			onDraw = spec.onDraw,
		}

		function win:close()
			self.closeRequested = true
		end

		win.closeRequested = false
		local manager = self
		function win:focus()
			return manager:focusWindow(win)
		end
		self.roots[#self.roots + 1] = win
		self:focusWindow(win)
		return win
	end

	function self:focusWindow(win)
		local idx = indexOf(win)
		if not idx then
			return false
		end
		local top = topWindow()
		if top ~= win then
			table.remove(self.roots, idx)
			self.roots[#self.roots + 1] = win
		end
		if self.focused ~= win then
			self.focused = win
			if win.handlers.onFocus then
				pcall(win.handlers.onFocus, win, true)
			end
		end
		return true
	end

	local function removeWindow(win)
		local idx = indexOf(win)
		if not idx then
			return false
		end
		table.remove(self.roots, idx)
		win.frame.setVisible(false)
		if self.focused == win then
			self.focused = topWindow() -- may be nil if no windows remain
		end
		if self.activeMouse == win then
			self.activeMouse = nil
		end
		if self.dragWin == win then
			self.dragWin = nil
		end
		if win.handlers.onClose then
			pcall(win.handlers.onClose, win)
		end
		return true
	end

	function self:closeWindow(win)
		return removeWindow(win)
	end

	function self:listWindows()
		local copy = {}
		for i, win in ipairs(self.roots) do
			copy[i] = win
		end
		return copy
	end

	function self:isOpen(win)
		return indexOf(win) ~= nil
	end

	-- ---------- window snapping (CloverOS extension) ----------
	function self:snap(win, side)
		local area = self.workArea
		local ax, ay, aw, ah = area.x, area.y, area.w, area.h
		local f = win.frame
		if side == "max" then
			win.restoreBounds = win.restoreBounds or {
				x = f.position.x, y = f.position.y, w = f.w, h = f.h,
			}
			f.setBounds(ax, ay, aw, ah)
			f.setMaximised(true)
		elseif side == "left" then
			f.setBounds(ax, ay, math.floor(aw / 2), ah)
			f.setMaximised(true)
		elseif side == "right" then
			local w1 = math.floor(aw / 2)
			f.setBounds(ax + w1, ay, aw - w1, ah)
			f.setMaximised(true)
		elseif side == "restore" then
			local saved = win.restoreBounds
			if saved then
				f.setBounds(saved.x, saved.y, saved.w, saved.h)
				f.setMaximised(true)
				win.restoreBounds = nil
			else
				f.setMaximised(not f.style.maximised)
			end
		end
		return true
	end

	-- true when (x, y) is on the draggable part of win's title bar
	local function onTitleDragArea(win, x, y)
		local p = win.frame.position
		return y == p.y and x > p.x and x < p.x + win.frame.w - 1
	end

	local function deliver(win, ev)
		local widgetEvents = win.frame.processEvent(ev)
		if type(widgetEvents) == "table" then
			for _, ge in ipairs(widgetEvents) do
				ge.window = win
				if win.handlers.onGuiEvent then
					pcall(win.handlers.onGuiEvent, win, ge)
				end
			end
		end
		if ev[1] == "mouse_click" and win.handlers.onMouse then
			-- title-bar clicks (drag start / close / minimize) belong to the
			-- frame, not the app
			local p = win.frame.position
			local onTitle = ev[4] == p.y and ev[3] >= p.x and ev[3] < p.x + win.frame.w
			if not onTitle then
				pcall(win.handlers.onMouse, win, ev)
			end
		end
	end

	function self:pump(ev)
		local kind = ev[1]

		if kind == "mouse_click" then
			local win = hitTest(ev[3], ev[4])
			if win then
				self:focusWindow(win)
				self.activeMouse = win
				if onTitleDragArea(win, ev[3], ev[4]) then
					self.dragWin = win
				end
				deliver(win, ev)
			else
				self.activeMouse = nil
			end
		elseif kind == "mouse_double_click" then
			local win = hitTest(ev[3], ev[4])
			if win then
				self:focusWindow(win)
				deliver(win, ev)
				local p = win.frame.position
				local onTitle = ev[4] == p.y and ev[3] >= p.x and ev[3] < p.x + win.frame.w
				if onTitle then
					if win.restoreBounds then
						self:snap(win, "restore")
					else
						win.frame.setMaximised(not win.frame.style.maximised)
					end
				end
			end
		elseif kind == "mouse_drag" or kind == "mouse_up" then
			local win = self.activeMouse or topWindow()
			if win then
				deliver(win, ev)
			end
			if kind == "mouse_drag" and self.dragWin then
				-- live edge snap: top edge maximises, side edges half-snap
				local area = self.workArea
				if ev[4] == area.y then
					self:snap(self.dragWin, "max")
				elseif ev[3] == area.x then
					self:snap(self.dragWin, "left")
				elseif ev[3] == area.x + area.w - 1 then
					self:snap(self.dragWin, "right")
				end
			end
			if kind == "mouse_up" then
				self.activeMouse = nil
				self.dragWin = nil
			end
		elseif kind == "key" or kind == "key_up" or kind == "char" or kind == "paste" then
			local win = self.focused or topWindow()
			if win then
				-- imgui widgets (textboxes) see the event first, then the app
				deliver(win, ev)
				if kind == "char" then
					if win.handlers.onChar then
						pcall(win.handlers.onChar, win, ev[2])
					end
				elseif kind == "key" and win.handlers.onKey then
					pcall(win.handlers.onKey, win, ev[2], ev[3])
				end
			end
		elseif kind == "terminate" then
			return "terminate"
		end

		-- process close requests from title bar or apps
		for i = #self.roots, 1, -1 do
			local win = self.roots[i]
			if win.closeRequested or win.frame.closeRequested then
				removeWindow(win)
			end
		end

		return nil
	end

	-- background (if given) is drawn over the cleared screen, under windows
	function self:render(background)
		-- draw bottom-to-top so higher z windows overlay lower ones; each app
		-- draws its content first, then the title bar and widgets render on top
		self.imgui.window.setVisible(false)
		self.imgui.window.clear()
		if background then
			pcall(background)
		end
		for _, win in ipairs(self.roots) do
			if not win.hidden then
				term.redirect(win.frame.win)
				if win.handlers.onDraw then
					pcall(win.handlers.onDraw, win)
				end
				term.redirect(self.imgui.parent or term.native())
				win.frame.render()
			end
		end
		term.redirect(self.imgui.parent or term.native())
		self.imgui.window.setVisible(true)
	end

	return self
end

return M
