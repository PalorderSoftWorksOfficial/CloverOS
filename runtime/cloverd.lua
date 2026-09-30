-- cloverd: the hardware daemon for a text-mode session.
--
-- The GNOME session is already an event loop, so runtime/desktop.lua hands its
-- events straight to the system layer. A text session has no such loop: it
-- sits in read() waiting for a line, and os.pullEventRaw cannot be filtered
-- without discarding the events it skips, so pulling from a command or a
-- prompt would eat the keystrokes the user has already typed. That is why
-- `net` in a terminal works by rescanning the hardware directly, and why the
-- rednet inbox only filled during a desktop session.
--
-- cloverd closes that gap the way CC:Tweaked intends. A coroutine calls
-- os.queueEvents, which redirects the program's events to that coroutine's
-- queue. cloverd then owns every event: hardware events go to the system
-- layer, and everything else is put back with os.queueEvent so the shell
-- waiting in read() still sees it.
--
-- The forwarding is the risky part, because how a host routes an event queued
-- from inside a redirected coroutine is not defined identically everywhere.
-- If an event comes straight back instead of reaching the shell, cloverd
-- would spin on the user's own typing, so it watches for that and switches
-- itself off rather than taking the terminal with it.
local M = {}
M.__index = M

local QUEUE_NAME = "cloverd"

function M.new(deps)
	deps = deps or {}
	return setmetatable({
		system = deps.system,
		kernel = deps.kernel,
		queueName = QUEUE_NAME,
		running = false,
		thread = nil,
		-- counts, so `service status cloverd` and the journal can say
		-- whether the daemon is actually doing anything
		handled = 0,
		forwarded = 0,
		disabledReason = nil,
		lastForwarded = nil,
		repeats = 0,
	}, M)
end

local function note(daemon, level, message)
	local kernel = daemon.kernel
	if kernel and type(kernel[level]) == "function" then
		pcall(kernel[level], "cloverd: " .. message)
	end
end

-- Can this host redirect its event queue at all? CC:Tweaked can; a bare
-- interpreter or the test harness may not, and the caller carries on without
-- the daemon rather than failing the session.
function M.available()
	return type(os) == "table"
		and type(os.queueEvents) == "function"
		and type(os.queueEvent) == "function"
		and type(os.pullEvent) == "function"
		and type(coroutine) == "table"
		and type(coroutine.create) == "function"
end

-- Put an event back where the rest of the program can see it. Returns false
-- when the host offers no way to do it, which is the daemon's cue to stop.
function M:forward(ev)
	if type(os.queueEvent) ~= "function" then
		return false
	end
	local args = {}
	for i = 1, #ev do
		args[i] = ev[i]
	end
	os.queueEvent(table.unpack(args, 1, #ev))
	self.forwarded = self.forwarded + 1
	self.lastForwarded = ev
	return true
end

-- Detect an event that we just handed back and then received again, which
-- means the host is looping it to this coroutine instead of to the program.
-- Three in a row is enough to be sure without punishing a coincidence.
function M:notLooping(ev)
	if not self.lastForwarded or #self.lastForwarded ~= #ev then
		self.repeats = 0
		return true
	end
	local same = true
	for i = 1, #ev do
		if ev[i] ~= self.lastForwarded[i] then
			same = false
			break
		end
	end
	if not same then
		self.repeats = 0
		return true
	end
	self.repeats = self.repeats + 1
	return self.repeats < 3
end

function M:loop()
	-- from here on every event the program produces is queued to this
	-- coroutine instead of to the shell
	os.queueEvents(self.queueName)
	while self.running do
		local pulled = { os.pullEvent(self.queueName) }
		local kind = pulled[1]
		if type(kind) ~= "string" then
			-- a host that gives nothing back would spin, so stop
			self.running = false
			break
		end
		if kind == "terminate" then
			-- the shell has to see this too, or it would hang on the prompt
			self:forward(pulled)
			self.running = false
			break
		end
		local consumed = self.system and self.system:dispatch(pulled) or false
		if consumed then
			self.handled = self.handled + 1
			if self.system and type(self.system.save) == "function" then
				self.system:save()
			end
			self.repeats = 0
		else
			if not self:notLooping(pulled) then
				self:disable("events were returned to the daemon instead of the shell")
				break
			end
			if not self:forward(pulled) then
				self:disable("this host cannot return an event to the program")
				break
			end
		end
	end
end

function M:disable(reason)
	self.running = false
	self.disabledReason = tostring(reason)
	note(self, "warn", "disabled: " .. self.disabledReason)
end

-- Returns true when the daemon is running, or nil plus a reason when the
-- host cannot support it. Starting twice is harmless.
function M:start()
	if self.thread then
		return self.running
	end
	if not M.available() then
		return nil, "this host cannot redirect the event queue"
	end
	if not self.system then
		return nil, "no system layer to service"
	end
	self.running = true
	self.thread = coroutine.create(function()
		self:loop()
	end)
	local ok, err = coroutine.resume(self.thread)
	if not ok then
		self.running = false
		self.thread = nil
		return nil, tostring(err)
	end
	note(self, "info", "started (text sessions now see hardware events)")
	return true
end

function M:stop()
	if not self.thread then
		return true
	end
	self.running = false
	-- the coroutine is parked in pullEvent; nothing can wake it safely, so
	-- it is left to be collected once the session ends
	self.thread = nil
	return true
end

function M:status()
	return {
		running = self.running,
		handled = self.handled,
		forwarded = self.forwarded,
		disabled = self.disabledReason,
	}
end

-- Register cloverd as a kernel service so `service list` and
-- `service status cloverd` describe it alongside everything else. An
-- already-built daemon can be passed in so the session and the service
-- entry describe the same thing.
function M.register(kernel, system, existing)
	if not kernel or type(kernel.service) ~= "table"
		or type(kernel.service.register) ~= "function" then
		return nil
	end
	local daemon = existing or M.new({ system = system, kernel = kernel })
	kernel.service.register("cloverd", {
		description = "hardware events for a text session",
		start = function()
			return daemon:start()
		end,
		stop = function()
			return daemon:stop()
		end,
		status = function()
			local state = daemon:status()
			if not state.running then
				return state.disabled and ("stopped: " .. state.disabled) or "stopped"
			end
			return string.format("running, %d hardware, %d forwarded", state.handled, state.forwarded)
		end,
	})
	return daemon
end

return M
