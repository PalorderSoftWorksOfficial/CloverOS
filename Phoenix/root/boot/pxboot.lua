if not (fs or term or os.pullEvent) then
	error("This program must be run from CraftOS.")
end
local a = require("cc.expect")
if not getmetatable(a) then
	setmetatable(a, {
		__call = function(self, ...)
			return self.expect(...)
		end,
	})
elseif not getmetatable(a).__call then
	getmetatable(a).__call = function(self, ...)
		return self.expect(...)
	end
end
local b = {}
local c = {}
local d = {}
local e = {}
local f = {}
local g
local function h(i, ...)
	local j = _G.dofile
	local k = table.pack(...)
	local l = {
		bit32 = true,
		bit = true,
		ccemux = true,
		config = true,
		coroutine = true,
		debug = true,
		ffi = true,
		fs = true,
		http = true,
		io = true,
		jit = true,
		mounter = true,
		os = true,
		periphemu = true,
		peripheral = true,
		redstone = true,
		rs = true,
		term = true,
		utf8 = true,
		_HOST = true,
		_CC_DEFAULT_SETTINGS = true,
		_CC_DISABLE_LUA51_FEATURES = true,
		_VERSION = true,
		assert = true,
		collectgarbage = true,
		error = true,
		gcinfo = true,
		getfenv = true,
		getmetatable = true,
		ipairs = true,
		load = true,
		loadstring = true,
		math = true,
		newproxy = true,
		next = true,
		pairs = true,
		pcall = true,
		rawequal = true,
		rawget = true,
		rawlen = true,
		rawset = true,
		select = true,
		setfenv = true,
		setmetatable = true,
		string = true,
		table = true,
		tonumber = true,
		tostring = true,
		type = true,
		unpack = true,
		xpcall = true,
		turtle = true,
		pocket = true,
		commands = true,
		_G = true,
		sound = true,
	}
	local m = {}
	for n in pairs(_G) do
		if not l[n] and not f[n] then
			table.insert(m, n)
		end
	end
	for o, n in ipairs(m) do
		_G[n] = nil
	end
	local p = g or _G.term.native()
	for o, q in ipairs({ "nativePaletteColor", "nativePaletteColour", "screenshot" }) do
		p[q] = _G.term[q]
	end
	_G.term = p
	_G.http.checkURL = _G.http.checkURLAsync
	_G.http.websocket = _G.http.websocketAsync
	if _G.commands then
		_G.commands = _G.commands.native
	end
	if _G.turtle then
		_G.turtle.native, _G.turtle.craft = nil
	end
	local r = {
		os = { "version", "pullEventRaw", "pullEvent", "run", "loadAPI", "unloadAPI", "sleep" },
		http = {
			"get",
			"post",
			"put",
			"delete",
			"patch",
			"options",
			"head",
			"trace",
			"listen",
			"checkURLAsync",
			"websocketAsync",
		},
		fs = { "complete", "isDriveRoot" },
	}
	for n, s in pairs(r) do
		for o, t in ipairs(s) do
			_G[n][t] = nil
		end
	end
	local u = error
	_G.error = function() end
	_G.term.redirect = function() end
	function _G.term.native()
		_G.term.native = nil
		_G.term.redirect = nil
		_G.error = u
		term.setBackgroundColor(32768)
		term.setTextColor(1)
		term.setCursorPos(1, 1)
		term.setCursorBlink(true)
		term.clear()
		local v
		if type(i) == "function" then
			v = i
		else
			local w = fs.open(i, "r")
			if w == nil then
				term.setCursorBlink(false)
				term.setTextColor(16384)
				term.write("Could not find kernel. pxboot cannot continue.")
				term.setCursorPos(1, 2)
				term.write("Press any key to continue")
				coroutine.yield("key")
				os.shutdown()
			end
			local x
			v, x = loadstring(w.readAll(), "=kernel")
			w.close()
			if v == nil then
				term.setCursorBlink(false)
				term.setTextColor(16384)
				term.write("Could not load kernel. pxboot cannot continue.")
				term.setCursorPos(1, 2)
				term.write(x)
				term.setCursorPos(1, 3)
				term.write("Press any key to continue")
				coroutine.yield("key")
				os.shutdown()
			end
		end
		setfenv(v, _G)
		local y = os.shutdown
		os.shutdown = function()
			os.shutdown = y
			return v(table.unpack(k, 1, k.n))
		end
	end
	if debug then
		local function z(A, B, C, D)
			local E, F, G = 1, debug.getupvalue(A[B], D)
			while F ~= C and not (F == nil and E > 1) do
				F, G = debug.getupvalue(A[B], E)
				E = E + 1
			end
			A[B] = G or A[B]
		end
		z(_G, "loadstring", "nativeloadstring", 1)
		z(_G, "load", "nativeload", 5)
		z(http, "request", "nativeHTTPRequest", 3)
		z(os, "shutdown", "nativeShutdown", 1)
		z(os, "reboot", "nativeReboot", 1)
		if turtle then
			z(turtle, "equipLeft", "v", 1)
			z(turtle, "equipRight", "v", 1)
		end
		do
			local E, F, G = 1, debug.getupvalue(peripheral.isPresent, 2)
			while F ~= "native" and F ~= nil do
				F, G = debug.getupvalue(peripheral.isPresent, E)
				E = E + 1
			end
			_G.peripheral = G or peripheral
		end
		if debug.getupvalue(j, 2) == "status" then
			local o, H = debug.getupvalue(j, 2)
			o, _G.discord = debug.getupvalue(H, 4)
		end
	end
	coroutine.yield()
