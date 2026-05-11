-- CloverOS kernel loader
-- Copyright (c) 2026 PalorderSoftWorksOfficial
-- This file locates CloverOS components and starts the OS.
---@diagnostic disable: undefined-global
-- luacheck: globals fs shell colors printError os term peripheral

local function findFile(fileName)
	for i = 0, 99 do
		local d = "/disk" .. (i == 0 and "" or i)
		local p = d .. "/" .. fileName
		if fs.exists(p) then
			return p
		end
	end

	if fs.exists("/" .. fileName) then
		return "/" .. fileName
	end

	return nil
end

local path = findFile("CloverOS_API.lua")
if not path then
	error("CloverOS_API.lua not found")
end

local path2 = findFile("etc/filesystem/main.lua")

local API = dofile(path)
local API2 = path2 and dofile(path2) or {}

local function mergeTables(t1, t2)
	for k, v in pairs(t2) do
		if type(v) == "table" and type(t1[k]) == "table" then
			mergeTables(t1[k], v)
		else
			t1[k] = v
		end
	end
	return t1
end

mergeTables(API, API2)

local osAPIFunc = {
	version = function()
		return "CloverOS v1.0.0"
	end,
	author = function()
		return "CloverOS Team"
	end,
	runInstaller = function()
		shell.run("wget", "https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua", "netinstall.lua")
		shell.run("netinstall.lua")
	end,
}

for k, v in pairs(osAPIFunc) do
	API[k] = v
end

local fsPath = findFile("etc/filesystem/main.lua")
if fsPath then
	local ok, fsModule = pcall(dofile, fsPath)
	if ok and type(fsModule) == "table" then
		API.filesystem = fsModule
	end
end

local function safeFindOS(fileName)
	local ok, result = pcall(function()
		for i = 0, 99 do
			local d = "/disk" .. (i == 0 and "" or i)
			local p = d .. "/" .. fileName
			if fs.exists(p) then
				return p
			end
		end
		if fs.exists("/" .. fileName) then
			return "/" .. fileName
		end
		return nil
	end)

	if ok then
		return result or "/CloverOS_OS.lua"
	else
		printError("Error finding OS: " .. tostring(result))
		return "/CloverOS_OS.lua"
	end
end
local kernel = {
	_name = "CloverOS Kernel",
	_version = "1.0.0",
	_build = "2026-05-11",
	_startedAt = os.clock(),
	_services = {},
	_drivers = {},
	_state = {
		booted = false,
		shutdownRequested = false,
		rebootRequested = false,
	},
}

function kernel.version()
	return kernel._version
end

function kernel.name()
	return kernel._name
end

function kernel.build()
	return kernel._build
end

function kernel.author()
	return "CloverOS Team"
end

function kernel.uptime()
	return os.clock() - kernel._startedAt
end

function kernel.time()
	return os.time()
end

function kernel.date(format, time)
	return os.date(format or "%c", time)
end

function kernel.epoch()
	return os.epoch("utc")
end

function kernel.sleep(seconds)
	return sleep(seconds)
end

function kernel.yield()
	os.queueEvent("kernel_yield")
	return os.pullEvent("kernel_yield")
end

function kernel.panic(message)
	error("[KERNEL PANIC] " .. tostring(message), 0)
end

function kernel.assert(condition, message)
	if not condition then
		kernel.panic(message or "assertion failed")
	end
	return condition
end

function kernel.try(fn, ...)
	local ok, result = pcall(fn, ...)
	return ok, result
end

function kernel.log(level, ...)
	local parts = { ... }
	for i = 1, #parts do
		parts[i] = tostring(parts[i])
	end
	local line = ("[%s] %s"):format(string.upper(tostring(level or "info")), table.concat(parts, " "))
	if print then
		print(line)
	else
		write(line .. "\n")
	end
	return line
end

function kernel.info(...)
	return kernel.log("info", ...)
end

function kernel.warn(...)
	return kernel.log("warn", ...)
end

if kernel.debug == nil then
	kernel.debug = {}
end

setmetatable(kernel.debug, {
	__call = function(_, ...)
		return kernel.log("debug", ...)
	end,
})

function kernel.error(...)
	return kernel.log("error", ...)
end

function kernel.queueEvent(name, ...)
	return os.queueEvent(name, ...)
end

function kernel.pullEvent(filter)
	return os.pullEvent(filter)
end

function kernel.pullEventRaw(filter)
	return os.pullEventRaw(filter)
end

function kernel.reboot()
	kernel._state.rebootRequested = true
	return os.reboot()
end

function kernel.shutdown()
	kernel._state.shutdownRequested = true
	return os.shutdown()
end

kernel.computer = {}

function kernel.computer.id()
	return os.getComputerID()
end

function kernel.computer.label()
	return os.getComputerLabel()
end

function kernel.computer.setLabel(label)
	return os.setComputerLabel(label)
end

function kernel.computer.version()
	return os.version()
end

function kernel.computer.isTurtle()
	return turtle ~= nil
end

function kernel.computer.isOn()
	return true
end

kernel.fs = {}

function kernel.fs.exists(path)
	return fs.exists(path)
end

function kernel.fs.isDir(path)
	return fs.isDir(path)
end

function kernel.fs.isReadOnly(path)
	return fs.isReadOnly(path)
end

function kernel.fs.list(path)
	return fs.list(path)
end

function kernel.fs.makeDir(path)
	return fs.makeDir(path)
end

function kernel.fs.delete(path)
	return fs.delete(path)
end

function kernel.fs.copy(from, to)
	return fs.copy(from, to)
end

function kernel.fs.move(from, to)
	return fs.move(from, to)
end

function kernel.fs.getSize(path)
	return fs.getSize(path)
end

function kernel.fs.getDrive(path)
	return fs.getDrive(path)
end

function kernel.fs.combine(...)
	return fs.combine(...)
end

function kernel.fs.getName(path)
	return fs.getName(path)
end

function kernel.fs.getDir(path)
	return fs.getDir(path)
end

function kernel.fs.open(path, mode)
	return fs.open(path, mode)
end

function kernel.fs.readAll(path)
	local h = fs.open(path, "r")
	if not h then
		return nil, "cannot open file for reading"
	end
	local data = h.readAll()
	h.close()
	return data
end

function kernel.fs.writeAll(path, data)
	local parent = fs.getDir(path)
	if parent and parent ~= "" and not fs.exists(parent) then
		fs.makeDir(parent)
	end

	local h = fs.open(path, "w")
	if not h then
		return nil, "cannot open file for writing"
	end
	h.write(tostring(data or ""))
	h.close()
	return true
end

function kernel.fs.appendAll(path, data)
	local h = fs.open(path, "a")
	if not h then
		return nil, "cannot open file for appending"
	end
	h.write(tostring(data or ""))
	h.close()
	return true
end

