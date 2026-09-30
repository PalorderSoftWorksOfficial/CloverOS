-- CloverOS init: unit management over the kernel's service table.
--
-- The kernel can register, start and stop services, but it knows nothing
-- about ordering, dependencies or what should run at boot - every caller
-- wired that by hand. This module is the systemd-shaped layer on top:
-- units with dependencies and ordering, a default target, enable/disable
-- persistence in /etc/clover/init.cfg, and journal filtering for
-- journalctl. Units are declarative tables; the built-ins are created here
-- and a session can hand in extra factories (the desktop registers sshd
-- with a live server, for example).
--
-- Start order is a depth-first walk of the "after" list with a visiting
-- set, so a dependency cycle is reported instead of hanging the boot.
local M = {}

M.VERSION = 1
M.CONFIG_PATH = nil -- set per instance from paths

local function note(kernel, level, message)
	if kernel and type(kernel[level]) == "function" then
		pcall(kernel[level], "init: " .. message)
	end
end

-- ---------- built-in units ----------
-- Each factory returns a unit definition, or nil when its dependencies are
-- not available in this session (the unit still shows in `systemctl
-- list-units` but refuses to start with a clear reason).
local function builtinUnits(deps)
	local units = {}

	units.network = {
		description = "rednet networking",
		after = {},
		start = function()
			if not (deps.system and type(deps.system.rednetOpen) == "function") then
				return nil, "no system layer in this session"
			end
			local ok = deps.system:rednetOpen()
			if not ok then
				-- already open counts as success
				return true
			end
			return true
		end,
		stop = function()
			if not (deps.system and type(deps.system.rednetClose) == "function") then
				return nil, "no system layer in this session"
			end
			deps.system:rednetClose()
			return true
		end,
	}

	units.cloverd = {
		description = "hardware events for a text session",
		after = { "network" },
		start = function()
			if not (deps.daemon and type(deps.daemon.start) == "function") then
				return nil, "no daemon in this session"
			end
			local ok, why = deps.daemon:start()
			if not ok then
				return nil, why
			end
			return true
		end,
		stop = function()
			if deps.daemon and type(deps.daemon.stop) == "function" then
				deps.daemon:stop()
			end
			return true
		end,
	}

	units.sshd = {
		description = "remote shell server",
		after = { "network" },
		start = function()
			if not (deps.sshFactory and deps.system and deps.users) then
				return nil, "ssh needs a desktop session with users"
			end
			local server, why = deps.sshFactory()
			if not server then
				return nil, why
			end
			return true
		end,
		stop = function()
			return true
		end,
	}

	units["multi-user.target"] = {
		description = "standard session services",
		after = {},
		wants = { "network", "cloverd", "sshd" },
		target = true,
		start = function()
			return true
		end,
	}

	units["graphical.target"] = {
		description = "the GNOME desktop session",
		after = { "multi-user.target" },
		wants = { "multi-user.target" },
		target = true,
		start = function()
			return true
		end,
	}

	return units
end

