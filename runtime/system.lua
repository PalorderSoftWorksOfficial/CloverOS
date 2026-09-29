-- CloverOS system layer: the bridge between the kernel and CC:Tweaked's real
-- hardware surface.
--
-- The kernel knows about services, config and the journal, but on CC:Tweaked
-- the machine is made of peripherals: a modem or wifi card, a GPS, rednet,
-- disks, monitors. Nothing owned them, so modem/wifi/GPS/rednet events were
-- dropped on the floor and the panel could only guess whether the computer
-- was online. This module owns that surface:
--
--   * discovery  -- scan() walks peripheral.getNames() and derives the state
--                   the panel, the commands and the login screen all read
--   * dispatch   -- dispatch() turns raw pullEventRaw() events into state
--                   changes and journal entries instead of discarding them
--   * drain      -- drain() gives the text-mode shell a non-blocking look at
--                   the queue so `net` in a terminal sees a modem event
--   * persistence -- the snapshot is written to var/run/system.cfg so a
--                   second process (and the reboot path) can read it
--
-- Peripheral objects are userdata on CC:Tweaked, so everything here is
-- duck-typed through `type(p.method) == "function"`; nothing compares
-- type(p) against "userdata".
local M = {}

local STATE_VERSION = 1

-- events the system layer consumes outright. Anything else (term_resize,
-- mouse_*, key, char, ...) is left for the window manager, so dispatch()
-- returning true really does mean "nobody else needs this event".
local HARDWARE_EVENTS = {
	peripheral = true,
	peripheral_detach = true,
	modem = true,
	wifi = true,
	gps = true,
	rednet_open = true,
	rednet_close = true,
	rednet_message = true,
	speaker_note = true,
	printer_page = true,
	disk = true,
	disk_eject = true,
}

local function hasType(found, ptype)
	for _, entry in ipairs(found) do
		if entry.type == ptype then
			return true
		end
	end
	return false
end

local function newState()
	return {
		peripherals = {},
		network = { interface = "none", state = "offline", connected = false, signal = nil },
		audio = { present = false },
		power = { present = false },
		gps = { present = false, open = false, lat = nil, lon = nil, altitude = nil },
		rednet = { present = false, open = 0, sent = 0, received = 0 },
		printer = { present = false, pages = 0 },
		storage = { disks = 0, space = nil },
		display = { monitors = 0 },
		inbox = {},
	}
end

-- call p[name](p, ...) if the peripheral exposes it; nil otherwise
local function call(p, name, ...)
	if type(p) ~= "table" and type(p) ~= "userdata" then
		return nil
	end
	local fn = p[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, p, ...)
	if not ok then
		return nil
	end
	return result
end