function kernel.fs.readLines(path)
	local h = fs.open(path, "r")
	if not h then
		return nil, "cannot open file for reading"
	end

	local lines = {}
	while true do
		local line = h.readLine()
		if line == nil then
			break
		end
		lines[#lines + 1] = line
	end

	h.close()
	return lines
end

function kernel.fs.isFile(path)
	return fs.exists(path) and not fs.isDir(path)
end

kernel.path = {}

function kernel.path.resolve(path)
	return shell.resolve(path)
end

function kernel.path.program(name)
	return shell.resolveProgram(name)
end

function kernel.path.current()
	return shell.dir()
end

function kernel.path.setCurrent(path)
	return shell.setDir(path)
end

function kernel.path.shellPath()
	return shell.path()
end

function kernel.path.setShellPath(path)
	return shell.setPath(path)
end

function kernel.path.split(path)
	return fs.getDir(path), fs.getName(path)
end

function kernel.path.basename(path)
	return fs.getName(path)
end

function kernel.path.dirname(path)
	return fs.getDir(path)
end

function kernel.path.extension(path)
	local name = fs.getName(path)
	return name:match("%.([^.]+)$")
end

function kernel.path.withExtension(path, ext)
	local dir = fs.getDir(path)
	local base = fs.getName(path):gsub("%.[^.]+$", "")
	local name = base .. "." .. tostring(ext or "")
	if dir == "" then
		return name
	end
	return fs.combine(dir, name)
end

kernel.term = {}

function kernel.term.write(text)
	return term.write(text)
end

function kernel.term.clear()
	return term.clear()
end

function kernel.term.clearLine()
	return term.clearLine()
end

function kernel.term.getSize()
	return term.getSize()
end

function kernel.term.getCursorPos()
	return term.getCursorPos()
end

function kernel.term.setCursorPos(x, y)
	return term.setCursorPos(x, y)
end

function kernel.term.setTextColor(color)
	return term.setTextColor(color)
end

function kernel.term.setBackgroundColor(color)
	return term.setBackgroundColor(color)
end

function kernel.term.resetColor()
	return term.setTextColor(colors.white), term.setBackgroundColor(colors.black)
end

function kernel.term.isColor()
	return term.isColor()
end

function kernel.term.native()
	return term.native()
end

function kernel.term.current()
	return term.current()
end

function kernel.term.redirect(target)
	return term.redirect(target)
end

kernel.peripheral = {}

function kernel.peripheral.list()
	return peripheral.getNames()
end

function kernel.peripheral.has(name)
	return peripheral.isPresent(name)
end

function kernel.peripheral.type(name)
	return peripheral.getType(name)
end

function kernel.peripheral.get(name)
	return peripheral.wrap(name)
end

function kernel.peripheral.unget(name)
	return peripheral.getName(name)
end

function kernel.peripheral.find(typeName)
	return peripheral.find(typeName)
end

function kernel.peripheral.call(name, method, ...)
	return peripheral.call(name, method, ...)
end

function kernel.peripheral.methods(name)
	return peripheral.getMethods(name)
end

function kernel.peripheral.hasMethod(name, method)
	local methods = peripheral.getMethods(name)
	for i = 1, #methods do
		if methods[i] == method then
			return true
		end
	end
	return false
end

kernel.colors = colors
kernel.textutils = textutils

kernel.settings = {}

function kernel.settings.get(name, default)
	return settings.get(name, default)
end

function kernel.settings.set(name, value)
	return settings.set(name, value)
end

function kernel.settings.unset(name)
	return settings.unset(name)
end

function kernel.settings.load(path)
	return settings.load(path)
end

function kernel.settings.save(path)
	return settings.save(path)
end

kernel.process = {}

function kernel.process.run(path, ...)
	return shell.run(path, ...)
end

function kernel.process.resolve(name)
	return shell.resolveProgram(name)
end

function kernel.process.alias(name, program)
	return shell.alias(name, program)
end

function kernel.process.setAlias(name, program)
	return shell.alias(name, program)
end

function kernel.process.complete(line, cursorPos)
	return shell.complete(line, cursorPos)
end

function kernel.process.exec(path, ...)
	local program = kernel.process.resolve(path) or path
	return shell.run(program, ...)
end

kernel.table = {}

function kernel.table.copy(src)
	local out = {}
	for k, v in pairs(src or {}) do
		out[k] = v
	end
	return out
end

function kernel.table.deepCopy(src)
	local out = {}
	for k, v in pairs(src or {}) do
		if type(v) == "table" then
			out[k] = kernel.table.deepCopy(v)
		else
			out[k] = v
		end
	end
	return out
end

function kernel.table.merge(dst, src)
	for k, v in pairs(src or {}) do
		if type(v) == "table" and type(dst[k]) == "table" then
			kernel.table.merge(dst[k], v)
		else
			dst[k] = v
		end
	end
	return dst
end

function kernel.table.keys(t)
	local out = {}
	for k in pairs(t or {}) do
		out[#out + 1] = k
	end
	return out
end

function kernel.table.values(t)
	local out = {}
	for _, v in pairs(t or {}) do
		out[#out + 1] = v
	end
	return out
end

kernel.service = {}

function kernel.service.register(name, value)
	if type(name) ~= "string" or name == "" then
		return nil, "invalid service name"
	end
	kernel._services[name] = value or true
	return true
end

function kernel.service.get(name)
	return kernel._services[name]
end

function kernel.service.unregister(name)
	kernel._services[name] = nil
	return true
end

function kernel.service.list()
	return kernel.table.keys(kernel._services)
end

kernel.driver = {}

function kernel.driver.unload(id)
	local driver = kernel._drivers[id]
	if not driver then
		return nil, "driver not loaded"
	end

	if type(driver.shutdown) == "function" then
		local ok, err = pcall(driver.shutdown, kernel, kernel.old or {})
		if not ok then
			return nil, "driver shutdown failed: " .. tostring(err)
		end
	end

	kernel._drivers[id] = nil
	return true
end

function kernel.driver.load(filePath)
	local ok, driver = pcall(dofile, filePath)
	if not ok then
		return nil, "failed to load driver: " .. tostring(driver)
	end

	if type(driver) ~= "table" then
		return nil, "driver must return a table"
	end

	if type(driver.id) ~= "string" or driver.id == "" then
		return nil, "driver missing valid id"
	end

	if kernel._drivers[driver.id] then
		return nil, "driver already loaded: " .. driver.id
	end

	if type(driver.init) == "function" then
		local ok2, err = pcall(driver.init, kernel, kernel.old or {})
		if not ok2 then
			return nil, "driver init failed: " .. tostring(err)
		end
	end

	kernel._drivers[driver.id] = driver
	return driver
end

function kernel.driver.register(name, value)
	if type(name) ~= "string" or name == "" then
		return nil, "invalid driver name"
	end
	kernel._drivers[name] = value or true
	return true
end

function kernel.driver.get(name)
	return kernel._drivers[name]
end

function kernel.driver.unregister(name)
	kernel._drivers[name] = nil
	return true
end

function kernel.driver.list()
	return kernel.table.keys(kernel._drivers)
end

function kernel.boot()
	kernel._state.booted = true
	kernel.info("Boot sequence complete")
	return true
end

function kernel.status()
	return {
		name = kernel.name(),
		version = kernel.version(),
		build = kernel.build(),
		uptime = kernel.uptime(),
		booted = kernel._state.booted,
		shutdownRequested = kernel._state.shutdownRequested,
		rebootRequested = kernel._state.rebootRequested,
	}
end

kernel.text = kernel.text or {}
kernel.math = kernel.math or {}
kernel.table = kernel.table or {}

function kernel.text.trim(s)
	s = tostring(s or "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function kernel.text.split(s, sep)
	s = tostring(s or "")
	sep = sep or "%s+"
	local out = {}

	if sep == "%s+" then
		for part in s:gmatch("%S+") do
			out[#out + 1] = part
		end
		return out
	end

	local startPos = 1
	while true do
		local i, j = string.find(s, sep, startPos, true)
		if not i then
			out[#out + 1] = string.sub(s, startPos)
			break
		end
		out[#out + 1] = string.sub(s, startPos, i - 1)
		startPos = j + 1
	end
	return out
end

function kernel.text.startsWith(s, prefix)
	s, prefix = tostring(s or ""), tostring(prefix or "")
	return s:sub(1, #prefix) == prefix
end

function kernel.text.endsWith(s, suffix)
	s, suffix = tostring(s or ""), tostring(suffix or "")
	return suffix == "" or s:sub(-#suffix) == suffix
end

function kernel.text.padLeft(s, len, char)
	s = tostring(s or "")
	char = tostring(char or " ")
	while #s < (len or 0) do
		s = char .. s
	end
	return s
end

function kernel.text.padRight(s, len, char)
	s = tostring(s or "")
	char = tostring(char or " ")
	while #s < (len or 0) do
		s = s .. char
	end
	return s
end

function kernel.text.repeatChar(char, count)
	return string.rep(tostring(char or " "), math.max(0, tonumber(count) or 0))
end

function kernel.text.center(s, width, char)
	s = tostring(s or "")
	char = tostring(char or " ")
	width = tonumber(width) or #s
	if #s >= width then
		return s
	end
	local left = math.floor((width - #s) / 2)
	local right = width - #s - left
	return string.rep(char, left) .. s .. string.rep(char, right)
end

function kernel.text.toLines(s)
	s = tostring(s or "")
	local out = {}
	for line in (s .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	return out
end

function kernel.text.fromLines(lines, sep)
	return table.concat(lines or {}, sep or "\n")
end

function kernel.math.clamp(n, min, max)
	n = tonumber(n) or 0
	min = tonumber(min) or n
	max = tonumber(max) or n
	if n < min then
		return min
	end
	if n > max then
		return max
	end
	return n
end

function kernel.math.sign(n)
	n = tonumber(n) or 0
	if n > 0 then
		return 1
	end
	if n < 0 then
		return -1
	end
	return 0
end

function kernel.math.round(n)
	n = tonumber(n) or 0
	return math.floor(n + 0.5)
end

function kernel.math.floor(n)
	return math.floor(tonumber(n) or 0)
end

function kernel.math.ceil(n)
	return math.ceil(tonumber(n) or 0)
end

function kernel.math.lerp(a, b, t)
	a, b, t = tonumber(a) or 0, tonumber(b) or 0, tonumber(t) or 0
	return a + (b - a) * t
end

function kernel.math.map(value, inMin, inMax, outMin, outMax)
	value = tonumber(value) or 0
	inMin, inMax = tonumber(inMin) or 0, tonumber(inMax) or 1
	outMin, outMax = tonumber(outMin) or 0, tonumber(outMax) or 1
	if inMax == inMin then
		return outMin
	end
	return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin)
end

function kernel.math.within(n, min, max)
	n = tonumber(n) or 0
	min = tonumber(min) or n
	max = tonumber(max) or n
	return n >= min and n <= max
end

function kernel.table.contains(t, value)
	for _, v in pairs(t or {}) do
		if v == value then
			return true
		end
	end
	return false
end

function kernel.table.indexOf(t, value)
	for k, v in ipairs(t or {}) do
		if v == value then
			return k
		end
	end
	return nil
end

function kernel.table.reverse(t)
	local out = {}
	for i = #t, 1, -1 do
		out[#out + 1] = t[i]
	end
	return out
end

function kernel.table.count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

if type(kernel.serialize) ~= "table" then
	kernel.serialize = {}
end
if type(kernel.file) ~= "table" then
	kernel.file = {}
end

function kernel.serialize.table(t)
	return textutils.serialize(t)
end

function kernel.serialize.untable(s)
	local ok, result = pcall(textutils.unserialize, s)
	if ok then
		return result
	end
	return nil, result
end

function kernel.serialize.json(t)
	if textutils.serializeJSON then
		return textutils.serializeJSON(t)
	end
	return nil, "serializeJSON unavailable"
end

function kernel.serialize.unjson(s)
	if textutils.unserializeJSON then
		local ok, result = pcall(textutils.unserializeJSON, s)
		if ok then
			return result
		end
		return nil, result
	end
	return nil, "unserializeJSON unavailable"
end

function kernel.file.exists(path)
	return kernel.fs.exists(path)
end

function kernel.file.read(path)
	return kernel.fs.readAll(path)
end

function kernel.file.write(path, data)
	return kernel.fs.writeAll(path, data)
end

function kernel.file.append(path, data)
	return kernel.fs.appendAll(path, data)
end

function kernel.file.delete(path)
	return kernel.fs.delete(path)
end

function kernel.file.copy(from, to)
	return kernel.fs.copy(from, to)
end

function kernel.file.move(from, to)
	return kernel.fs.move(from, to)
end

function kernel.file.touch(path)
	if not fs.exists(path) then
		return kernel.fs.writeAll(path, "")
	end
	return true
end

function kernel.file.readTable(path)
	local data, err = kernel.file.read(path)
	if not data then
		return nil, err
	end
	return kernel.serialize.untable(data)
end

function kernel.file.writeTable(path, value)
	local data = kernel.serialize.table(value)
	if not data then
		return nil, "serialization failed"
	end
	return kernel.file.write(path, data)
end

function kernel.file.ensureParent(path)
	local dir = fs.getDir(path)
	if dir and dir ~= "" and not fs.exists(dir) then
		return fs.makeDir(dir)
	end
	return true
end

function kernel.file.ensureDir(path)
	if not fs.exists(path) then
		return fs.makeDir(path)
	end
	return true
end

function kernel.file.readLines(path)
	local data, err = kernel.file.read(path)
	if not data then
		return nil, err
	end
	return kernel.text.toLines(data)
end

function kernel.file.walk(path, out)
	path = path or "/"
	out = out or {}
	if not fs.exists(path) then
		return out
	end
	out[#out + 1] = path
	if fs.isDir(path) then
		for _, name in ipairs(fs.list(path)) do
			kernel.file.walk(fs.combine(path, name), out)
		end
	end
	return out
end

function kernel.file.size(path)
	return fs.getSize(path)
end

function kernel.file.isDir(path)
	return fs.isDir(path)
end

function kernel.file.isFile(path)
	return fs.exists(path) and not fs.isDir(path)
end

kernel.event = kernel.event or {}
kernel.process = kernel.process or {}

function kernel.event.emit(name, ...)
	return os.queueEvent(name, ...)
end

function kernel.event.wait(filter, timeout)
	if timeout == nil then
		return os.pullEvent(filter)
	end

	local timer = os.startTimer(timeout)
	while true do
		local e, a, b, c, d = os.pullEvent()
		if filter == nil or e == filter then
			return e, a, b, c, d
		end
		if e == "timer" and a == timer then
			return nil, "timeout"
		end
	end
end

function kernel.event.waitAny(filters, timeout)
	local wanted = {}
	for _, name in ipairs(filters or {}) do
		wanted[name] = true
	end

	if timeout ~= nil then
		local timer = os.startTimer(timeout)
		while true do
			local e, a, b, c, d = os.pullEvent()
			if wanted[e] or next(wanted) == nil then
				return e, a, b, c, d
			end
			if e == "timer" and a == timer then
				return nil, "timeout"
			end
		end
	end

	while true do
		local e, a, b, c, d = os.pullEvent()
		if wanted[e] or next(wanted) == nil then
			return e, a, b, c, d
		end
	end
end

function kernel.event.after(seconds, callback, ...)
	local timer = os.startTimer(seconds)
	while true do
		local e, a = os.pullEvent("timer")
		if a == timer then
			return callback(...)
		end
	end
end

function kernel.process.exists(name)
	return shell.resolveProgram(name) ~= nil
end

function kernel.process.dir()
	return shell.dir()
end

function kernel.process.setDir(path)
	return shell.setDir(path)
end

function kernel.process.path()
	return shell.path()
end

function kernel.process.setPath(path)
	return shell.setPath(path)
end

if type(kernel.peripheral) ~= "table" then
	kernel.peripheral = {}
end
if type(kernel.monitor) ~= "table" then
	kernel.monitor = {}
end
if type(kernel.color) ~= "table" then
	kernel.color = {}
end

kernel.color.names = {
	white = colors.white,
	orange = colors.orange,
	magenta = colors.magenta,
	lightBlue = colors.lightBlue,
	yellow = colors.yellow,
	lime = colors.lime,
	pink = colors.pink,
	gray = colors.gray,
	lightGray = colors.lightGray,
	cyan = colors.cyan,
	purple = colors.purple,
	blue = colors.blue,
	brown = colors.brown,
	green = colors.green,
	red = colors.red,
	black = colors.black,
}

function kernel.color.fromName(name)
	return kernel.color.names[tostring(name or "")] or kernel.color.names[string.lower(tostring(name or ""))] or nil
end

function kernel.color.toName(value)
	for name, c in pairs(kernel.color.names) do
		if c == value then
			return name
		end
	end
	return nil
end

function kernel.color.isValid(value)
	return kernel.color.toName(value) ~= nil
end

function kernel.peripheral.require(name, expectedType)
	if not peripheral.isPresent(name) then
		return nil, "peripheral not present"
	end
	if expectedType and peripheral.getType(name) ~= expectedType then
		return nil, "unexpected peripheral type"
	end
	return peripheral.wrap(name)
end

function kernel.peripheral.findAll(typeName)
	local out = {}
	for _, name in ipairs(peripheral.getNames()) do
		if peripheral.getType(name) == typeName then
			out[#out + 1] = peripheral.wrap(name)
		end
	end
	return out
end

function kernel.monitor.find()
	local found = peripheral.find("monitor")
	return found
end

function kernel.monitor.list()
	local out = {}
	for _, name in ipairs(peripheral.getNames()) do
		if peripheral.getType(name) == "monitor" then
			out[#out + 1] = name
		end
	end
	return out
end

function kernel.monitor.wrap(name)
	local mon = peripheral.wrap(name)
	if not mon then
		return nil, "monitor not found"
	end
	return mon
end

function kernel.monitor.use(name, fn)
	local mon, err = kernel.monitor.wrap(name)
	if not mon then
		return nil, err
	end
	local old = term.redirect(mon)
	local ok, result = pcall(fn, mon)
	term.redirect(old)
	if not ok then
		return nil, result
	end
	return result
end

function kernel.monitor.clear(name)
	return kernel.monitor.use(name, function(mon)
		mon.clear()
		mon.setCursorPos(1, 1)
	end)
end

function kernel.monitor.writeCentered(name, y, text)
	return kernel.monitor.use(name, function(mon)
		local w, _ = mon.getSize()
		local x = math.max(1, math.floor((w - #tostring(text)) / 2) + 1)
		mon.setCursorPos(x, y or 1)
		mon.write(tostring(text))
	end)
end

function kernel.monitor.setScale(name, scale)
	local mon = peripheral.wrap(name)
	if not mon then
		return nil, "monitor not found"
	end
	return mon.setTextScale(scale)
end

kernel.net = kernel.net or {}

function kernel.net.available()
	return rednet ~= nil
end

function kernel.net.open(side)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.open(side)
end

function kernel.net.close(side)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.close(side)
end

function kernel.net.isOpen(side)
	if not rednet then
		return false
	end
	return rednet.isOpen(side)
end

function kernel.net.send(id, message, protocol)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.send(id, message, protocol)
end

function kernel.net.broadcast(message, protocol)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.broadcast(message, protocol)
end

function kernel.net.receive(protocol, timeout)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.receive(protocol, timeout)
end

function kernel.net.host(protocol, hostname)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.host(protocol, hostname)
end

function kernel.net.unhost(protocol)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.unhost(protocol)
end

function kernel.net.lookup(protocol, hostname)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.lookup(protocol, hostname)
end

kernel.system = kernel.system or {}
kernel.util = kernel.util or {}

function kernel.system.status()
	return {
		name = kernel.name and kernel.name() or "CloverOS",
		version = kernel.version and kernel.version() or "unknown",
		uptime = kernel.uptime and kernel.uptime() or 0,
		computerId = os.getComputerID(),
		label = os.getComputerLabel(),
		color = term.isColor and term.isColor() or false,
	}
end

function kernel.system.hostname()
	return os.getComputerLabel() or ("computer-" .. tostring(os.getComputerID()))
end

function kernel.system.setHostname(name)
	return os.setComputerLabel(name)
end

function kernel.util.uuidLike()
	return string.format(
		"%08x-%04x-%04x-%04x-%012x",
		os.epoch("utc") % 0xFFFFFFFF,
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFFFFFFFFFF)
	)
end

function kernel.util.timeMs()
	return os.epoch("utc")
end

function kernel.util.now()
	return os.clock()
end

function kernel.util.safeCall(fn, ...)
	local ok, result = pcall(fn, ...)
	if ok then
		return true, result
	end
	return false, result
end

function kernel.util.import(path)
	local ok, result = pcall(dofile, path)
	if ok then
		return true, result
	end
	return false, result
end

if type(kernel.fs) ~= "table" then
	kernel.fs = {}
end
if type(kernel.path) ~= "table" then
	kernel.path = {}
end
if type(kernel.table) ~= "table" then
	kernel.table = {}
end
if type(kernel.config) ~= "table" then
	kernel.config = {}
end
if type(kernel.registry) ~= "table" then
	kernel.registry = {}
end
if type(kernel.ui) ~= "table" then
	kernel.ui = {}
end
if type(kernel.input) ~= "table" then
	kernel.input = {}
end
if type(kernel.task) ~= "table" then
	kernel.task = {}
end
if type(kernel.app) ~= "table" then
	kernel.app = {}
end
if type(kernel.debug) ~= "table" then
	local dbg = kernel.debug
	kernel.debug = {}
	if type(dbg) == "function" then
		local mt = getmetatable(dbg)
		if mt then
			setmetatable(kernel.debug, mt)
		end
	end
end
if type(kernel.system) ~= "table" then
	kernel.system = {}
end
if type(kernel.net) ~= "table" then
	kernel.net = {}
end
function kernel.fs.getFreeSpace(path)
	return fs.getFreeSpace(path or "/")
end

function kernel.fs.makeTree(path)
	if not path or path == "" then
		return nil, "invalid path"
	end
	if fs.exists(path) then
		return true
	end
	local dir = fs.getDir(path)
	if dir and dir ~= "" and not fs.exists(dir) then
		kernel.fs.makeTree(dir)
	end
	return fs.makeDir(path)
end

function kernel.fs.parent(path)
	return fs.getDir(path)
end

function kernel.fs.stem(path)
	local name = fs.getName(path)
	return (name:gsub("%.[^.]+$", ""))
end

function kernel.fs.extension(path)
	local name = fs.getName(path)
	return name:match("%.([^.]+)$")
end

function kernel.fs.readOr(path, default)
	local data = kernel.fs.readAll(path)
	if data == nil then
		return default
	end
	return data
end

function kernel.fs.writeIfMissing(path, data)
	if not fs.exists(path) then
		return kernel.fs.writeAll(path, data)
	end
	return true
end

function kernel.fs.listdir(path)
	return fs.list(path or "/")
end

function kernel.fs.count(path)
	if not fs.exists(path) then
		return 0
	end
	if not fs.isDir(path) then
		return 1
	end
	local n = 0
	for _, _ in ipairs(fs.list(path)) do
		n = n + 1
	end
	return n
end

function kernel.path.normalize(path)
	path = tostring(path or "")
	local absolute = path:sub(1, 1) == "/"
	local parts = {}

	for part in path:gmatch("[^/]+") do
		if part == ".." then
			if #parts > 0 then
				table.remove(parts)
			end
		elseif part ~= "." and part ~= "" then
			parts[#parts + 1] = part
		end
	end

	local result = table.concat(parts, "/")
	if absolute then
		result = "/" .. result
	end
	if result == "" then
		return absolute and "/" or "."
	end
	return result
end

function kernel.path.join(...)
	local parts = { ... }
	if #parts == 0 then
		return ""
	end
	local out = tostring(parts[1] or "")
	for i = 2, #parts do
		out = fs.combine(out, tostring(parts[i] or ""))
	end
	return kernel.path.normalize(out)
end

function kernel.path.isAbsolute(path)
	return tostring(path or ""):sub(1, 1) == "/"
end

function kernel.path.parent(path)
	return fs.getDir(path)
end

function kernel.path.stem(path)
	local name = fs.getName(path)
	return (name:gsub("%.[^.]+$", ""))
end

function kernel.path.hasExtension(path)
	return kernel.path.extension(path) ~= nil
end

function kernel.table.filter(t, fn)
	local out = {}
	for k, v in pairs(t or {}) do
		if fn(v, k) then
			out[k] = v
		end
	end
	return out
end

function kernel.table.map(t, fn)
	local out = {}
	for k, v in pairs(t or {}) do
		out[k] = fn(v, k)
	end
	return out
end

function kernel.table.slice(t, fromIndex, toIndex)
	local out = {}
	fromIndex = fromIndex or 1
	toIndex = toIndex or #t
	for i = fromIndex, math.min(toIndex, #t) do
		out[#out + 1] = t[i]
	end
	return out
end

function kernel.table.unique(t)
	local out = {}
	local seen = {}
	for _, v in ipairs(t or {}) do
		if not seen[v] then
			seen[v] = true
			out[#out + 1] = v
		end
	end
	return out
end

function kernel.table.sort(t, comp)
	local out = kernel.table.copy(t or {})
	table.sort(out, comp)
	return out
end

function kernel.table.join(a, b)
	local out = kernel.table.copy(a or {})
	for _, v in ipairs(b or {}) do
		out[#out + 1] = v
	end
	return out
end

function kernel.table.clear(t)
	for k in pairs(t or {}) do
		t[k] = nil
	end
	return t
end

kernel._configs = kernel._configs or {}

function kernel.config.path(name)
	name = tostring(name or "")
	if name == "" then
		return nil, "invalid config name"
	end
	return "etc/config/" .. name .. ".cfg"
end

function kernel.config.get(name, key, default)
	local cfg = kernel._configs[name]
	if not cfg then
		return default
	end
	local value = cfg[key]
	if value == nil then
		return default
	end
	return value
end

function kernel.config.set(name, key, value)
	kernel._configs[name] = kernel._configs[name] or {}
	kernel._configs[name][key] = value
	return true
end

function kernel.config.load(name)
	local path = kernel.config.path(name)
	if not path then
		return nil, "invalid config name"
	end
	local data = kernel.fs.readAll(path)
	if not data then
		return nil, "config not found"
	end
	local ok, t = pcall(textutils.unserialize, data)
	if not ok or type(t) ~= "table" then
		return nil, "invalid config data"
	end
	kernel._configs[name] = t
	return t
end

function kernel.config.save(name)
	local path = kernel.config.path(name)
	if not path then
		return nil, "invalid config name"
	end
	local cfg = kernel._configs[name] or {}
	local data = textutils.serialize(cfg)
	return kernel.fs.writeAll(path, data)
end

function kernel.config.loadOrCreate(name, defaults)
	local cfg = kernel._configs[name]
	if cfg then
		return cfg
	end

	local loaded = kernel.config.load(name)
	if loaded then
		return loaded
	end

	kernel._configs[name] = kernel.table.deepCopy(defaults or {})
	return kernel._configs[name]
end

function kernel.config.merge(name, defaults)
	local cfg = kernel.config.loadOrCreate(name, defaults)
	kernel.table.merge(cfg, defaults or {})
	return cfg
end

function kernel.config.remove(name)
	kernel._configs[name] = nil
	local path = kernel.config.path(name)
	if path and fs.exists(path) then
		return fs.delete(path)
	end
	return true
end

function kernel.config.list()
	return kernel.table.keys(kernel._configs)
end

kernel._registry = kernel._registry or {}

function kernel.registry.set(namespace, key, value)
	namespace = tostring(namespace or "default")
	kernel._registry[namespace] = kernel._registry[namespace] or {}
	kernel._registry[namespace][key] = value
	return true
end

function kernel.registry.get(namespace, key, default)
	namespace = tostring(namespace or "default")
	local ns = kernel._registry[namespace]
	if not ns then
		return default
	end
	local value = ns[key]
	if value == nil then
		return default
	end
	return value
end

function kernel.registry.remove(namespace, key)
	namespace = tostring(namespace or "default")
	local ns = kernel._registry[namespace]
	if not ns then
		return false
	end
	ns[key] = nil
	return true
end

function kernel.registry.clear(namespace)
	if namespace == nil then
		kernel._registry = {}
		return true
	end
	kernel._registry[tostring(namespace)] = {}
	return true
end

function kernel.registry.list(namespace)
	if namespace == nil then
		return kernel.table.keys(kernel._registry)
	end
	return kernel.table.keys(kernel._registry[tostring(namespace)] or {})
end

function kernel.registry.has(namespace, key)
	namespace = tostring(namespace or "default")
	local ns = kernel._registry[namespace]
	return ns ~= nil and ns[key] ~= nil
end

function kernel.ui.size()
	return term.getSize()
end

function kernel.ui.clear()
	term.clear()
	term.setCursorPos(1, 1)
end

function kernel.ui.clearLine(y)
	local x, curY = term.getCursorPos()
	if y then
		term.setCursorPos(1, y)
	end
	term.clearLine()
	term.setCursorPos(x, curY)
end

function kernel.ui.writeAt(x, y, text)
	term.setCursorPos(x, y)
	term.write(tostring(text or ""))
end

function kernel.ui.centerText(y, text)
	local w = select(1, term.getSize())
	text = tostring(text or "")
	local x = math.max(1, math.floor((w - #text) / 2) + 1)
	term.setCursorPos(x, y)
	term.write(text)
end

function kernel.ui.rightText(y, text)
	local w = select(1, term.getSize())
	text = tostring(text or "")
	local x = math.max(1, w - #text + 1)
	term.setCursorPos(x, y)
	term.write(text)
end

function kernel.ui.box(x, y, w, h, char)
	char = tostring(char or "#")
	for row = 0, h - 1 do
		term.setCursorPos(x, y + row)
		term.write(string.rep(char, w))
	end
end

function kernel.ui.frame(x, y, w, h)
	term.setCursorPos(x, y)
	term.write("+" .. string.rep("-", w - 2) .. "+")
	for row = 1, h - 2 do
		term.setCursorPos(x, y + row)
		term.write("|" .. string.rep(" ", w - 2) .. "|")
	end
	term.setCursorPos(x, y + h - 1)
	term.write("+" .. string.rep("-", w - 2) .. "+")
end

function kernel.ui.progressBar(x, y, width, current, max)
	current = tonumber(current) or 0
	max = tonumber(max) or 1
	width = tonumber(width) or 10
	local pct = 0
	if max > 0 then
		pct = math.max(0, math.min(1, current / max))
	end
	local filled = math.floor(width * pct)
	local bar = "[" .. string.rep("=", filled) .. string.rep(" ", width - filled) .. "]"
	term.setCursorPos(x, y)
	term.write(bar)
end

function kernel.ui.statusLine(text)
	local w, h = term.getSize()
	term.setCursorPos(1, h)
	term.clearLine()
	term.write(kernel.text.padRight(tostring(text or ""), w))
end

function kernel.input.line(prompt, hiddenOrDefault, default)
	local hidden = false
	if type(hiddenOrDefault) == "boolean" then
		hidden = hiddenOrDefault
	else
		default = hiddenOrDefault
	end

	if prompt and prompt ~= "" then
		write(tostring(prompt))
	end
	local input
	if hidden and type(read) == "function" then
		input = read("*")
	else
		input = read()
	end
	if input == "" and default ~= nil then
		return default
	end
	return input
end

function kernel.input.readline(prompt, history, complete)
	if prompt and prompt ~= "" then
		term.write(tostring(prompt))
	end
	if type(read) == "function" then
		return read(nil, history, complete)
	end
	return read()
end

function kernel.input.number(prompt, default)
	local value = kernel.input.line(prompt, default and tostring(default) or nil)
	local n = tonumber(value)
	if n == nil then
		return default
	end
	return n
end

function kernel.input.confirm(prompt, default)
	local suffix = default == false and " [y/N] " or " [Y/n] "
	local value = kernel.input.line((prompt or "Confirm") .. suffix, nil)
	value = kernel.text.trim(tostring(value or "")):lower()
	if value == "" then
		return default ~= false
	end
	return value == "y" or value == "yes" or value == "true" or value == "1"
end

function kernel.input.choice(prompt, options, defaultIndex)
	options = options or {}
	write(tostring(prompt or "Choose") .. "\n")
	for i, opt in ipairs(options) do
		write(("  %d) %s\n"):format(i, tostring(opt)))
	end
	local choice = kernel.input.number("Select: ", defaultIndex or 1) or 1
	if choice < 1 or choice > #options then
		return nil, "invalid choice"
	end
	return choice, options[choice]
end

kernel._tasks = kernel._tasks or {}
kernel._nextTaskId = kernel._nextTaskId or 1

function kernel.task.spawn(fn, ...)
	if type(fn) ~= "function" then
		return nil, "fn must be a function"
	end

	local id = kernel._nextTaskId
	kernel._nextTaskId = id + 1

	local co = coroutine.create(fn)
	kernel._tasks[id] = {
		co = co,
		alive = true,
		done = false,
		result = nil,
		error = nil,
	}

	local ok, result = coroutine.resume(co, ...)
	if not ok then
		kernel._tasks[id].alive = false
		kernel._tasks[id].done = true
		kernel._tasks[id].error = result
		return nil, result
	end

	if coroutine.status(co) == "dead" then
		kernel._tasks[id].alive = false
		kernel._tasks[id].done = true
		kernel._tasks[id].result = result
	end

	return id
end

function kernel.task.step(id, ...)
	local task = kernel._tasks[id]
	if not task or not task.alive then
		return nil, "task not alive"
	end

	local ok, result = coroutine.resume(task.co, ...)
	if not ok then
		task.alive = false
		task.done = true
		task.error = result
		return nil, result
	end

	if coroutine.status(task.co) == "dead" then
		task.alive = false
		task.done = true
		task.result = result
	end

	return true, result
end

function kernel.task.cancel(id)
	local task = kernel._tasks[id]
	if not task then
		return nil, "task not found"
	end
	task.alive = false
	task.done = true
	task.error = "cancelled"
	return true
end

function kernel.task.alive(id)
	local task = kernel._tasks[id]
	return task ~= nil and task.alive == true
end

function kernel.task.status(id)
	local task = kernel._tasks[id]
	if not task then
		return nil, "task not found"
	end
	return {
		alive = task.alive,
		done = task.done,
		result = task.result,
		error = task.error,
	}
end

function kernel.task.list()
	local out = {}
	for id in pairs(kernel._tasks) do
		out[#out + 1] = id
	end
	table.sort(out)
	return out
end

function kernel.task.cleanup()
	for id, task in pairs(kernel._tasks) do
		if not task.alive then
			kernel._tasks[id] = nil
		end
	end
	return true
end

function kernel.input.waitKey(filter)
	return os.pullEvent(filter or "key")
end

kernel._apps = kernel._apps or {}

function kernel.app.register(name, program, meta)
	if type(name) ~= "string" or name == "" then
		return nil, "invalid app name"
	end
	kernel._apps[name] = {
		program = program,
		meta = meta or {},
		running = false,
	}
	return true
end

function kernel.app.get(name)
	return kernel._apps[name]
end

function kernel.app.unregister(name)
	kernel._apps[name] = nil
	return true
end

function kernel.app.list()
	return kernel.table.keys(kernel._apps)
end

function kernel.app.isRunning(name)
	local app = kernel._apps[name]
	return app ~= nil and app.running == true
end

function kernel.app.launch(name, ...)
	local app = kernel._apps[name]
	if not app then
		return nil, "app not registered"
	end
	local program = app.program
	if type(program) ~= "string" then
		return nil, "invalid program"
	end

	app.running = true
	local ok, result = pcall(shell.run, program, ...)
	app.running = false

	if not ok then
		return nil, result
	end
	return result
end

function kernel.app.meta(name)
	local app = kernel._apps[name]
	if not app then
		return nil, "app not registered"
	end
	return app.meta
end

function kernel.debug.inspect(value)
	local ok, result = pcall(textutils.serialize, value)
	if ok then
		return result
	end
	return tostring(value)
end

function kernel.debug.dump(value)
	local data = kernel.debug.inspect(value)
	if print then
		print(data)
	else
		write(data .. "\n")
	end
	return data
end

function kernel.debug.trace(message)
	error("[TRACE] " .. tostring(message), 2)
end

function kernel.system.isColor()
	return term.isColor()
end

function kernel.system.freeSpace(path)
	return fs.getFreeSpace(path or "/")
end

function kernel.system.id()
	return os.getComputerID()
end

function kernel.system.label()
	return os.getComputerLabel()
end

function kernel.system.setLabel(label)
	return os.setComputerLabel(label)
end

function kernel.system.versionString()
	return os.version()
end

function kernel.net.ping(id, protocol, timeout)
	if not rednet then
		return nil, "rednet unavailable"
	end
	return rednet.ping(id, protocol, timeout)
end

function kernel.net.isTargetOnline(id)
	if not rednet then
		return false
	end
	return rednet.isPresent(id)
end

function kernel.net.lookupAll(protocol)
	if not rednet then
		return nil, "rednet unavailable"
	end
	local results = {}
	local found = rednet.lookup(protocol)
	if type(found) == "table" then
		return found
	end
	if found ~= nil then
		results[#results + 1] = found
	end
	return results
end
-- Licensed under GPLv2
local RISCV = {
	reg = {},
	pc = 0,
	syscalls = require("syscall"),
	opcodes = { [0x63] = {}, [0x03] = {}, [0x23] = {}, [0x13] = {}, [0x33] = {}, [0x2F] = { [2] = true } },
	mult_opcodes = {},
	atomic_opcodes = {},
	atomic_rs = {},
	halt = false,
	sysdata = {},
}
for i = 1, 31 do
	RISCV.reg[i] = 0
end
setmetatable(RISCV.reg, {
	__index = function()
		return 0
	end,
	__newindex = function() end,
})
if ffi then
	print("Using FFI acceleration")
	RISCV.mem = ffi.new("uint8_t[?]", 0x2010000)
	RISCV.mem16 = ffi.cast("uint16_t*", RISCV.mem)
	RISCV.mem32 = ffi.cast("uint32_t*", RISCV.mem)
	RISCV.fficopy, RISCV.ffistring = ffi.copy, ffi.string
else
	local function __add(self, offset)
		return setmetatable({}, {
			__index = function(_, idx)
				return self[offset + idx]
			end,
			__newindex = function(_, idx, val)
				self[offset + idx] = val
			end,
			__add = __add,
		})
	end
	RISCV.mem = setmetatable({}, {
		__index = function()
			return 0
		end,
		__add = __add,
	})
	RISCV.mem16 = setmetatable({}, {
		__index = function(_, idx)
			return RISCV.mem[idx * 2] + RISCV.mem[idx * 2 + 1] * 256
		end,
		__newindex = function(_, idx, val)
			RISCV.mem[idx * 2] = bit32.extract(val, 0, 8)
			RISCV.mem[idx * 2 + 1] = bit32.extract(val, 8, 8)
		end,
		__add = __add,
	})
	RISCV.mem32 = setmetatable({}, {
		__index = function(_, idx)
			return RISCV.mem[idx * 4]
				+ RISCV.mem[idx * 4 + 1] * 256
				+ RISCV.mem[idx * 4 + 2] * 65536
				+ RISCV.mem[idx * 4 + 3] * 16777216
		end,
		__newindex = function(_, idx, val)
			RISCV.mem[idx * 4] = bit32.extract(val, 0, 8)
			RISCV.mem[idx * 4 + 1] = bit32.extract(val, 8, 8)
			RISCV.mem[idx * 4 + 2] = bit32.extract(val, 16, 8)
			RISCV.mem[idx * 4 + 3] = bit32.extract(val, 24, 8)
		end,
		__add = __add,
	})
	function RISCV.fficopy(dest, src, size)
		if type(src) == "string" then
			for i, c in src:gmatch("()(.)") do
				dest[i - 1] = c:byte()
			end
		else
			for i = 0, size - 1 do
				dest[i] = src[i]
			end
		end
	end
	function RISCV.ffistring(ptr, size)
		local retval = ""
		if size then
			for i = 0, size - 1 do
				retval = retval .. string.char(ptr[i])
			end
		else
			for i = 0, math.huge do
				local c = ptr[i]
				if c == 0 then
					break
				end
				retval = retval .. string.char(c)
			end
		end
		return retval
	end
end

local function fiximm(bits)
	return function(inst)
		if bit32.btest(inst.imm, 2 ^ (bits - 1)) then
			inst.simm = bit32.bor(inst.imm, bit32.bnot(2 ^ bits - 1)) - 0x100000000
		else
			inst.simm = inst.imm
		end
		return inst
	end
end

local function decodeR(inst)
	return {
		inst = inst,
		opcode = bit32.extract(inst, 0, 7),
		rd = bit32.extract(inst, 7, 5),
		funct3 = bit32.extract(inst, 12, 3),
		rs1 = bit32.extract(inst, 15, 5),
		rs2 = bit32.extract(inst, 20, 5),
		funct7 = bit32.extract(inst, 25, 7),
	}
end

local function decodeI(inst)
	return fiximm(12)({
		inst = inst,
		opcode = bit32.extract(inst, 0, 7),
		rd = bit32.extract(inst, 7, 5),
		funct3 = bit32.extract(inst, 12, 3),
		rs1 = bit32.extract(inst, 15, 5),
		imm = bit32.extract(inst, 20, 12),
	})
end

local function decodeS(inst)
	return fiximm(12)({
		inst = inst,
		opcode = bit32.extract(inst, 0, 7),
		funct3 = bit32.extract(inst, 12, 3),
		rs1 = bit32.extract(inst, 15, 5),
		rs2 = bit32.extract(inst, 20, 5),
		imm = bit32.bor(bit32.extract(inst, 7, 5), bit32.lshift(bit32.extract(inst, 25, 7), 5)),
	})
end

local function decodeB(inst)
	return fiximm(13)({
		inst = inst,
		opcode = bit32.extract(inst, 0, 7),
		funct3 = bit32.extract(inst, 12, 3),
		rs1 = bit32.extract(inst, 15, 5),
		rs2 = bit32.extract(inst, 20, 5),
		imm = bit32.bor(
			bit32.lshift(bit32.extract(inst, 7, 1), 11),
			bit32.lshift(bit32.extract(inst, 8, 4), 1),
			bit32.lshift(bit32.extract(inst, 25, 6), 5),
			bit32.lshift(bit32.extract(inst, 31, 1), 12)
		),
	})
end

local function decodeU(inst)
	return fiximm(32)({
		inst = inst,
		opcode = bit32.extract(inst, 0, 7),
		rd = bit32.extract(inst, 7, 5),
		imm = bit32.band(inst, 0xFFFFF000),
	})
end

local function decodeJ(inst)
	return fiximm(21)({
		inst = inst,
		opcode = bit32.extract(inst, 0, 7),
		rd = bit32.extract(inst, 7, 5),
		imm = bit32.bor(
			bit32.lshift(bit32.extract(inst, 12, 8), 12),
			bit32.lshift(bit32.extract(inst, 20, 1), 11),
			bit32.lshift(bit32.extract(inst, 21, 10), 1),
			bit32.lshift(bit32.extract(inst, 31, 1), 20)
		),
	})
end

local opcode_modes = {
	[0x37] = decodeU, -- LUI
	[0x17] = decodeU, -- AUIPC
	[0x6F] = decodeJ, -- JAL
	[0x67] = decodeI, -- JALR
	[0x63] = decodeB, -- B*
	[0x03] = decodeI, -- L*
	[0x23] = decodeS, -- S*
	[0x13] = decodeI, -- immediate arith
	[0x33] = decodeR, -- arith
	[0x0F] = decodeI, -- FENCE
	[0x73] = decodeI, -- E*
	[0x2F] = decodeR, -- atomic
}

RISCV.opcodes[0x37] = function(pc, inst) -- LUI
	return ([[
        -- %08X: LUI
        self.reg[%d] = %d
    ]]):format(pc, inst.rd, inst.imm)
end

RISCV.opcodes[0x17] = function(pc, inst) -- AUIPC
	return ([[
        -- %08X: AUIPC
        self.reg[%d] = %d
    ]]):format(pc, inst.rd, (pc - 4 + inst.imm) % 0x100000000)
end

RISCV.opcodes[0x6F] = function(pc, inst) -- JAL
	if (pc + inst.simm - 4) % 4 ~= 0 then
		error("unaligned jump to " .. (pc + inst.simm - 4))
	end
	return ([[
        -- %08X: JAL
        self.reg[%d] = %d
        return self.traces[%d](self)
    ]]):format(pc, inst.rd, pc, pc + inst.simm - 4),
		true
end

RISCV.opcodes[0x67] = function(pc, inst) -- JALR
	return ([[
        -- %08X: JALR
        local pc = bit32.band(self.reg[%d] + %d, 0xFFFFFFFE)
        self.reg[%d] = %d
        return self.traces[pc](self)
    ]]):format(pc, inst.rs1, inst.simm, inst.rd, pc),
		true
end

RISCV.opcodes[0x63][0] = function(pc, inst) -- BEQ
	return ([[
        -- %08X: BEQ
        if self.reg[%d] == self.reg[%d] then return self.traces[%d](self)
        else return self.traces[%d](self) end
    ]]):format(pc, inst.rs1, inst.rs2, pc + inst.simm - 4, pc),
		true
end

RISCV.opcodes[0x63][1] = function(pc, inst) -- BNE
	return ([[
        -- %08X: BNE
        if self.reg[%d] ~= self.reg[%d] then return self.traces[%d](self)
        else return self.traces[%d](self) end
    ]]):format(pc, inst.rs1, inst.rs2, pc + inst.simm - 4, pc),
		true
end

RISCV.opcodes[0x63][4] = function(pc, inst) -- BLT
	return ([[
        -- %08X: BLT
        local ra, rb = self.reg[%d], self.reg[%d]
        if ra >= 0x80000000 then ra = ra - 0x100000000 end
        if rb >= 0x80000000 then rb = rb - 0x100000000 end
        if ra < rb then return self.traces[%d](self)
        else return self.traces[%d](self) end
    ]]):format(pc, inst.rs1, inst.rs2, pc + inst.simm - 4, pc),
		true
end

RISCV.opcodes[0x63][5] = function(pc, inst) -- BGE
	return ([[
        -- %08X: BGE
        local ra, rb = self.reg[%d], self.reg[%d]
        if ra >= 0x80000000 then ra = ra - 0x100000000 end
        if rb >= 0x80000000 then rb = rb - 0x100000000 end
        if ra >= rb then return self.traces[%d](self)
        else return self.traces[%d](self) end
    ]]):format(pc, inst.rs1, inst.rs2, pc + inst.simm - 4, pc),
		true
end

RISCV.opcodes[0x63][6] = function(pc, inst) -- BLTU
	return ([[
        -- %08X: BLTU
        if self.reg[%d] < self.reg[%d] then return self.traces[%d](self)
        else return self.traces[%d](self) end
    ]]):format(pc, inst.rs1, inst.rs2, pc + inst.simm - 4, pc),
		true
end

RISCV.opcodes[0x63][7] = function(pc, inst) -- BGEU
	return ([[
        -- %08X: BGEU
        if self.reg[%d] >= self.reg[%d] then return self.traces[%d](self)
        else return self.traces[%d](self) end
    ]]):format(pc, inst.rs1, inst.rs2, pc + inst.simm - 4, pc),
		true
end

RISCV.opcodes[0x03][0] = function(pc, inst) -- LB
	return ([[
        -- %08X: LB
        self.reg[%d] = self.mem[self.reg[%d] + %d]
        if self.reg[%d] >= 0x80 then self.reg[%d] = self.reg[%d] + 0xFFFFFF00 end
    ]]):format(pc, inst.rd, inst.rs1, inst.simm, inst.rd, inst.rd, inst.rd)
end

RISCV.opcodes[0x03][1] = function(pc, inst) -- LH
	return ([[
        -- %08X: LH
        local addr = self.reg[%d] + %d
        if addr %% 2 ~= 0 then self.reg[%d] = self.mem[addr] + self.mem[addr+1] * 256
        else self.reg[%d] = self.mem16[addr / 2] end
        if self.reg[%d] >= 0x8000 then self.reg[%d] = self.reg[%d] + 0xFFFF0000 end
    ]]):format(pc, inst.rs1, inst.simm, inst.rd, inst.rd, inst.rd, inst.rd, inst.rd)
end

RISCV.opcodes[0x03][2] = function(pc, inst) -- LW
	return ([[
        -- %08X: LW
        local addr = self.reg[%d] + %d
        if addr %% 4 ~= 0 then self.reg[%d] = self.mem[addr] + self.mem[addr+1] * 256 + self.mem[addr+2] * 65536 + self.mem[addr+3] * 16777216
        else self.reg[%d] = self.mem32[addr / 4] end
    ]]):format(pc, inst.rs1, inst.simm, inst.rd, inst.rd)
end

RISCV.opcodes[0x03][4] = function(pc, inst) -- LBU
	return ([[
        -- %08X: LBU
        self.reg[%d] = self.mem[self.reg[%d] + %d]
    ]]):format(pc, inst.rd, inst.rs1, inst.simm)
end

RISCV.opcodes[0x03][5] = function(pc, inst) -- LHU
	return ([[
        -- %08X: LHU
        local addr = self.reg[%d] + %d
        if addr %% 2 ~= 0 then self.reg[%d] = self.mem[addr] + self.mem[addr+1] * 256
        else self.reg[%d] = self.mem16[addr / 2] end
    ]]):format(pc, inst.rs1, inst.simm, inst.rd, inst.rd)
end

RISCV.opcodes[0x23][0] = function(pc, inst) -- SB
	return ([[
        -- %08X: SB
        self.mem[self.reg[%d] + %d] = self.reg[%d] %% 256
    ]]):format(pc, inst.rs1, inst.simm, inst.rs2)
end

RISCV.opcodes[0x23][1] = function(pc, inst) -- SH
	return ([[
        -- %08X: SH
        local addr = self.reg[%d] + %d
        if addr %% 2 ~= 0 then
            self.mem[addr] = bit32.extract(self.reg[%d], 0, 8)
            self.mem[addr+1] = bit32.extract(self.reg[%d], 8, 8)
        else self.mem16[addr / 2] = self.reg[%d] %% 65536 end
    ]]):format(pc, inst.rs1, inst.simm, inst.rs2, inst.rs2, inst.rs2)
end

RISCV.opcodes[0x23][2] = function(pc, inst) -- SW
	return ([[
        -- %08X: SW
        local addr = self.reg[%d] + %d
        if addr %% 4 ~= 0 then
            self.mem[addr] = bit32.extract(self.reg[%d], 0, 8)
            self.mem[addr+1] = bit32.extract(self.reg[%d], 8, 8)
            self.mem[addr+2] = bit32.extract(self.reg[%d], 16, 8)
            self.mem[addr+3] = bit32.extract(self.reg[%d], 24, 8)
        else self.mem32[addr / 4] = self.reg[%d] end
    ]]):format(pc, inst.rs1, inst.simm, inst.rs2, inst.rs2, inst.rs2, inst.rs2, inst.rs2)
end

RISCV.opcodes[0x13][0] = function(pc, inst) -- ADDI
	if inst.rs1 == 0 then
		return ([[
        -- %08X: LI
        self.reg[%d] = %d
        ]]):format(pc, inst.rd, inst.simm % 0x100000000)
	elseif inst.simm == 0 then
		return ([[
        -- %08X: MR
        self.reg[%d] = self.reg[%d]
        ]]):format(pc, inst.rd, inst.rs1)
	else
		return ([[
        -- %08X: ADDI
        self.reg[%d] = (self.reg[%d] + %d) %% 0x100000000
        ]]):format(pc, inst.rd, inst.rs1, inst.simm)
	end
end

RISCV.opcodes[0x13][2] = function(pc, inst) -- SLTI
	return ([[
        -- %08X: SLTI
        local rs = self.reg[%d]
        if rs >= 0x80000000 then rs = rs - 0x100000000 end
        self.reg[%d] = rs < %d and 1 or 0
    ]]):format(pc, inst.rs1, inst.rd, inst.simm)
end

RISCV.opcodes[0x13][3] = function(pc, inst) -- SLTIU
	local imm = inst.simm
	if imm < 0 then
		imm = imm + 0x100000000
	end
	return ([[
        -- %08X: SLTIU
        self.reg[%d] = self.reg[%d] < %d and 1 or 0
    ]]):format(pc, inst.rd, inst.rs1, imm)
end

RISCV.opcodes[0x13][4] = function(pc, inst) -- XORI
	return ([[
        -- %08X: XORI
        self.reg[%d] = bit32.bxor(self.reg[%d], %d)
    ]]):format(pc, inst.rd, inst.rs1, inst.simm % 0x100000000)
end

RISCV.opcodes[0x13][6] = function(pc, inst) -- ORI
	return ([[
        -- %08X: ORI
        self.reg[%d] = bit32.bor(self.reg[%d], %d)
    ]]):format(pc, inst.rd, inst.rs1, inst.simm % 0x100000000)
end

RISCV.opcodes[0x13][7] = function(pc, inst) -- ANDI
	return ([[
        -- %08X: ANDI
        self.reg[%d] = bit32.band(self.reg[%d], %d)
    ]]):format(pc, inst.rd, inst.rs1, inst.simm % 0x100000000)
end

RISCV.opcodes[0x13][1] = function(pc, inst) -- SLLI
	return ([[
        -- %08X: SLLI
        self.reg[%d] = bit32.lshift(self.reg[%d], %d)
    ]]):format(pc, inst.rd, inst.rs1, bit32.band(inst.imm, 0x1F))
end

RISCV.opcodes[0x13][5] = function(pc, inst) -- SRLI/SRAI
	return ([[
        -- %08X: SRLI/SRAI
        self.reg[%d] = bit32.%srshift(self.reg[%d], %d)
    ]]):format(pc, inst.rd, bit32.btest(inst.imm, 0x400) and "a" or "", inst.rs1, bit32.band(inst.imm, 0x1F))
end

RISCV.opcodes[0x33][0] = function(pc, inst) -- ADD/SUB
	return ([[
        -- %08X: ADD/SUB
        self.reg[%d] = (self.reg[%d] %s self.reg[%d]) %% 0x100000000
    ]]):format(pc, inst.rd, inst.rs1, bit32.btest(inst.funct7, 0x20) and "-" or "+", inst.rs2)
end

RISCV.opcodes[0x33][1] = function(pc, inst) -- SLL
	return ([[
        -- %08X: SLL
        self.reg[%d] = bit32.lshift(self.reg[%d], bit32.band(self.reg[%d], 0x1F))
    ]]):format(pc, inst.rd, inst.rs1, inst.rs2)
end

RISCV.opcodes[0x33][2] = function(pc, inst) -- SLT
	return ([[
        -- %08X: SLT
        local ra, rb = self.reg[%d], self.reg[%d]
        if ra >= 0x80000000 then ra = ra - 0x100000000 end
        if rb >= 0x80000000 then rb = rb - 0x100000000 end
        self.reg[%d] = ra < rb and 1 or 0
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd)
end

RISCV.opcodes[0x33][3] = function(pc, inst) -- SLTU
	return ([[
        -- %08X: SLTU
        self.reg[%d] = self.reg[%d] < self.reg[%d] and 1 or 0
    ]]):format(pc, inst.rd, inst.rs1, inst.rs2)
end

RISCV.opcodes[0x33][4] = function(pc, inst) -- XOR
	return ([[
        -- %08X: XOR
        self.reg[%d] = bit32.bxor(self.reg[%d], self.reg[%d])
    ]]):format(pc, inst.rd, inst.rs1, inst.rs2)
end

RISCV.opcodes[0x33][5] = function(pc, inst) -- SRL/SRA
	return ([[
        -- %08X: SRL/SRA
        self.reg[%d] = bit32.%srshift(self.reg[%d], bit32.band(self.reg[%d], 0x1F))
    ]]):format(pc, inst.rd, bit32.btest(inst.funct7, 0x20) and "a" or "", inst.rs1, inst.rs2)
end

RISCV.opcodes[0x33][6] = function(pc, inst) -- OR
	return ([[
        -- %08X: OR
        self.reg[%d] = bit32.bor(self.reg[%d], self.reg[%d])
    ]]):format(pc, inst.rd, inst.rs1, inst.rs2)
end

RISCV.opcodes[0x33][7] = function(pc, inst) -- AND
	return ([[
        -- %08X: AND
        self.reg[%d] = bit32.band(self.reg[%d], self.reg[%d])
    ]]):format(pc, inst.rd, inst.rs1, inst.rs2)
end

RISCV.opcodes[0x0F] = function(pc, inst) -- FENCE
	-- do nothing
	return ("-- %08X: FENCE\n"):format(pc)
end

RISCV.opcodes[0x73] = function(pc, inst) -- ECALL/EBREAK
	if inst.funct3 ~= 0 then
		return ("-- %08X: ECALL Zicsr\n"):format(pc)
	end -- Zicsr not implemented
	if inst.imm == 0 then
		return [=[
        --print("Syscall: " .. self.reg[17])
        if self.syscalls[self.reg[17]] then self.reg[10] = self.syscalls[self.reg[17]](self, table.unpack(self.reg, 10, 16))
        else self.reg[10] = -38 end
        if self.halt then return end
    ]=]
	elseif inst.imm == 0x302 then
		return [=[
        return self.traces[self.reg[5]](self)
    ]=], true
	end
end

RISCV.mult_opcodes[0] = function(pc, inst) -- MUL
	return ([[
        -- %08X: MUL
        local ra, rb = self.reg[%d], self.reg[%d]
        if ra >= 0x80000000 then ra = ra - 0x100000000 end
        if rb >= 0x80000000 then rb = rb - 0x100000000 end
        self.reg[%d] = math.abs((ra * rb) %% 0x100000000)
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd)
end

RISCV.mult_opcodes[3] = function(pc, inst) -- MULHU
	return ([[
        -- %08X: MULHU
        self.reg[%d] = math.floor((self.reg[%d] * self.reg[%d]) / 0x100000000)
    ]]):format(pc, inst.rd, inst.rs1, inst.rs2)
end

RISCV.mult_opcodes[2] = function(pc, inst) -- MULHSU
	return ([[
        -- %08X: MULHSU
        local ra = self.reg[%d]
        if ra >= 0x80000000 then ra = ra - 0x100000000 end
        local rd = math.floor((ra * self.reg[%d]) / 0x100000000)
        if rd < 0 then rd = rd + 0x100000000 end
        self.reg[%d] = rd
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd)
end

RISCV.mult_opcodes[1] = function(pc, inst) -- MULH
	return ([[
        -- %08X: MULH
        local ra, rb = self.reg[%d], self.reg[%d]
        if ra >= 0x80000000 then ra = ra - 0x100000000 end
        if rb >= 0x80000000 then rb = rb - 0x100000000 end
        local rd = math.floor((ra * rb) / 0x100000000)
        if rd < 0 then rd = rd + 0x100000000 end
        self.reg[%d] = rd
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd)
end

RISCV.mult_opcodes[4] = function(pc, inst) -- DIV
	return ([[
        -- %08X: DIV
        if self.reg[%d] == 0 then
            self.reg[%d] = 0xFFFFFFFF
        else
            local ra, rb = self.reg[%d], self.reg[%d]
            if ra >= 0x80000000 then ra = ra - 0x100000000 end
            if rb >= 0x80000000 then rb = rb - 0x100000000 end
            local res = ra / rb
            if res < 0 then self.reg[%d] = math.ceil(res) + 0x100000000
            else self.reg[%d] = math.floor(res) end
        end
    ]]):format(pc, inst.rs2, inst.rd, inst.rs1, inst.rs2, inst.rd, inst.rd)
end

RISCV.mult_opcodes[5] = function(pc, inst) -- DIVU
	return ([[
        -- %08X: DIVU
        if self.reg[%d] == 0 then self.reg[%d] = 0xFFFFFFFF
        else self.reg[%d] = math.floor(self.reg[%d] / self.reg[%d]) end
    ]]):format(pc, inst.rs2, inst.rd, inst.rd, inst.rs1, inst.rs2)
end

RISCV.mult_opcodes[6] = function(pc, inst) -- REM
	return ([[
        -- %08X: REM
        if self.reg[%d] == 0 then
            self.reg[%d] = self.reg[%d]
        else
            local ra, rb = self.reg[%d], self.reg[%d]
            if ra >= 0x80000000 then ra = ra - 0x100000000 end
            if rb >= 0x80000000 then rb = rb - 0x100000000 end
            local res = math.fmod(ra, rb)
            if res < 0 then self.reg[%d] = math.ceil(res) + 0x100000000
            else self.reg[%d] = math.floor(res) end
        end
    ]]):format(pc, inst.rs2, inst.rd, inst.rs1, inst.rs1, inst.rs2, inst.rd, inst.rd)
end

RISCV.mult_opcodes[7] = function(pc, inst) -- REMU
	return ([[
        -- %08X: REMU
        if self.reg[%d] == 0 then self.reg[%d] = self.reg[%d]
        else self.reg[%d] = self.reg[%d] %% self.reg[%d] end
    ]]):format(pc, inst.rs2, inst.rd, inst.rs1, inst.rd, inst.rs1, inst.rs2)
end

RISCV.atomic_opcodes[0] = function(pc, inst) -- AMOADD.W
	return ([[
        -- %08X: AMOADD.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val = self.mem32[addr / 4]
        self.reg[%d] = val
        self.mem32[addr / 4] = (val + self.reg[%d]) %% 0x100000000
    ]]):format(pc, inst.rs1, inst.rd, inst.rs2)
end

RISCV.atomic_opcodes[1] = function(pc, inst) -- AMOSWAP.W
	return ([[
        -- %08X: AMOSWAP.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val = self.mem32[addr / 4]
        self.mem32[addr / 4] = self.reg[%d]
        self.reg[%d] = val
    ]]):format(pc, inst.rs1, inst.rd, inst.rs2)
end

RISCV.atomic_opcodes[2] = function(pc, inst) -- LR.W
	return ([[
        -- %08X: LR.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction")
        else self.reg[%d] = self.mem32[addr / 4] end
        self.atomic_rs[addr / 4] = true
    ]]):format(pc, inst.rs1, inst.rd)
end

RISCV.atomic_opcodes[3] = function(pc, inst) -- SC.W
	return ([[
        -- %08X: SC.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction")
        elseif self.atomic_rs[addr / 4] then
            self.mem32[addr / 4] = self.reg[%d]
            self.reg[%d] = 0
        else
            self.reg[%d] = 1
        end
        self.atomic_rs[addr / 4] = nil
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd, inst.rd)
end

RISCV.atomic_opcodes[4] = function(pc, inst) -- AMOXOR.W
	return ([[
        -- %08X: AMOXOR.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val = self.mem32[addr / 4]
        self.reg[%d] = val
        self.mem32[addr / 4] = bit32.bxor(val, self.reg[%d])
    ]]):format(pc, inst.rs1, inst.rd, inst.rs2)
end

RISCV.atomic_opcodes[8] = function(pc, inst) -- AMOOR.W
	return ([[
        -- %08X: AMOOR.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val = self.mem32[addr / 4]
        self.reg[%d] = val
        self.mem32[addr / 4] = bit32.bor(val, self.reg[%d])
    ]]):format(pc, inst.rs1, inst.rd, inst.rs2)
end

RISCV.atomic_opcodes[12] = function(pc, inst) -- AMOAND.W
	return ([[
        -- %08X: AMOAND.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val = self.mem32[addr / 4]
        self.reg[%d] = val
        self.mem32[addr / 4] = bit32.band(val, self.reg[%d])
    ]]):format(pc, inst.rs1, inst.rd, inst.rs2)
end

RISCV.atomic_opcodes[16] = function(pc, inst) -- AMOMIN.W
	return ([[
        -- %08X: AMOMIN.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val, val2 = self.mem32[addr / 4], self.reg[%d]
        local ra, rb = val, val2
        if ra >= 0x80000000 then ra = ra - 0x100000000 end
        if rb >= 0x80000000 then rb = rb - 0x100000000 end
        self.reg[%d] = val
        self.mem32[addr / 4] = ra < rb and val or val2
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd)
end

RISCV.atomic_opcodes[20] = function(pc, inst) -- AMOMAX.W
	return ([[
        -- %08X: AMOMAX.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val, val2 = self.mem32[addr / 4], self.reg[%d]
        local ra, rb = val, val2
        if ra >= 0x80000000 then ra = ra - 0x100000000 end
        if rb >= 0x80000000 then rb = rb - 0x100000000 end
        self.reg[%d] = val
        self.mem32[addr / 4] = ra > rb and val or val2
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd)
end

RISCV.atomic_opcodes[24] = function(pc, inst) -- AMOMINU.W
	return ([[
        -- %08X: AMOMINU.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val, val2 = self.mem32[addr / 4], self.reg[%d]
        self.reg[%d] = val
        self.mem32[addr / 4] = val < val2 and val or val2
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd)
end

RISCV.atomic_opcodes[28] = function(pc, inst) -- AMOMAXU.W
	return ([[
        -- %08X: AMOMAXU.W
        local addr = self.reg[%d]
        if addr %% 4 ~= 0 then error("unaligned AMO instruction") end
        local val, val2 = self.mem32[addr / 4], self.reg[%d]
        self.reg[%d] = val
        self.mem32[addr / 4] = val > val2 and val or val2
    ]]):format(pc, inst.rs1, inst.rs2, inst.rd)
end

RISCV.traces = setmetatable({}, {
	__index = function(trace, pc)
		local self = RISCV
		local base = pc
		local chunk = ([[
    local math, bit32 = math, bit32
    return function(self)
        if self.halt then return end
        self.branches = self.branches + 1
        if self.branches > self.branchesLimit then coroutine.yield() end
        self.pc = %d
    ]]):format(pc)
		repeat
			if pc >= 33554432 then
				error("pc out of bounds")
			end
			if pc % 4 ~= 0 then
				error(("unaligned jump to %08X"):format(pc))
			end
			local inst = self.mem32[pc / 4]
			if inst == 0xc0001073 then
				chunk = chunk .. "self.halt = true\n"
				break
			end
			pc = pc + 4
			local mode = opcode_modes[bit32.band(inst, 0x7F)]
			if not mode then
				error(("Unknown opcode %02X at %08X"):format(bit32.band(inst, 0x7F), pc - 4))
				return
			end
			inst = mode(inst)
			--print(textutils.serialize(inst))
			local f = self.opcodes[inst.opcode]
			local op, isBranch
			if type(f) == "function" then
				op, isBranch = f(pc, inst)
			elseif type(f) == "table" then
				if not f[inst.funct3] then
					print("Unknown function " .. inst.funct3)
				elseif inst.opcode == 0x33 and bit32.btest(inst.funct7, 1) then
					op, isBranch = self.mult_opcodes[inst.funct3](pc, inst)
				elseif inst.opcode == 0x2F and inst.funct3 == 2 then
					op, isBranch = self.atomic_opcodes[bit32.rshift(inst.funct7, 2)](pc, inst)
				else
					op, isBranch = f[inst.funct3](pc, inst)
				end
			else
				error("Unknown opcode " .. inst.opcode .. " at " .. (pc - 4))
			end
			chunk = chunk .. op
		until isBranch
		chunk = chunk .. "end"
		--print(chunk)
		local fn = assert(load(chunk, ("@%08X"):format(base)))()
		trace[base] = fn
		return fn
	end,
})

function RISCV:run(cycles)
	self.branches = 0
	self.branchesLimit = cycles
	if self.coro then
		assert(coroutine.resume(self.coro))
	else
		self.coro = coroutine.create(self.traces[self.pc])
		assert(coroutine.resume(self.coro, self))
	end
	if coroutine.status(self.coro) == "dead" then
		self.coro = nil
	end
end

function RISCV:call(addr, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
	--print(("Call: %08x"):format(addr))
	self.coro = nil
	local oldra = self.reg[1]
	local oldreg = {}
	local oldpc = self.pc
	if arg1 then
		oldreg[1], self.reg[10] = self.reg[10], arg1
	end
	if arg2 then
		oldreg[2], self.reg[11] = self.reg[11], arg2
	end
	if arg3 then
		oldreg[3], self.reg[12] = self.reg[12], arg3
	end
	if arg4 then
		oldreg[4], self.reg[13] = self.reg[13], arg4
	end
	if arg5 then
		oldreg[5], self.reg[14] = self.reg[14], arg5
	end
	if arg6 then
		oldreg[6], self.reg[15] = self.reg[15], arg6
	end
	if arg7 then
		oldreg[7], self.reg[16] = self.reg[16], arg7
	end
	self.reg[1] = oldpc
	self.pc = addr
	local oldtrace = rawget(self.traces, oldpc)
	self.traces[oldpc] = function()
		self.pc = oldpc
	end
	while self.pc ~= oldpc do
		if self.halt then
			return
		end
		self:run(1)
	end
	self.traces[oldpc] = oldtrace
	local res = self.reg[10]
	self.reg[1] = oldra
	for k, v in pairs(oldreg) do
		self.reg[k + 9] = v
	end
	return res
end

if not _G._TRACEBACK then
	_G.pcall = function(f, ...)
		return xpcall(f, debug.traceback, ...)
	end
	local resume = coroutine.resume
	function coroutine.resume(coro, ...)
		local res = table.pack(resume(coro, ...))
		if not res[1] then
			res[2] = debug.traceback(coro, res[2])
		end
		return table.unpack(res, 1, res.n)
	end
	_G._TRACEBACK = true
end

local luastate = require("luastate")
local dynload = require("dynload")

function RISCV.resolveSymbol(addr, modules)
	local sym, symaddr = "??", 0
	for k, m in pairs(modules) do
		for _, t in pairs(m.elf.sections) do
			if t.symbols then
				for _, s in ipairs(t.symbols) do
					if
						s.type == "FUNC"
						and addr >= m.baseAddress + s.value
						and (
							m.baseAddress + s.value > symaddr
							or (m.baseAddress + s.value == symaddr and s.binding ~= "LOCAL")
						)
					then
						sym, symaddr = k .. ":" .. s.name, m.baseAddress + s.value
					end
				end
			end
		end
	end
	return sym, symaddr
end

function RISCV.dump(cpu, modules, endAddr)
	local msg = ""
	do
		local sym, symaddr = RISCV.resolveSymbol(cpu.pc, modules)
		msg = msg .. ("\npc=%08x (%s+%x)\n"):format(cpu.pc, sym, cpu.pc - symaddr)
	end
	for y = 0, 31, 4 do
		for x = 0, 3 do
			msg = msg .. ("x%d=%08x "):format(y + x, cpu.reg[y + x])
		end
		msg = msg .. "\n"
	end
	msg = msg .. "\nLoaded modules:\n"
	for k, v in pairs(modules) do
		msg = msg .. ("%08x  %s\n"):format(v.baseAddress, k)
	end
	msg = msg .. "\nStack trace (estimate):\n"
	do
		local sym, symaddr = RISCV.resolveSymbol(cpu.pc, modules)
		msg = msg .. ("%08x  %s+%x\n"):format(cpu.pc, sym, cpu.pc - symaddr)
	end
	do
		local sym, symaddr = RISCV.resolveSymbol(cpu.reg[1], modules)
		msg = msg .. ("%08x  %s+%x\n"):format(cpu.reg[1], sym, cpu.reg[1] - symaddr)
	end
	for sp = cpu.reg[2] / 4, 0x7FBFFF do
		local v = cpu.mem32[sp]
		if v > 0 and v < endAddr and v % 4 == 0 then
			local inst = cpu.mem32[v / 4 - 1]
			local op = bit32.band(inst, 0x7F)
			if op == 0x6F or op == 0x67 then
				inst = opcode_modes[op](inst)
				if inst.rd == 1 then
					local sym, symaddr = RISCV.resolveSymbol(v, modules)
					msg = msg .. ("%08x  %s+%x\n"):format(v, sym, v - symaddr)
				end
			end
		end
	end
	return msg
end

function RISCV.loadmodule(name)
	RISCV.reg[1] = 0x1FFFFFC -- return address (trap)
	RISCV.mem32[0x7FFFFF] = 0x00100073 -- EBREAK
	RISCV.reg[2] = 0x1FF0000 -- stack pointer
	-- thread pointer setup
	RISCV.reg[4] = 0x2000800
	RISCV.mem32[0x8001FE] = 0x2000800
	RISCV.mem32[0x8001FF] = 0
	RISCV.mem32[0x800200] = 0
	RISCV.modules = {}
	RISCV.endAddr = dynload(RISCV, RISCV.modules, name, 0)
	local entrypoint
	--for k, v in pairs(modules) do print(("%08x"):format(v.baseAddress), k) end
	for k, v in pairs(RISCV.modules[name].symbols) do
		if k:match("^luaopen_") then
			entrypoint = v
		end
	end
	if RISCV.modules["libc.so.6"] and RISCV.modules["libc.so.6"].symbols["__libc_early_init"] then
		local ok, err = xpcall(function()
			RISCV:call(RISCV.modules["libc.so.6"].symbols["__libc_early_init"], 1)
		end, function(msg)
			return msg .. "\n" .. dump(RISCV, RISCV.modules, RISCV.endAddr)
		end)
		if not ok then
			error(err)
		end
	end
	local nres
	local state = luastate.call_state(RISCV, luastate.cclosure(entrypoint), "test")
	local ok, err = xpcall(function()
		nres = RISCV:call(entrypoint, state)
	end, function(msg)
		return msg .. "\n" .. dump(RISCV, RISCV.modules, RISCV.endAddr)
	end)
	if not ok then
		error(err)
	end
	local st = luastate.states[state].stack
	local res = { table.unpack(st, st.n - nres + 1, st.n) }
	for i = 1, nres do
		res[i] = luastate.lua_value(res[i], RISCV)
	end
	return table.unpack(res, 1, nres)
end

if ... ~= "riscv" then
	local name, fn = ...
	local test = RISCV.loadmodule(name)
	local ok, err = xpcall(function(...)
		require("cc.pretty").pretty_print(test[fn](...))
		--print(test.crc32()(os.about()))
	end, function(msg)
		return msg .. "\n" .. RISCV.dump(RISCV, RISCV.modules, RISCV.endAddr)
	end, select(3, ...))
	if not ok then
		error(err)
	end
	return
end

_G.CloverOS = setmetatable(API, {
	__newindex = function()
		error("CloverOS API is read-only")
	end,
})
_G.kernel = setmetatable(kernel, {
	__newindex = function()
		error("kernel API is read-only")
	end,
})
_G.RISCV = setmetatable(RISCV, {
	__newindex = function()
		error("RISCV API is read-only")
	end,
})
local function DISK_ROOT()
	local function isCloverRoot(root)
		return fs.exists(root .. "/CloverOS_API.lua") and fs.exists(root .. "/boot/kernel.lua")
	end

	if isCloverRoot("") or isCloverRoot("/") then
		return ""
	end

	for i = 0, 99 do
		local root = "/disk" .. (i == 1 and "" or i)
		if isCloverRoot(root) then
			return root
		end
	end

	return nil
end

local root = DISK_ROOT()
if not root then
	error("CloverOS root not found")
end

local driverRoot = root .. "/boot/kernel/drivers"

if not fs.exists(driverRoot) then
	fs.makeDir(driverRoot)

	local exampleDriver = [[
return {
  id = "example_driver",

  init = function(kernel)
    kernel.info("Example driver initialized")
  end,

  shutdown = function(kernel)
    kernel.info("Example driver shutdown")
  end
}
]]

	local h = fs.open(fs.combine(driverRoot, "example.lua"), "w")
	h.write(exampleDriver)
	h.close()
end

local function loadDriver(path)
	local driver, err = kernel.driver.load(path)

	if not driver then
		kernel.warn("Driver load failed:", path, err)
		return
	end

	kernel.info("Loaded driver:", driver.id or path)
end

local function loadDrivers(dir)
	if not fs.exists(dir) then
		return
	end

	for _, name in ipairs(fs.list(dir)) do
		local path = fs.combine(dir, name)

		if fs.isDir(path) then
			local initPath = fs.combine(path, "init.lua")

			if fs.exists(initPath) then
				loadDriver(initPath)
			else
				loadDrivers(path)
			end
		else
			local lower = name:lower()

			if
				lower:sub(-4) == ".lua"
				or lower:sub(-4) == ".sys"
				or lower:sub(-4) == ".dll"
				or lower:sub(-5) == ".luau"
			then
				loadDriver(path)
			end
		end
	end
end

loadDrivers(driverRoot)

local startupPath = "/startup.lua"

if settings.get("envType") == "craftos" and not fs.exists(startupPath) then
	local h = fs.open(startupPath, "w")

	h.write([[
print("Setting up CraftOS environment...")

pcall(function()
	shell.run("attach left drive")
	shell.run("attach right speaker")
	shell.run("attach back monitor")

	if mounter and mounter.mount then
		mounter.mount("/CloverOS_Disks/0", "C:\\CloverOS_Disks\\0")
	end

	if disk and disk.insertDisk then
		disk.insertDisk("left", "C:\\CloverOS_Disks\\0")
	end
end)

local diskStartup = "/disk/startup.lua"

if fs.exists(diskStartup) and diskStartup ~= shell.getRunningProgram() then
	shell.run(diskStartup)
end
]])

	h.close()
end

local cloverOS = safeFindOS("CloverOS_OS.lua")
shell.run(cloverOS)