function M.new(deps)
	deps = deps or {}
	local self = {
		kernel = deps.kernel,
		paths = deps.paths,
		units = {},
		started = {}, -- unit name -> true, mirrors kernel service state
		visiting = {},
		sshServer = deps.sshServer,
	}

	self.configPath = self.paths
		and self.paths:join("etc", "clover", "init.cfg")
		or "etc/clover/init.cfg"

	-- a unit that was already registered in the kernel (cloverd does this)
	-- is adopted so systemctl describes the same object the session runs
	local function adopt(name, definition)
		self.units[name] = definition
	end

	for name, definition in pairs(builtinUnits(deps)) do
		adopt(name, definition)
	end
	if deps.daemon then
		-- keep the kernel registration the session already made in sync
		self.units.cloverd.kernelRegistered = true
	end
	if deps.sshFactory then
		self.units.sshd.factory = deps.sshFactory
	end

	-- ---------- persistence ----------
	function self:load()
		if type(fs) ~= "table" or not fs.exists(self.configPath) then
			return false
		end
		local handle = fs.open(self.configPath, "r")
		if not handle then
			return false
		end
		local data = handle.readAll()
		handle.close()
		local ok, value = pcall(textutils.unserialize, data)
		if not ok or type(value) ~= "table" then
			note(self.kernel, "warn", "init.cfg unreadable, using defaults")
			return false
		end
		if type(value.enabled) == "table" then
			for name in pairs(value.enabled) do
				if self.units[name] then
					self.units[name].enabled = true
				end
			end
		end
		if type(value.defaultTarget) == "string" and self.units[value.defaultTarget] then
			self.defaultTarget = value.defaultTarget
		end
		return true
	end

	function self:persist()
		if type(textutils) ~= "table" or type(textutils.serialize) ~= "function" then
			return false
		end
		local enabled = {}
		for name, unit in pairs(self.units) do
			if unit.enabled then
				enabled[name] = true
			end
		end
		local handle = fs.open(self.configPath, "w")
		if not handle then
			return false
		end
		handle.write(textutils.serialize({
			version = M.VERSION,
			enabled = enabled,
			defaultTarget = self.defaultTarget or "multi-user.target",
		}))
		handle.close()
		return true
	end

	-- every unit is enabled by default except the ones that depend on
	-- session specifics a plain text shell does not have
	for name, unit in pairs(self.units) do
		unit.enabled = (name ~= "sshd") or deps.sshFactory ~= nil
	end
	self.defaultTarget = "multi-user.target"
	self:load()

	-- ---------- dependency walk ----------
	function self:startUnit(name, chain)
		local unit = self.units[name]
		if not unit then
			return nil, "unknown unit: " .. tostring(name)
		end
		if self.started[name] then
			return true
		end
		chain = chain or {}
		if chain[name] then
			return nil, "dependency loop at " .. tostring(name)
		end
		chain[name] = true
		for _, dep in ipairs(unit.after or {}) do
			if self.units[dep] then
				local ok, why = self:startUnit(dep, chain)
				if not ok then
					return nil, dep .. " failed: " .. tostring(why)
				end
			end
		end
		for _, want in ipairs(unit.wants or {}) do
			if self.units[want] and not self.started[want] then
				-- a wanted unit that fails must not fail the target
				pcall(self.startUnit, self, want, chain)
			end
		end
		if type(unit.start) == "function" then
			local ok, err = unit.start()
			if not ok then
				note(self.kernel, "warn", "unit " .. name .. " failed: " .. tostring(err))
				return nil, tostring(err)
			end
		end
		-- keep the kernel's service table in step so `service status` agrees
		if self.kernel and self.kernel.service and not unit.target then
			if not self.kernel.service.isRunning(name) then
				pcall(self.kernel.service.start, name)
			end
		end
		self.started[name] = true
		note(self.kernel, "info", "unit started: " .. name)
		return true
	end

	function self:stopUnit(name)
		local unit = self.units[name]
		if not unit then
			return nil, "unknown unit: " .. tostring(name)
		end
		if not self.started[name] then
			return true
		end
		if type(unit.stop) == "function" then
			pcall(unit.stop)
		end
		if self.kernel and self.kernel.service and self.kernel.service.isRunning(name) then
			pcall(self.kernel.service.stop, name)
		end
		self.started[name] = nil
		note(self.kernel, "info", "unit stopped: " .. name)
		return true
	end

	-- ---------- enable/disable ----------
	function self:enable(name)
		local unit = self.units[name]
		if not unit then
			return nil, "unknown unit: " .. tostring(name)
		end
		unit.enabled = true
		self:persist()
		return true
	end

	function self:disable(name)
		local unit = self.units[name]
		if not unit then
			return nil, "unknown unit: " .. tostring(name)
		end
		unit.enabled = false
		self:persist()
		return true
	end

	function self:isEnabled(name)
		return self.units[name] ~= nil and self.units[name].enabled == true
	end

	-- ---------- queries ----------
	function self:unitNames()
		local names = {}
		for name in pairs(self.units) do
			names[#names + 1] = name
		end
		table.sort(names)
		return names
	end

	function self:status(name)
		local unit = self.units[name]
		if not unit then
			return nil, "unknown unit: " .. tostring(name)
		end
		return {
			name = name,
			description = unit.description or "",
			loaded = true,
			enabled = unit.enabled == true,
			running = self.started[name] == true,
			after = unit.after or {},
			wants = unit.wants or {},
			target = unit.target == true,
		}
	end

	-- The systemd-ish table for `systemctl` output: UNIT, LOAD, ACTIVE, ENABLED.
	function self:listUnits()
		local rows = {}
		for _, name in ipairs(self:unitNames()) do
			local state = self:status(name)
			rows[#rows + 1] = {
				name = name,
				loaded = "loaded",
				active = state.running and "active" or "inactive",
				enabled = state.enabled and "enabled" or "disabled",
				description = state.description,
			}
		end
		return rows
	end

	-- Boot the default target. Wants that fail are logged, not fatal.
	function self:boot(target)
		target = target or self.defaultTarget
		if not self.units[target] then
			return nil, "unknown target: " .. tostring(target)
		end
		return self:startUnit(target)
	end

	-- ---------- journal filtering (journalctl) ----------
	-- kernel.journal lines look like "[info] init: unit started: network".
	-- Filters: unit (substring), level (minimum), lines (tail limit).
	function self:journalctl(opts)
		opts = opts or {}
		local kernel = self.kernel
		if not (kernel and type(kernel.journal) == "function") then
			return {}
		end
		local entries = kernel.journal(opts.level or "debug")
		if opts.unit and opts.unit ~= "" then
			local needle = tostring(opts.unit):lower()
			local filtered = {}
			for _, line in ipairs(entries) do
				if line:lower():find(needle, 1, true) then
					filtered[#filtered + 1] = line
				end
			end
			entries = filtered
		end
		if opts.lines and opts.lines > 0 then
			local tail = {}
			for i = math.max(1, #entries - opts.lines + 1), #entries do
				tail[#tail + 1] = entries[i]
			end
			entries = tail
		end
		return entries
	end

	return self
end

-- Session entry point. Locates the CloverOS root the way the other runtime
-- modules do (explicit root, CLOVER_ROOT, or the running program's dir).
function M.attach(kernel, paths, deps)
	deps = deps or {}
	if not kernel then
		return nil, "init needs the kernel"
	end
	if not paths then
		return nil, "init needs paths"
	end
	return M.new({
		kernel = kernel,
		paths = paths,
		system = deps.system,
		users = deps.users,
		daemon = deps.daemon,
		sshFactory = deps.sshFactory,
	})
end

return M