function M.new(deps)
	deps = deps or {}
	local self = {
		paths = deps.paths,
		kernel = deps.kernel,
		listeners = {},
		state = newState(),
	}

	-- ---------- notification ----------
	function self:subscribe(fn)
		if type(fn) == "function" then
			self.listeners[#self.listeners + 1] = fn
			return true
		end
		return false
	end

	function self:announce(topic, detail)
		for _, fn in ipairs(self.listeners) do
			pcall(fn, topic, detail, self.state)
		end
	end

	function self:note(level, message)
		if self.kernel and type(self.kernel[level]) == "function" then
			pcall(self.kernel[level], message)
		end
	end

	-- ---------- persistence ----------
	function self:statePath()
		return self.paths:join("var", "run", "system.cfg")
	end

	-- The snapshot is advisory: a missing or damaged file must never stop the
	-- OS from starting, so save() reports failure and load() just returns nil.
	function self:save()
		if type(textutils) ~= "table" or type(textutils.serialize) ~= "function" then
			return false
		end
		self.state.version = STATE_VERSION
		local ok, data = pcall(textutils.serialize, self.state)
		if not ok or type(data) ~= "string" then
			return false
		end
		local handle = fs.open(self:statePath(), "w")
		if not handle then
			fs.makeDir(fs.getDir(self:statePath()))
			handle = fs.open(self:statePath(), "w")
		end
		if not handle then
			return false
		end
		handle.write(data)
		handle.close()
		return true
	end

	function self:load()
		if not fs.exists(self:statePath()) then
			return nil
		end
		local handle = fs.open(self:statePath(), "r")
		if not handle then
			return nil
		end
		local data = handle.readAll()
		handle.close()
		if type(data) ~= "string" then
			return nil
		end
		local ok, value = pcall(textutils.unserialize, data)
		if not ok or type(value) ~= "table" then
			return nil
		end
		for key, default in pairs(newState()) do
			if value[key] == nil then
				value[key] = default
			end
		end
		self.state = value
		return self.state
	end

	-- ---------- discovery ----------
	function self:readNetwork(p, ptype)
		local net = self.state.network
		net.interface = ptype
		-- modem and wifi disagree on the spelling; try both
		local status = call(p, "getStatus") or call(p, "getState")
		if type(status) == "string" then
			net.state = status
		elseif call(p, "isOpen") == true then
			net.state = "online"
		else
			net.state = "offline"
		end
		net.connected = (net.state == "online")
		local signal = call(p, "signalStrength") or call(p, "getSignalStrength")
		net.signal = (type(signal) == "number" and signal >= 0) and signal or nil
		return true
	end

	-- Re-reads every peripheral and folds the result into the state. Safe to
	-- call on a computer with no peripherals at all: everything stays at its
	-- default and the panel simply shows "offline".
	function self:scan()
		local found = {}
		-- rescan replaces the device list outright; appending would duplicate
		-- every peripheral on the second call (attach() loads, then scans)
		self.state.peripherals = {}
		if type(peripheral) == "table" and type(peripheral.getNames) == "function" then
			local ok, names = pcall(peripheral.getNames)
			if ok and type(names) == "table" then
				for _, name in ipairs(names) do
					local ptype
					if type(peripheral.getType) == "function" then
						local tok, result = pcall(peripheral.getType, name)
						ptype = tok and result or nil
					end
					local p
					if type(peripheral.find) == "function" then
						local fok, result = pcall(peripheral.find, ptype)
						p = fok and result or nil
					end
					found[#found + 1] = { name = name, type = ptype or "unknown", peripheral = p }
				end
			end
		end
		table.sort(found, function(a, b)
			return a.name < b.name
		end)

		local summary = { names = {}, disks = 0, monitors = 0 }
		for _, entry in ipairs(found) do
			local ptype = entry.type
			local plain = { name = entry.name, type = ptype }
			self.state.peripherals[#self.state.peripherals + 1] = plain
			summary.names[#summary.names + 1] = entry.name .. " (" .. ptype .. ")"
			if ptype == "modem" or ptype == "wifi" then
				self:readNetwork(entry.peripheral, ptype)
			elseif ptype == "gps" then
				self:readGps(entry.peripheral)
			elseif ptype == "speaker" then
				self.state.audio.present = true
			elseif ptype == "energy" then
				self.state.power.present = true
			elseif ptype == "rednet" then
				self.state.rednet.present = true
			elseif ptype == "printer" then
				self.state.printer.present = true
			elseif ptype == "disk" then
				summary.disks = summary.disks + 1
				local space = call(entry.peripheral, "getSpace")
				self.state.storage.space = (type(space) == "number" and space > 0) and space
					or self.state.storage.space
			elseif ptype == "monitor" then
				summary.monitors = summary.monitors + 1
			end
		end
		-- a modem that has been unplugged must not stay "online"
		if summary.disks == 0 then
			self.state.storage.space = nil
		end
		self.state.storage.disks = summary.disks
		self.state.display.monitors = summary.monitors
		if not hasType(found, "modem") and not hasType(found, "wifi") then
			self.state.network = { interface = "none", state = "offline", connected = false, signal = nil }
		end
		if not hasType(found, "gps") then
			self.state.gps = { present = false, open = false, lat = nil, lon = nil, altitude = nil }
		end
		self.state.updatedAt = os.epoch("utc")
		self:announce("scan", summary)
		return self.state
	end

	function self:readGps(p)
		local gps = self.state.gps
		gps.present = true
		gps.open = call(p, "isOpen") == true
		-- getPosition is the one peripheral method with three results, so it
		-- is unwrapped by hand; call() only yields the first
		if p and type(p.getPosition) == "function" then
			local ok, x, y, z = pcall(p.getPosition, p)
			if ok and type(x) == "number" and type(y) == "number" then
				gps.lat, gps.lon, gps.altitude = x, y, z
			end
		end
		return true
	end

	-- ---------- events ----------
	function self:handleRednetMessage(senderId, message)
		local inbox = self.state.inbox
		inbox[#inbox + 1] = {
			from = tonumber(senderId) or senderId,
			message = tostring(message or ""),
			at = os.epoch("utc"),
		}
		-- a mailbox nobody can drain is a leak, not a feature
		while #inbox > 50 do
			table.remove(inbox, 1)
		end
		self.state.rednet.received = self.state.rednet.received + 1
		self:note("info", "rednet message from " .. tostring(senderId))
		return true
	end

	-- Handles one event. Returns true when the system layer consumed it, so
	-- the caller knows not to forward it to the window manager.
	function self:dispatch(ev)
		if type(ev) ~= "table" then
			return false
		end
		local kind = ev[1]
		if type(kind) ~= "string" or not HARDWARE_EVENTS[kind] then
			return false
		end
		if kind == "peripheral" or kind == "peripheral_detach" then
			local name = tostring(ev[2] or "?")
			local ptype = (type(peripheral) == "table" and type(peripheral.getType) == "function"
				and peripheral.getType(name)) or "removed"
			if kind == "peripheral" then
				self:note("info", "attached " .. name .. " (" .. tostring(ptype) .. ")")
			else
				self:note("warn", "detached " .. name)
			end
			self:scan()
			self:announce(kind, name)
			return true
		elseif kind == "modem" or kind == "wifi" then
			local p
			if type(peripheral) == "table" and type(peripheral.find) == "function" then
				p = peripheral.find(kind)
			end
			if p then
				self:readNetwork(p, kind)
			end
			self:note("info", kind .. " status " .. tostring(self.state.network.state))
			self:announce(kind, self.state.network.state)
			return true
		elseif kind == "gps" then
			local p
			if type(peripheral) == "table" and type(peripheral.find) == "function" then
				p = peripheral.find("gps")
			end
			if p then
				self:readGps(p)
			end
			self:announce("gps", self.state.gps)
			return true
		elseif kind == "rednet_open" then
			self.state.rednet.present = true
			self.state.rednet.open = self.state.rednet.open + 1
			self:announce("rednet_open", ev[3])
			return true
		elseif kind == "rednet_close" then
			self.state.rednet.open = math.max(0, self.state.rednet.open - 1)
			self:announce("rednet_close", ev[3])
			return true
		elseif kind == "rednet_message" then
			return self:handleRednetMessage(ev[3], ev[4])
		elseif kind == "speaker_note" then
			self.state.audio.present = true
			self:announce("speaker_note", ev[2])
			return true
		elseif kind == "printer_page" then
			self.state.printer.present = true
			self.state.printer.pages = self.state.printer.pages + 1
			self:note("info", "printer page " .. tostring(ev[2]))
			return true
		elseif kind == "disk" or kind == "disk_eject" then
			self:note("info", kind .. " " .. tostring(ev[2] or ""))
			self:scan()
			self:announce(kind, ev[2])
			return true
		end
		return false
	end

	-- Non-blocking drain deliberately does not exist: os.pullEventRaw cannot
	-- be filtered without discarding the events it skips, so a command that
	-- drained the queue would eat the shell's queued keystrokes. Commands
	-- use scan() instead, which reads the hardware directly and so is
	-- already current without touching the event stream.

	-- ---------- accessors ----------
	function self:network()
		return self.state.network
	end

	function self:inbox()
		return self.state.inbox
	end

	function self:clearInbox()
		local n = #self.state.inbox
		self.state.inbox = {}
		return n
	end

	-- "wifi 3/4" style summary for the panel's status area
	function self:summary()
		local net = self.state.network
		if net.interface == "none" then
			return "offline"
		end
		local text = net.interface
		if not net.connected then
			text = text .. " offline"
		end
		if net.signal then
			text = text .. " " .. tostring(net.signal) .. "/4"
		end
		return text
	end

	-- ---------- rednet ----------
	function self:rednet()
		if type(peripheral) == "table" and type(peripheral.find) == "function" then
			return peripheral.find("rednet")
		end
		return nil
	end

	function self:rednetOpen(side)
		local p = self:rednet()
		if not p then
			return false, "no rednet peripheral"
		end
		local ok, err = call(p, "open", tonumber(side) or 1)
		if not ok then
			return false, "rednet open failed"
		end
		self.state.rednet.present = true
		self.state.rednet.open = self.state.rednet.open + 1
		return true
	end

	function self:rednetClose(side)
		local p = self:rednet()
		if not p then
			return false, "no rednet peripheral"
		end
		local ok = call(p, "close", tonumber(side) or 1)
		if not ok then
			return false, "rednet close failed"
		end
		self.state.rednet.open = math.max(0, self.state.rednet.open - 1)
		return true
	end

	function self:rednetSend(message, side)
		local p = self:rednet()
		if not p then
			return false, "no rednet peripheral"
		end
		local id = call(p, "send", tonumber(side) or 1, tostring(message or ""))
		if id == nil then
			return false, "rednet send failed"
		end
		self.state.rednet.present = true
		self.state.rednet.sent = self.state.rednet.sent + 1
		return true, id
	end

	return self
end

-- Entry point for programs outside the session (the `net`, `gps` and
-- `rednet` commands, and `bin/neofetch.lua`). Locates the CloverOS root,
-- loads the snapshot the running session keeps up to date, then rescans the
-- hardware so the answer reflects the machine right now rather than when the
-- desktop last ran. Read-only with respect to the event stream, so it is
-- safe to call while a shell is waiting for input.
function M.attach(root)
	if type(fs) ~= "table" or type(fs.combine) ~= "function" then
		return nil
	end
	if type(root) ~= "string" or root == "" then
		root = type(CLOVER_ROOT) == "string" and CLOVER_ROOT or nil
	end
	if not root then
		local program = type(shell) == "table" and type(shell.getRunningProgram) == "function"
			and shell.getRunningProgram() or nil
		-- bin/ lives directly under the root, so the program's dir is the root
		root = program and fs.getDir(program) or nil
	end
	if not root then
		return nil
	end
	local pathsOk, pathsModule = pcall(dofile, fs.combine(root, "runtime/paths.lua"))
	if not pathsOk or type(pathsModule) ~= "table" or type(pathsModule.new) ~= "function" then
		return nil
	end
	local self = M.new({ paths = pathsModule.new(root) })
	self:load()
	self:scan()
	return self
end

return M
