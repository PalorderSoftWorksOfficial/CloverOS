-- CloverOS kernel: journal, service manager, config store, app registry.
-- Boot flow contract (tests/boot_driver.lua): the journal file
-- var/log/kernel.log must contain the marker lines written during startup,
-- so keep message text for prompt stages stable across rewrites.
local version = dofile(fs.combine(CLOVER_ROOT, "etc/version.lua"))

local kernel = {}

kernel._name = "CloverOS Kernel"
kernel._version = version.kernelVersion()
kernel._startedAt = os.clock()
kernel._services = {}
kernel._serviceOrder = {}
kernel._journal = {}
kernel._journalMax = 200
kernel._configDir = fs.combine(CLOVER_ROOT, "var/lib/clover")
kernel._logFile = fs.combine(CLOVER_ROOT, "var/log/kernel.log")
kernel._state = {
	booted = false,
	shutdownRequested = false,
	rebootRequested = false,
}

function kernel.name()
	return kernel._name
end

function kernel.version()
	return kernel._version
end

function kernel.uptime()
	return os.clock() - kernel._startedAt
end

function kernel.sleep(seconds)
	return sleep(tonumber(seconds) or 0)
end

-- ---------- journal ----------
local function journalTime()
	return textutils.formatTime(os.time(), true)
end

