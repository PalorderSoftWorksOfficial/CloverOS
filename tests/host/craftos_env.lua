-- In-memory CraftOS environment for host-side tests (tests/host/run.js).
-- Provides the CC:Tweaked / CraftOS API surface the CloverOS modules use:
-- fs, os, textutils, term, window, colors, keys, shell, parallel, read/write.
-- The virtual filesystem is seeded from the repository files handed in by
-- the Node runner.
local M = {}

function M.install(repoFiles)
	-- ---------- virtual filesystem ----------
	-- nodes: { dir = true, children = { [name] = node } } or { data = "..." }
	local root = { dir = true, children = {} }
	local fs = {}

	local function normalize(path)
		local parts = {}
		for piece in tostring(path or ""):gmatch("[^/]+") do
			if piece == ".." then
				if #parts > 0 then
					table.remove(parts)
				end
			elseif piece ~= "." then
				parts[#parts + 1] = piece
			end
		end
		return table.concat(parts, "/")
	end

	local function nodeAt(path)
		local node = root
		if normalize(path) == "" then
			return root
		end
		for piece in normalize(path):gmatch("[^/]+") do
			if not node.dir then
				return nil
			end
			node = node.children[piece]
			if not node then
				return nil
			end
		end
		return node
	end

	local function parentOf(path)
		local n = normalize(path)
		local parent, name = n:match("^(.-)/?([^/]*)$")
		return nodeAt(parent), name
	end

	local function writeFile(path, data)
		local n = normalize(path)
		-- create missing parents (the virtual tree starts empty)
		local parentPath = n:match("^(.-)/?[^/]*$")
		if parentPath ~= "" then
			fs.makeDir(parentPath)
		end
		local parent, name = parentOf(path)
		if not parent or not parent.dir or name == "" then
			return nil, "cannot write " .. tostring(path)
		end
		parent.children[name] = { data = tostring(data or "") }
		return true
	end

	local function readFile(path)
		local node = nodeAt(path)
		if not node or node.dir then
			return nil
		end
		return node.data
	end

	function fs.combine(...)
		return normalize(table.concat({ ... }, "/"))
	end

	function fs.getName(path)
		local n = normalize(path)
		return n:match("([^/]*)$") or ""
	end

	function fs.getDir(path)
		local n = normalize(path)
		local parent = n:match("^(.-)/?[^/]*$")
		return parent
	end

	function fs.exists(path)
		return nodeAt(path) ~= nil
	end

	function fs.isDir(path)
		local node = nodeAt(path)
		return node ~= nil and node.dir == true
	end

	function fs.isReadOnly()
		return false
	end

	function fs.getSize(path)
		local node = nodeAt(path)
		if not node or node.dir then
			error("No such file")
		end
		return #node.data
	end

	function fs.getFreeSpace(path)
		return 1000000
	end

	function fs.getCapacity(path)
		return 2000000
	end

	function fs.list(path)
		local node = nodeAt(path)
		if not node or not node.dir then
			error("Not a directory")
		end
		local out = {}
		for name in pairs(node.children) do
			out[#out + 1] = name
		end
		table.sort(out)
		return out
	end

	function fs.makeDir(path)
		local n = normalize(path)
		local node = root
		for piece in n:gmatch("[^/]+") do
			if not node.children[piece] then
				node.children[piece] = { dir = true, children = {} }
			end
			node = node.children[piece]
			if not node.dir then
				error("File exists")
			end
		end
	end

	function fs.delete(path)
		local parent, name = parentOf(path)
		if parent and parent.dir then
			parent.children[name] = nil
		end
	end

	function fs.copy(from, to)
		local node = nodeAt(from)
		if not node then
			error("No such file")
		end
		local function clone(n)
			if n.dir then
				local out = { dir = true, children = {} }
				for name, child in pairs(n.children) do
					out.children[name] = clone(child)
				end
				return out
			end
			return { data = n.data }
		end
		local parent, name = parentOf(to)
		parent.children[name] = clone(node)
	end

	function fs.move(from, to)
		local node = nodeAt(from)
		if not node then
			error("No such file")
		end
		local parent, name = parentOf(to)
		parent.children[name] = node
		fs.delete(from)
	end

	function fs.open(path, mode)
		mode = mode or "r"
		if mode == "r" then
			local data = readFile(path)
			if data == nil then
				return nil
			end
			local pos = 1
			return {
				readAll = function()
					pos = #data + 1
					return data
				end,
				readLine = function()
					if pos > #data then
						return nil
					end
					local s, e = data:find("\n", pos, true)
					local line
					if s then
						line = data:sub(pos, s - 1)
						pos = e + 1
					else
						line = data:sub(pos)
						pos = #data + 1
					end
					return line
				end,
				close = function() end,
			}
		elseif mode == "w" or mode == "a" then
			local buf = mode == "a" and (readFile(path) or "") or ""
			return {
				write = function(text)
					buf = buf .. tostring(text)
				end,
				writeLine = function(text)
					buf = buf .. tostring(text) .. "\n"
				end,
				flush = function() end,
				close = function()
					writeFile(path, buf)
				end,
			}
		end
		return nil
	end

	_G.fs = fs

	-- ---------- os ----------
	-- virtual clock and event queue; coroutines waiting for events or timers
	-- are resumed by the parallel scheduler below
	local fakeClock = 0
	local epochCounter = 0
	local eventQueue = {}
	local waiting = {} -- [co] = event filter or true (any)
	local sleeping = {} -- [co] = wake time
	local timers = 0
	local TERMINATED = "Terminated"

	local osShim = {}

	function osShim.epoch(unit)
		epochCounter = epochCounter + 1
		return 1700000000000 + epochCounter
	end

	function osShim.clock()
		return fakeClock
	end

	function osShim.time()
		return 1700000000
	end

	function osShim.date(fmt)
		return os.date and os.date(fmt) or "1970-01-01"
	end

	function osShim.getComputerID()
		return 0
	end

	function osShim.getComputerLabel()
		return "host-test"
	end

	function osShim.version()
		return "CraftOS 1.8"
	end

	function osShim.shutdown()
		error(TERMINATED, 0)
	end

	function osShim.reboot()
		error(TERMINATED, 0)
	end

	function osShim.queueEvent(name, ...)
		eventQueue[#eventQueue + 1] = { name, ... }
	end

	function osShim.startTimer()
		timers = timers + 1
		return timers
	end

	function osShim.cancelTimer() end

	function osShim.pullEventRaw(filter)
		local co = coroutine.running()
		if co and waiting then
			waiting[co] = filter or true
			return coroutine.yield("event")
		end
		while true do
			if #eventQueue > 0 then
				local ev = table.remove(eventQueue, 1)
				if not filter or ev[1] == filter then
					return table.unpack(ev)
				end
			else
				error("host shim: event queue empty (would block)", 0)
			end
		end
	end

	function osShim.pullEvent(filter)
		return osShim.pullEventRaw(filter)
	end

	function osShim.run(env, path, ...)
		local data = readFile(path)
		if data == nil then
			return false
		end
		local fn, err = load(data, "@" .. path, "t", env)
		if not fn then
			error(err, 0)
		end
		fn(...)
		return true
	end

	_G.os = setmetatable(osShim, { __index = os or {} })

	function _G.sleep(n)
		local co = coroutine.running()
		if co and waiting then
			sleeping[co] = fakeClock + (tonumber(n) or 0)
			return coroutine.yield("timer")
		end
		fakeClock = fakeClock + (tonumber(n) or 0)
	end

	-- ---------- textutils ----------
	local textutils = {}

	local function serializeValue(v, indent)
		local t = type(v)
		if t == "number" or t == "boolean" then
			return tostring(v)
		elseif t == "string" then
			return string.format("%q", v)
		elseif t == "table" then
			local keys = {}
			for k in pairs(v) do
				keys[#keys + 1] = k
			end
			table.sort(keys, function(a, b)
				if type(a) == type(b) then
					return tostring(a) < tostring(b)
				end
				return type(a) < type(b)
			end)
			local parts = { "{" }
			for _, k in ipairs(keys) do
				parts[#parts + 1] = string.rep("\t", indent + 1)
					.. "[" .. serializeValue(k, indent + 1) .. "] = "
					.. serializeValue(v[k], indent + 1) .. ","
			end
			parts[#parts + 1] = string.rep("\t", indent) .. "}"
			return table.concat(parts, "\n")
		end
		return "nil"
	end

	function textutils.serialize(v)
		return serializeValue(v, 0)
	end

	function textutils.unserialize(data)
		if type(data) ~= "string" then
			return nil
		end
		local fn = load("return " .. data, "=unserialize", "t", {})
		if not fn then
			return nil
		end
		local ok, value = pcall(fn)
		if ok and type(value) == "table" then
			return value
		end
		return nil
	end

	-- CC:Tweaked textutils.date; the installer stamps its log with it
	function textutils.date(fmt)
		local ok, value = pcall(os.date, fmt or "%Y-%m-%d %H:%M:%S", os.time())
		if ok and type(value) == "string" then
			return value
		end
		return "1970-01-01 00:00:00"
	end

	function textutils.formatTime(t, b24)
		local hour = math.floor(t) % 24
		local minute = math.floor((t % 1) * 60)
		if b24 then
			return string.format("%02d:%02d", hour, minute)
		end
		local suffix = hour < 12 and "AM" or "PM"
		local h12 = hour % 12
		if h12 == 0 then
			h12 = 12
		end
		return string.format("%d:%02d %s", h12, minute, suffix)
	end

	_G.textutils = textutils

	-- ---------- colors ----------
	local colors = {
		white = 0x1, orange = 0x2, magenta = 0x4, lightBlue = 0x8,
		yellow = 0x10, lime = 0x20, pink = 0x40, gray = 0x80,
		lightGray = 0x100, cyan = 0x200, purple = 0x400, blue = 0x800,
		brown = 0x1000, green = 0x2000, red = 0x4000, black = 0x8000,
	}
	for i = 0, 15 do
		colors[2 ^ i] = 2 ^ i
	end
	function colors.toBlit(color)
		for i = 0, 15 do
			if color == 2 ^ i then
				return string.format("%x", i)
			end
		end
		return "0"
	end
	_G.colors = colors

	-- ---------- keys ----------
	-- Codes mirror the CC:Tweaked keys API (see CC-tweaked/rom/apis/keys.lua):
	-- F1-F12 are 290-301 and the modifiers live at 340-346, so the two ranges
	-- never overlap. Getting this wrong makes desktop shortcuts behave
	-- differently on the real platform than they do here.
	local keys = {
		enter = 257, tab = 258, backspace = 259, space = 32,
		up = 265, right = 262, down = 264, left = 263,
		home = 268, ["end"] = 269, pageUp = 266, pageDown = 267,
		insert = 260, delete = 261,
		capsLock = 280, scrollLock = 281, numLock = 282,
		printScreen = 283, pause = 284,
		leftShift = 340, leftCtrl = 341, leftAlt = 342, leftSuper = 343,
		rightShift = 344, rightCtrl = 345, rightAlt = 346, menu = 348,
	}
	for i = 0, 9 do
		keys["numPad" .. i] = 320 + i
	end
	for i = 1, 25 do
		keys["f" .. i] = 289 + i
	end
	for i = string.byte("a"), string.byte("z") do
		keys[string.char(i)] = i
	end
	for i = string.byte("0"), string.byte("9") do
		keys[string.char(i)] = i
	end
	_G.keys = keys

	-- ---------- term ----------
	local function makeTerm(width, height)
		local t = {
			_w = width, _h = height,
			_x = 1, _y = 1,
			_fg = colors.white, _bg = colors.black,
			_visible = true, _blink = false,
			_lines = {},
		}
		for y = 1, height do
			t._lines[y] = string.rep(" ", width)
		end
		local function clamp()
			t._x = math.max(1, math.min(t._x, t._w))
			t._y = math.max(1, math.min(t._y, t._h))
		end
		local api = {}
		function api.getSize()
			return t._w, t._h
		end
		function api.setCursorPos(x, y)
			t._x, t._y = x, y
			clamp()
		end
		function api.getCursorPos()
			return t._x, t._y
		end
		function api.setCursorBlink(b)
			t._blink = b and true or false
		end
		function api.getCursorBlink()
			return t._blink
		end
		function api.clear()
			for y = 1, t._h do
				t._lines[y] = string.rep(" ", t._w)
			end
		end
		function api.clearLine()
			t._lines[t._y] = string.rep(" ", t._w)
		end
		function api.write(text)
			text = tostring(text or "")
			for i = 1, #text do
				local ch = text:sub(i, i)
				if t._x > t._w then
					t._x = 1
					t._y = t._y + 1
					if t._y > t._h then
						t._y = t._h
					end
					t._lines[t._y] = string.rep(" ", t._w)
				end
				local line = t._lines[t._y]
				t._lines[t._y] = line:sub(1, t._x - 1) .. ch .. line:sub(t._x + 1)
				t._x = t._x + 1
			end
		end
		function api.blit(text, fg, bg)
			api.write(text)
		end
		function api.scroll(n)
			for _ = 1, n do
				table.remove(t._lines, 1)
				t._lines[t._h] = string.rep(" ", t._w)
			end
		end
		function api.setTextColor(c)
			t._fg = c
		end
		function api.setBackgroundColor(c)
			t._bg = c
		end
		api.setTextColour = api.setTextColor
		api.setBackgroundColour = api.setBackgroundColor
		function api.getTextColor()
			return t._fg
		end
		function api.getBackgroundColor()
			return t._bg
		end
		api.getTextColour = api.getTextColor
		api.getBackgroundColour = api.getBackgroundColor
		function api.isColor()
			return true
		end
		api.isColour = api.isColor
		function api.setPaletteColor() end
		api.setPaletteColour = api.setPaletteColor
		function api.getPaletteColor()
			return 0
		end
		api.getPaletteColour = api.getPaletteColor
		function api.setVisible(v)
			t._visible = v and true or false
		end
		function api.redraw() end
		function api.getLine(y)
			return t._lines[y]
		end
		-- non-CC helper for host assertions
		function api.dump()
			return table.concat(t._lines, "\n")
		end
		return api
	end

	local nativeTerm = makeTerm(51, 19)
	local currentTerm = nativeTerm

	_G.term = setmetatable({
		redirect = function(target)
			local old = currentTerm
			currentTerm = target or nativeTerm
			return old
		end,
		current = function()
			return currentTerm
		end,
		native = function()
			return nativeTerm
		end,
	}, {
		__index = function(_, k)
			return currentTerm[k]
		end,
	})

	_G.window = {
		create = function(parent, x, y, w, h)
			local win = makeTerm(w, h)
			win.reposition = function(nx, ny, nw, nh)
				-- buffer width changes are ignored; CloverOS only resizes
				-- frames after checking the screen clamp
			end
			return win
		end,
	}

	-- ---------- shell ----------
	local shellDir = "/"
	_G.shell = {
		dir = function()
			return shellDir
		end,
		setDir = function(p)
			shellDir = normalize(p)
		end,
		resolve = function(p)
			return normalize(p)
		end,
		resolvePath = function(p)
			return normalize(p)
		end,
		getRunningProgram = function()
			return "host"
		end,
		run = function(path, ...)
			return osShim.run(_G, path, ...)
		end,
		path = function()
			return { "/bin" }
		end,
	}

	-- ---------- peripheral ----------
	-- CC:Tweaked peripherals are userdata, so production code has to
	-- duck-type them (type(p.method) == "function") rather than compare
	-- type(p). The shim therefore hands back plain tables with the same
	-- method surface, which keeps that constraint honest under test.
	local hw = { attached = {} } -- name -> { type = ..., methods = {...} }

	local function peripheralProxy(name)
		local entry = hw.attached[name]
		if not entry then
			return nil
		end
		return setmetatable({}, {
			__index = function(_, key)
				local fn = entry.methods[key]
				if type(fn) == "function" then
					return function(...)
						return fn(...)
					end
				end
				return entry.methods[key]
			end,
			__tostring = function()
				return entry.type .. "(" .. name .. ")"
			end,
		})
	end

	_G.peripheral = {
		getNames = function()
			local names = {}
			for name in pairs(hw.attached) do
				names[#names + 1] = name
			end
			table.sort(names)
			return names
		end,
		getType = function(name)
			local entry = hw.attached[name]
			return entry and entry.type or nil
		end,
		find = function(ptype)
			for name, entry in pairs(hw.attached) do
				if entry.type == ptype then
					return peripheralProxy(name)
				end
			end
			return nil
		end,
		isPresent = function(name)
			return hw.attached[name] ~= nil
		end,
		hasType = function(ptype)
			for _, entry in pairs(hw.attached) do
				if entry.type == ptype then
					return true
				end
			end
			return false
		end,
	}

	-- ---------- network ----------
	-- http.get is the only way CloverOS reaches the network on CC:Tweaked.
	-- Tests script replies through hostShim.http; an unscripted URL fails
	-- exactly as an offline computer would.
	local httpState = { replies = {}, failAll = false }

	local function httpHandle(body, headers)
		return {
			readAll = function()
				return body
			end,
			readLine = function()
				return nil
			end,
			close = function() end,
			getResponseHeaders = function()
				return headers or {}
			end,
			getResponseCode = function()
				return (headers and headers.code) or 200
			end,
		}
	end

	_G.http = {
		get = function(url, headers)
			if httpState.failAll then
				return nil, "Connection refused"
			end
			local reply = httpState.replies[url]
			if reply == nil then
				return nil, "Could not connect"
			end
			return httpHandle(reply.body, reply.headers)
		end,
		post = function(url, body, headers)
			local reply = httpState.replies[url]
			if reply == nil then
				return nil, "Could not connect"
			end
			return httpHandle(reply.body, reply.headers)
		end,
		checkURL = function(url)
			return httpState.replies[url] ~= nil
		end,
	}

	-- CC:Tweaked exposes ping as a global, not a table
	_G.ping = function(host, count)
		if type(host) ~= "string" or host == "" then
			error("bad argument #1 to 'ping' (string expected)", 2)
		end
		local reply = httpState.replies["ping:" .. host]
		if reply == nil then
			error("Cannot resolve " .. host, 2)
		end
		local times = reply.times or { 12, 14, 15 }
		local out = {}
		for i = 1, (tonumber(count) or 4) do
			out[i] = times[((i - 1) % #times) + 1]
		end
		return out
	end

	-- ---------- parallel ----------
	-- cooperative scheduler: event waiters are resumed with queued events,
	-- sleepers resume at the next virtual timestamp
	local function resumeCo(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			if err == TERMINATED then
				error(err, 0)
			end
			error(debug.traceback(co, tostring(err)), 0)
		end
	end

	local function scheduler(...)
		local fns = {...}
		local cos = {}
		for i, fn in ipairs(fns) do
			cos[i] = coroutine.create(fn)
		end
		while true do
			local progressed = false
			for i, co in ipairs(cos) do
				if coroutine.status(co) ~= "dead" and not waiting[co] and not sleeping[co] then
					progressed = true
					resumeCo(co)
				end
			end
			for i, co in ipairs(cos) do
				if coroutine.status(co) == "dead" then
					return i
				end
			end
			-- deliver pending events to waiters (CC drops non-matching ones
			-- only when no waiter wants them; here each waiter filters)
			for i, co in ipairs(cos) do
				local want = waiting[co]
				if want then
					for qi = 1, #eventQueue do
						local ev = eventQueue[qi]
						if want == true or ev[1] == want then
							table.remove(eventQueue, qi)
							waiting[co] = nil
							progressed = true
							resumeCo(co, table.unpack(ev))
							break
						end
					end
				end
			end
			if not progressed then
				if next(sleeping) then
					-- advance virtual time to the earliest alarm
					local soonest = nil
					for _, at in pairs(sleeping) do
						if not soonest or at < soonest then
							soonest = at
						end
					end
					fakeClock = soonest
					for co, at in pairs(sleeping) do
						if at <= fakeClock then
							sleeping[co] = nil
						end
					end
				else
					error("host shim: deadlock (all coroutines waiting, no events)", 0)
				end
			end
		end
	end

	_G.parallel = {
		waitForAny = scheduler,
		waitForAll = function(...)
			scheduler(...)
		end,
	}

	-- ---------- console helpers ----------
	-- write/print feed the console term like the real platform (so
	-- host-side checks can inspect the visible console) and mirror to
	-- stdout for the test log. All console output is also accumulated in
	-- a log that dumpTerm includes: the host-side "console log" the boot
	-- tests grep. When term is redirected to a window the globals stay
	-- out of the buffer; apps own their window buffers.
	local consoleLog = {}
	local function consoleWrite(text)
		text = tostring(text or "")
		io.write(text)
		consoleLog[#consoleLog + 1] = text
		if currentTerm ~= nativeTerm then
			return
		end
		local t = currentTerm
		local pos = 1
		while true do
			local nl = text:find("\n", pos, true)
			local seg = nl and text:sub(pos, nl - 1) or text:sub(pos)
			if #seg > 0 then
				t.write(seg)
			end
			if not nl then
				break
			end
			local _, y = t.getCursorPos()
			local _, h = t.getSize()
			y = y + 1
			if y > h then
				t.scroll(1)
				y = h
			end
			t.setCursorPos(1, y)
			pos = nl + 1
		end
	end

	_G.write = consoleWrite

	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		consoleWrite(table.concat(parts, "\t") .. "\n")
	end

	_G.printError = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		io.stderr:write(table.concat(parts, " ") .. "\n")
	end

	-- read() consumes char/key events like the real platform, so scripted
	-- drivers can type into any prompt
	_G.read = function(replace, history, complete)
		local buf = ""
		while true do
			local ev = { osShim.pullEventRaw() }
			if ev[1] == "char" then
				buf = buf .. tostring(ev[2])
			elseif ev[1] == "paste" then
				buf = buf .. tostring(ev[2])
			elseif ev[1] == "key" and ev[2] == keys.enter then
				return buf
			elseif ev[1] == "key" and ev[2] == keys.backspace then
				buf = buf:sub(1, -2)
			elseif ev[1] == "terminate" then
				error(TERMINATED, 0)
			end
		end
	end
	_G.hostShim = {
		queueInput = function(line)
			for i = 1, #line do
				osShim.queueEvent("char", line:sub(i, i))
			end
			osShim.queueEvent("key", keys.enter)
		end,
		readFile = readFile,
		writeFile = writeFile,
		exists = fs.exists,
		-- hardware: attach/detach models CC:Tweaked hotplug
		attach = function(name, ptype, methods)
			hw.attached[name] = { type = ptype, methods = methods or {} }
			osShim.queueEvent("peripheral", name)
		end,
		detach = function(name)
			local entry = hw.attached[name]
			hw.attached[name] = nil
			if entry then
				osShim.queueEvent("peripheral_detach", name)
			end
		end,
		hardware = function()
			local list = {}
			for name, entry in pairs(hw.attached) do
				list[#list + 1] = { name = name, type = entry.type }
			end
			table.sort(list, function(a, b)
				return a.name < b.name
			end)
			return list
		end,
		http = {
			reply = function(url, body, headers)
				httpState.replies[url] = { body = body, headers = headers }
			end,
			latency = function(host, times)
				httpState.replies["ping:" .. host] = { times = times }
			end,
			offline = function(offline)
				httpState.failAll = offline and true or false
			end,
		},
		isShutdown = function(err)
			return err == TERMINATED
		end,
		dumpTerm = function()
			return nativeTerm.dump() .. "\n" .. table.concat(consoleLog)
		end,
	}

	-- dofile/loadfile read from the virtual filesystem
	_G.dofile = function(path)
		local data = readFile(path)
		if data == nil then
			error("cannot open " .. tostring(path), 0)
		end
		local fn, err = load(data, "@" .. path, "t", _G)
		if not fn then
			error(err, 0)
		end
		return fn()
	end

	_G.loadfile = function(path)
		local data = readFile(path)
		if data == nil then
			return nil, "cannot open " .. tostring(path)
		end
		return load(data, "@" .. path, "t", _G)
	end

	-- ---------- hash ----------
	-- CC:Tweaked ships a native `hash` library and runtime/hash.lua uses it
	-- when present. The host harness models the same API so the production
	-- path is the one under test; the portable path stays reachable through
	-- hash.pureSha256hex. Only registered when the runner injected a real
	-- digest function (see run.js), so pure-Lua interpreters still work.
	if type(__nativeSha256) == "function" then
		_G.hash = { sha256 = __nativeSha256 }
	end

	-- seed the virtual filesystem: /src holds the repository verbatim
	for rel, content in pairs(repoFiles) do
		writeFile("/src/" .. rel, content)
	end

	return _G.hostShim
end

return M