end
function e.kernel(m)
	d.fn = h
	d.args = { m.path }
end
function e.chainloader(m)
	d.fn = shell and shell.run or function(i, ...)
		os.run({}, i, ...)
	end
	d.args = { m.path }
end
function e.craftos(m)
	d.fn = function()
		term.setTextColor(colors.yellow)
		print(os.version())
		term.setTextColor(colors.white)
		if settings.get("motd.enable") then
			if shell then
				shell.run("motd")
			else
				os.run({}, "/rom/programs/motd.lua")
			end
		end
	end
	d.args = {}
end
function e.args(m)
	if not d.args then
		error("config.lua:" .. m.line .. ": args command must come after boot type", 0)
	end
	for E = 1, #m.args do
		d.args[#d.args + 1] = m.args[E]
	end
end
function e.global(m)
	_G[m.key] = m.value
	f[m.key] = true
end
function e.monitor(m)
	if peripheral.hasType then
		assert(
			peripheral.hasType(m.name, "monitor"),
			"peripheral '" .. m.name .. "' does not exist or is not a monitor"
		)
	else
		assert(
			peripheral.getType(m.name) == "monitor",
			"peripheral '" .. m.name .. "' does not exist or is not a monitor"
		)
	end
	g = peripheral.wrap(m.name)
	term.redirect(g)
end
function e.insmod(m)
	local i
	if m.name:match("^/") then
		i = m.name
	elseif m.name:find("[/%.]") then
		i = fs.combine(shell and fs.getDir(shell.getRunningProgram()) or "pxboot", m.name)
	else
		i = fs.combine(shell and fs.getDir(shell.getRunningProgram()) or "pxboot", "modules/" .. m.name .. ".lua")
	end
	assert(
		loadfile(
			i,
			nil,
			setmetatable({ entries = b, bootcfg = d, cmds = e, userGlobals = f, unbios = h }, { __index = _ENV })
		)
	)(m.args, i)
end
local function I(J)
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
	term.clear()
	term.setCursorPos(1, 1)
	for E = 0, 15 do
		term.setPaletteColor(2 ^ E, term.nativePaletteColor(2 ^ E))
	end
	for o, s in ipairs(J.commands) do
		local K, x
		if type(s) == "function" then
			K, x = pcall(s)
		else
			K, x = pcall(e[s.cmd], s)
		end
		if not K then
			d = {}
			printError("Could not run boot script: " .. x)
			print("Press any key to continue.")
			os.pullEventRaw("key")
			return false
		end
	end
	if not d.fn then
		d = {}
		printError("Could not run boot script: missing boot type command")
		print("Press any key to continue.")
		os.pullEventRaw("key")
		return false
	end
	d.fn(table.unpack(d.args))
	return true
end
local L
local M = setmetatable({
	title = "Phoenix pxboot",
	titlecolor = colors.white,
	backgroundcolor = colors.black,
	textcolor = colors.white,
	boxcolor = colors.white,
	boxbackground = colors.black,
	selectcolor = colors.white,
	selecttext = colors.black,
	background = nil,
	defaultentry = nil,
	timeout = 30,
	menuentry = function(C)
		a(1, C, "string")
		return function(J)
			a(2, J, "table")
			local N = 1
			for E, s in pairs(J) do
				if type(E) == "number" then
					N = math.max(E, N)
				end
			end
			local O = { name = C, commands = {} }
			for E = 1, N do
				local P = J[E]
				if type(P) ~= "table" and type(P) ~= "function" or not P.cmd then
					error(
						"bad command entry #" .. E .. (P == nil and " (unknown command)" or " (missing arguments)"),
						2
					)
				end
				if type(P) == "function" then
					O.commands[#O.commands + 1] = P
				elseif P.cmd == "description" then
					O.description = P.text
				elseif e[P.cmd] then
					O.commands[#O.commands + 1] = P
				else
					error("bad command entry #" .. E .. " (unknown command " .. P.cmd .. ")", 2)
				end
			end
			b[#b + 1] = O
			c[C] = O
		end
	end,
	include = function(i)
		a(1, i, "string")
		for o, s in ipairs(fs.find(fs.combine(L, i))) do
			repeat
				local v, x = loadfile(s, "t", getfenv(2))
				if not v then
					printError("Could not load config file: " .. x)
					print("Press any key to continue...")
					os.pullEvent("key")
					break
				end
				local Q = L
				L = fs.getDir(s)
				local K, x = pcall(v)
				L = Q
				if not K then
					printError("Failed to execute config file: " .. x)
					print("Press any key to continue...")
					os.pullEvent("key")
					break
				end
			until true
		end
	end,
	description = function(R)
		a(1, R, "string")
		return { cmd = "description", text = R, line = debug.getinfo(2, "l").currentline }
	end,
	kernel = function(i)
		a(1, i, "string")
		return { cmd = "kernel", path = i, line = debug.getinfo(2, "l").currentline }
	end,
	chainloader = function(i)
		a(1, i, "string")
		return { cmd = "chainloader", path = i, line = debug.getinfo(2, "l").currentline }
	end,
	args = function(S)
		a(1, S, "string", "table")
		if type(S) == "table" then
			return { cmd = "args", args = S, line = debug.getinfo(2, "l").currentline }
		else
			local m = { "" }
			local T
			for P in S:gmatch(".") do
				if T then
					if P == T then
						T = nil
					else
						m[#m] = m[#m] .. P
					end
				elseif P == '"' or P == "'" then
					T = P
				elseif P == " " then
					m[#m + 1] = ""
				else
					m[#m] = m[#m] .. P
				end
			end
			local N = 2
			return setmetatable({ cmd = "args", args = m, line = debug.getinfo(2, "l").currentline }, {
				__call = function(self, U)
					a(N, U, "string")
					N = N + 1
					local m = self.args
					local T
					m[#m + 1] = ""
					for P in U:gmatch(".") do
						if T then
							if P == T then
								T = nil
							else
								m[#m] = m[#m] .. P
							end
						elseif P == '"' or P == "'" then
							T = P
						elseif P == " " then
							m[#m + 1] = ""
						else
							m[#m] = m[#m] .. P
						end
					end
					return self
				end,
			})
		end
	end,
	craftos = { cmd = "craftos" },
	global = function(F)
		return function(G)
			return { cmd = "global", key = F, value = G }
		end
	end,
	monitor = function(C)
		return { cmd = "monitor", name = C }
	end,
	insmod = function(C)
		a(1, C, "string")
		return setmetatable({ cmd = "insmod", name = C, line = debug.getinfo(2, "l").currentline }, {
			__call = function(self, S)
				a(2, S, "table")
				self.args = S
				setmetatable(self, nil)
				return self
			end,
		})
	end,
}, { __index = _ENV })
term.clear()
term.setCursorPos(1, 1)
repeat
	local v, x = loadfile(
		shell and fs.combine(fs.getDir(shell.getRunningProgram()), "config.lua") or "pxboot/config.lua",
		"t",
		M
	)
	if not v then
		printError("Could not load config file: " .. x)
		print("Press any key to continue...")
		os.pullEvent("key")
		break
	end
	L = shell and fs.getDir(shell.getRunningProgram()) or "pxboot"
	local K, x = pcall(v)
	L = nil
	if not K then
		printError("Failed to execute config file: " .. x)
		print("Press any key to continue...")
		os.pullEvent("key")
		break
	end
until true
local function V() end
if #b == 0 then
	return V()
end
local function W(N)
	return ("0123456789abcdef"):sub(N, N)
end
local X, Y = term.getSize()
local Z = Y - 11
local _ = window.create(term.current(), 2, 4, X - 2, Y - 9)
local a0 = window.create(_, 2, 2, X - 4, Z)
term.setBackgroundColor(M.backgroundcolor)
term.clear()
_.setBackgroundColor(M.boxbackground or M.backgroundcolor)
_.clear()
a0.setBackgroundColor(M.boxbackground or M.backgroundcolor)
a0.clear()
local a1, a2 = 1, 1
if M.defaultentry then
	for E = 1, #b do
		if b[E].name == M.defaultentry then
			a1 = E
			break
		end
	end
	if M.timeout == 0 and I(b[a1]) then
		return
	end
end
local function a3()
	a0.setVisible(false)
	a0.setBackgroundColor(M.boxbackground or M.backgroundcolor)
	a0.clear()
	for E = a2, a2 + Z - 1 do
		local a4 = b[E]
		if not a4 then
			break
		end
		a0.setCursorPos(2, E - a2 + 1)
		if E == a1 then
			a0.setBackgroundColor(M.selectcolor)
			a0.setTextColor(M.selecttext)
		else
			a0.setBackgroundColor(M.boxbackground or M.backgroundcolor)
			a0.setTextColor(M.textcolor)
		end
		a0.clearLine()
		a0.write(#a4.name > X - 6 and a4.name:sub(1, X - 9) .. "..." or a4.name)
		if E == a1 and M.timeout then
			local a5 = tostring(M.timeout)
			a0.setCursorPos(X - 4 - #a5, E - a2 + 1)
			a0.write(a5)
			a0.setCursorPos(2, E - a2 + 1)
		end
	end
	a0.setVisible(true)
	term.setCursorPos(5, Y - 5)
	term.clearLine()
	term.setTextColor(M.titlecolor)
	term.write(b[a1].description or "")
end
local function a6()
	local a7, a8 =
		W(select(2, math.frexp(M.boxbackground or M.backgroundcolor))),
		W(select(2, math.frexp(M.boxcolor or M.textcolor)))
	_.setTextColor(M.boxcolor or M.textcolor)
	_.setCursorPos(1, 1)
	_.write("\x9C" .. ("\x8C"):rep(X - 4))
	_.blit("\x93", a7, a8)
	for a9 = 2, Y - 10 do
		_.setCursorPos(1, a9)
		_.blit("\x95", a8, a7)
		_.setCursorPos(X - 2, a9)
		_.blit("\x95", a7, a8)
	end
	_.setCursorPos(1, Y - 9)
	_.setBackgroundColor(M.boxbackground or M.backgroundcolor)
	_.setTextColor(M.boxcolor or M.textcolor)
	_.write("\x8D" .. ("\x8C"):rep(X - 4) .. "\x8E")
	term.setCursorPos((X - #M.title) / 2, 2)
	term.setTextColor(M.titlecolor or M.textcolor)
	term.write(M.title)
	term.setCursorPos(5, Y - 3)
	term.write("Use the \x18 and \x19 keys to select.")
	term.setCursorPos(5, Y - 2)
	term.write("Press enter to boot the selected OS.")
	term.setCursorPos(5, Y - 1)
	term.write("'c' for shell, 'e' to edit.")
	a3()
end
a6()
local aa = M.defaultentry and M.timeout and os.startTimer(1)
while true do
	local ab = { coroutine.yield() }
	if ab[1] == "timer" and ab[2] == aa then
		M.timeout = M.timeout - 1
		if M.timeout == 0 then
			if I(c[M.defaultentry]) then
				return
			end
		end
		a3()
		aa = os.startTimer(1)
	elseif ab[1] == "key" then
		if aa then
			os.cancelTimer(aa)
			M.timeout, aa = nil
			a3()
		end
		if (ab[2] == keys.down or ab[2] == keys.numPad2) and a1 < #b then
			a1 = a1 + 1
			if a1 > a2 + Z - 1 then
				a2 = a2 + 1
			end
			a3()
		elseif (ab[2] == keys.up or ab[2] == keys.numPad8) and a1 > 1 then
			a1 = a1 - 1
			if a1 < a2 then
				a2 = a2 - 1
			end
			a3()
		elseif ab[2] == keys.enter then
			if I(b[a1]) then
				return
			end
		elseif ab[2] == keys.c then
			V()
			a6()
		end
	elseif ab[1] == "terminate" then
		break
	end
end