function kernel.log(level, message)
	level = tostring(level or "info"):upper()
	message = tostring(message or "")
	local line = string.format("[%s] [%s] %s", level, journalTime(), message)
	kernel._journal[#kernel._journal + 1] = line
	while #kernel._journal > kernel._journalMax do
		table.remove(kernel._journal, 1)
	end
	local ok = pcall(function()
		fs.makeDir(fs.getDir(kernel._logFile))
		local h = fs.open(kernel._logFile, "a")
		if h then
			h.writeLine(line)
			h.close()
		end
	end)
	if not ok then
		-- logging must never break the caller
	end
	return line
end

function kernel.info(message)
	return kernel.log("info", message)
end

function kernel.warn(message)
	return kernel.log("warn", message)
end

function kernel.error(message)
	return kernel.log("error", message)
end

function kernel.debug(message)
	return kernel.log("debug", message)
end

-- returns the in-memory journal; optional minimum level filters entries
local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

function kernel.journal(minLevel)
	local min = LEVELS[tostring(minLevel or "debug"):lower()] or 1
	local copy = {}
	for _, line in ipairs(kernel._journal) do
		local level = line:match("^%[([%a]+)%]")
		if (LEVELS[tostring(level or "info"):lower()] or 2) >= min then
			copy[#copy + 1] = line
		end
	end
	return copy
end

function kernel.panic(message, err)
	local detail = tostring(err or "")
	kernel.log("error", "panic: " .. tostring(message) .. (detail ~= "" and (" (" .. detail .. ")") or ""))
	printError("CloverOS kernel panic: " .. tostring(message))
	if detail ~= "" and detail ~= "nil" then
		printError(detail)
	end
	printError("System halted. Reboot to recover.")
	while true do
		local ev = os.pullEventRaw()
		if ev == "key" or ev == "terminate" then
			os.reboot()
		end
	end
end

function kernel.shutdown()
	kernel._state.shutdownRequested = true
	kernel.info("shutdown requested")
	for i = #kernel._serviceOrder, 1, -1 do
		kernel.service.stop(kernel._serviceOrder[i])
	end
	return os.shutdown()
end

function kernel.reboot()
	kernel._state.rebootRequested = true
	kernel.info("reboot requested")
	return os.reboot()
end

-- True when an error object is the platform's termination signal rather
-- than a real fault: os.shutdown/os.reboot unwind the coroutine, and the
-- CraftOS signal arrives as nil while hosts may report "Terminated".
function kernel.isShutdown(err)
	if err == nil or err == "Terminated" then
		return true
	end
	return type(err) == "table" and err.shutdown == true
end

function kernel.status()
	return {
		name = kernel._name,
		version = kernel._version,
		uptime = kernel.uptime(),
		booted = kernel._state.booted,
		computerId = os.getComputerID(),
		label = os.getComputerLabel(),
		services = kernel.service.list(),
	}
end

function kernel.peripherals()
	local out = {}
	if peripheral and peripheral.getNames then
		for _, name in ipairs(peripheral.getNames()) do
			out[#out + 1] = { name = name, type = peripheral.getType(name) }
		end
	end
	return out
end

-- ---------- services ----------
kernel.service = {}

local function serviceByName(name)
	return kernel._services[name]
end

function kernel.service.register(name, definition)
	if type(name) ~= "string" or name == "" then
		return nil, "invalid service name"
	end
	definition = definition or {}
	if not kernel._services[name] then
		kernel._serviceOrder[#kernel._serviceOrder + 1] = name
	end
	kernel._services[name] = {
		name = name,
		start = definition.start,
		stop = definition.stop,
		restart = definition.restart,
		order = definition.order or 100,
		started = false,
	}
	table.sort(kernel._serviceOrder, function(a, b)
		local oa = kernel._services[a] and kernel._services[a].order or 100
		local ob = kernel._services[b] and kernel._services[b].order or 100
		if oa == ob then
			return a < b
		end
		return oa < ob
	end)
	return true
end

function kernel.service.start(name)
	local svc = serviceByName(name)
	if not svc then
		return nil, "unknown service: " .. tostring(name)
	end
	if svc.started then
		return true
	end
	if type(svc.start) == "function" then
		local ok, err = pcall(svc.start)
		if not ok then
			kernel.warn("service " .. name .. " failed to start: " .. tostring(err))
			return nil, tostring(err)
		end
	end
	svc.started = true
	kernel.info("service started: " .. name)
	return true
end

function kernel.service.stop(name)
	local svc = serviceByName(name)
	if not svc then
		return nil, "unknown service: " .. tostring(name)
	end
	if not svc.started then
		return true
	end
	if type(svc.stop) == "function" then
		pcall(svc.stop)
	end
	svc.started = false
	kernel.info("service stopped: " .. name)
	return true
end

function kernel.service.restart(name)
	local svc = serviceByName(name)
	if not svc then
		return nil, "unknown service: " .. tostring(name)
	end
	if type(svc.restart) == "function" then
		local ok, err = pcall(svc.restart)
		if not ok then
			kernel.warn("service " .. name .. " failed to restart: " .. tostring(err))
			return nil, tostring(err)
		end
		svc.started = true
		kernel.info("service restarted: " .. name)
		return true
	end
	kernel.service.stop(name)
	return kernel.service.start(name)
end

function kernel.service.list()
	local names = {}
	for _, name in ipairs(kernel._serviceOrder) do
		names[#names + 1] = name
	end
	return names
end

function kernel.service.isRunning(name)
	local svc = serviceByName(name)
	return svc ~= nil and svc.started
end

function kernel.service.status(name)
	local svc = serviceByName(name)
	if not svc then
		return nil, "unknown service: " .. tostring(name)
	end
	return {
		name = svc.name,
		running = svc.started,
		order = svc.order,
	}
end

-- ---------- config ----------
kernel.config = {}

function kernel.config.path(name)
	return fs.combine(kernel._configDir, tostring(name) .. ".cfg")
end

kernel._configs = {}

function kernel.config.load(name)
	local path = kernel.config.path(name)
	if not fs.exists(path) then
		return nil, "config not found"
	end
	local h = fs.open(path, "r")
	if not h then
		return nil, "cannot open config"
	end
	local data = h.readAll()
	h.close()
	local ok, value = pcall(textutils.unserialize, data)
	if not ok or type(value) ~= "table" then
		return nil, "invalid config data"
	end
	kernel._configs[name] = value
	return value
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
	kernel._configs[name] = {}
	for k, v in pairs(defaults or {}) do
		kernel._configs[name][k] = v
	end
	return kernel._configs[name]
end

function kernel.config.save(name)
	local cfg = kernel._configs[name]
	if not cfg then
		return nil, "nothing to save"
	end
	fs.makeDir(fs.getDir(kernel.config.path(name)))
	local h = fs.open(kernel.config.path(name), "w")
	if not h then
		return nil, "cannot write config"
	end
	h.write(textutils.serialize(cfg))
	h.close()
	return true
end

function kernel.config.get(name, key, default)
	local cfg = kernel._configs[name]
	if not cfg or cfg[key] == nil then
		return default
	end
	return cfg[key]
end

function kernel.config.set(name, key, value)
	local cfg = kernel.config.loadOrCreate(name, {})
	cfg[key] = value
	return true
end

function kernel.config.delete(name)
	kernel._configs[name] = nil
	if fs.exists(kernel.config.path(name)) then
		fs.delete(kernel.config.path(name))
	end
	return true
end

-- ---------- apps ----------
kernel._apps = {}
kernel.app = {}

function kernel.app.register(name, program, meta)
	if type(name) ~= "string" or name == "" then
		return nil, "invalid app name"
	end
	if type(program) ~= "string" or program == "" then
		return nil, "invalid app path"
	end
	kernel._apps[name] = {
		name = name,
		program = program,
		meta = meta or {},
	}
	return true
end

function kernel.app.get(name)
	return kernel._apps[name]
end

function kernel.app.list()
	local names = {}
	for name in pairs(kernel._apps) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function kernel.app.launch(name, ...)
	local app = kernel._apps[name]
	if not app then
		return nil, "app not registered: " .. tostring(name)
	end
	if not fs.exists(app.program) then
		return nil, "app program missing: " .. app.program
	end
	local ok, err = pcall(shell.run, app.program, ...)
	if not ok then
		kernel.error("app " .. name .. " crashed: " .. tostring(err))
		return nil, tostring(err)
	end
	return true
end

function kernel.app.meta(name)
	local app = kernel._apps[name]
	if not app then
		return nil
	end
	return app.meta
end

-- ---------- boot ----------
function kernel.boot()
	if kernel._state.booted then
		return true
	end
	fs.makeDir(kernel._configDir)
	fs.makeDir(fs.getDir(kernel._logFile))
	kernel.info("CloverOS kernel " .. kernel._version .. " booting (computer " .. os.getComputerID() .. ")")
	for _, name in ipairs(kernel.service.list()) do
		kernel.service.start(name)
	end
	kernel._state.booted = true
	kernel.info("boot sequence complete")
	return true
end

return kernel
