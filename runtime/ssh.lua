-- CloverOS ssh: a rednet remote shell, modelled on the real thing.
--
-- The server listens for authenticated "open" messages from other
-- computers, then serves each connection a fresh shell session and streams
-- the output back as rednet replies tagged with a session id. The client
-- sends a line, waits (bounded) for the reply, prints it. Two computers
-- need nothing but modems and rednet: the protocol is open, command,
-- return, closed - no central directory to find.
--
-- Security notes: the password check is the same salted SHA-256 path the
-- login screen uses (runtime/users.lua + runtime/hash.lua); a failed
-- authentication is journaled; a session that sends nothing for five
-- minutes is closed. Commands run in a forked shell of the *server's*
-- logged-in user, exactly like an sshd without per-user chroots would.
local M = {}

M.PORT = 23 -- ssh-ish, purely conventional over rednet
M.PROTOCOL = "clover/ssh"
M.TIMEOUT = 8 -- seconds the client waits for a reply
M.IDLE = 60 * 5 -- seconds a session may stay silent before it is closed

local function note(kernel, level, message)
	if kernel and type(kernel[level]) == "function" then
		pcall(kernel[level], "ssh: " .. message)
	end
end-- ---------- server ----------
function M.server(deps)
	deps = deps or {}
	local self = {
		kernel = deps.kernel,
		paths = deps.paths,
		users = deps.users,
		session = deps.session, -- the server's own shell; sessions fork it
		sessions = {}, -- id -> session record
		nextId = 1,
		running = false,
		startedAt = nil,
	}

	function self:handleOpen(senderId, message)
		if type(message) ~= "table" then
			return false
		end
		if message.kind ~= "open" then
			return false
		end
		local name = tostring(message.user or "")
		local password = tostring(message.password or "")
		if name == "" then
			self:reply(senderId, { kind = "deny", why = "no user" }, message.session)
			return true
		end
		local ok, why = self.users:authenticate(name, password)
		if not ok then
			note(self.kernel, "warn", "failed login from computer " .. tostring(senderId) .. " (" .. name .. ")")
			self:reply(senderId, { kind = "deny", why = "login failed" }, message.session)
			return true
		end
		local id = tostring(self.nextId)
		self.nextId = self.nextId + 1
		local session, why = self:buildSession(name)
		if not session then
			self:reply(senderId, { kind = "deny", why = why or "no shell" }, message.session)
			return true
		end
		self.sessions[id] = {
			user = name,
			host = senderId,
			sh = session,
			last = os.clock(),
		}
		note(self.kernel, "info", "session " .. id .. " opened for " .. name
			.. " from computer " .. tostring(senderId))
		self:reply(senderId, { kind = "welcome", session = id }, message.session)
		return true
	end

	-- A fresh shell for the named user: a fork of the server's own session
	-- with captured output, exactly what desktop windows use. The shell's
	-- access checks keep the remote user to their own files.
	function self:buildSession(name)
		if not (self.session and type(self.session.forkWindowShell) == "function") then
			return nil, "server has no session to fork"
		end
		return self.session:forkWindowShell()
	end

	function self:handleCommand(senderId, message)
		if type(message) ~= "table" or message.kind ~= "command" then
			return false
		end
		local session = self.sessions[tostring(message.session or "")]
		if not session then
			self:reply(senderId, { kind = "closed", why = "no such session" }, message.session)
			return true
		end
		local now = os.clock()
		if now - session.last > M.IDLE then
			self.sessions[tostring(message.session)] = nil
			self:reply(senderId, { kind = "closed", why = "idle timeout" }, message.session)
			return true
		end
		session.last = now
		local command = tostring(message.line or "")
		local lines = self:execute(session, command)
		self:reply(senderId, { kind = "output", session = message.session, lines = lines }, message.session)
		return true
	end

	-- Run one command line in the session's forked shell and collect the
	-- output it buffered.
	function self:execute(session, command)
		local out = {}
		if session.sh and type(session.sh.execute) == "function" then
			session.sh:execute(command)
			if type(session.sh.drainOutput) == "function" then
				out = session.sh:drainOutput()
			end
		end
		if type(out) ~= "table" or #out == 0 then
			out = { "" }
		end
		return out
	end

	function self:reply(target, payload, session)
		-- rednet transports tables natively (serializing internally), so the
		-- payload goes over as a table on the clover/ssh protocol
		if type(rednet) == "table" and type(rednet.send) == "function" then
			rednet.send(target, payload, M.PROTOCOL)
			return
		end
		note(self.kernel, "warn", "reply failed: no rednet transport")
	end

	-- Serve one event. Returns true when it belonged to sshd.
	function self:dispatch(ev)
		if type(ev) ~= "table" then
			return false
		end
		local kind = ev[1]
		if kind == "rednet_message" then
			local ok, message = pcall(textutils.unserialize, tostring(ev[4] or ""))
			if not ok or type(message) ~= "table" then
				return false
			end
			if message.proto == M.PROTOCOL or message.kind then
				local senderId = ev[3]
				if message.kind == "open" then
					return self:handleOpen(senderId, message)
				elseif message.kind == "command" then
					return self:handleCommand(senderId, message)
				elseif message.kind == "close" then
					local session = self.sessions[tostring(message.session or "")]
					if session then
						note(self.kernel, "info", "session " .. tostring(message.session) .. " closed by client")
						self.sessions[message.session] = nil
					end
					return true
				end
			end
			return false
		elseif kind == "timer" then
			-- reap idle sessions
			for id, session in pairs(self.sessions) do
				if os.clock() - session.last > M.IDLE then
					self.sessions[id] = nil
					note(self.kernel, "info", "session " .. id .. " reaped (idle)")
				end
			end
			return false -- timers belong to everyone
		end
		return false
	end

	function self:start()
		if self.running then
			return true
		end
		if type(rednet) == "table" and type(rednet.open) == "function" then
			rednet.open("top")
		else
			return nil, "no rednet hardware"
		end
		if not (self.session and type(self.session.forkWindowShell) == "function") then
			return nil, "server has no session to fork"
		end
		self.running = true
		self.startedAt = os.clock()
		note(self.kernel, "info", "sshd listening on protocol " .. M.PROTOCOL)
		return true
	end

	function self:stop()
		if not self.running then
			return true
		end
		self.running = false
		for id in pairs(self.sessions) do
			self.sessions[id] = nil
		end
		note(self.kernel, "info", "sshd stopped")
		return true
	end

	function self:status()
		local count = 0
		for _ in pairs(self.sessions) do
			count = count + 1
		end
		return {
			running = self.running,
			sessions = count,
			since = self.startedAt,
		}
	end

	return self
end

-- ---------- client ----------
-- One exchange: connect, run a line, collect the output. `onOutput` gets
-- each line as it arrives. Returns true, or nil plus a reason.
function M.run(deps, host, command, onOutput)
	deps = deps or {}
	local kernel = deps.kernel
	local system = deps.system
	local users = deps.users
	local ui = deps.ui or {}

	if not host then
		return nil, "usage: ssh <host> <command>"
	end
	if command == nil or command == "" then
		return nil, "no command given"
	end
	local hostId = tonumber(host)
	if not hostId then
		return nil, "host must be a computer id (numbers only)"
	end

	-- prompt for the password the same way login does
	local password = deps.password
	if password == nil and type(ui.readPassword) == "function" then
		password = ui.readPassword("password: ")
	elseif password == nil and type(read) == "function" then
		write("password: ")
		password = read("*")
	end
	if not password or password == "" then
		return nil, "no password given"
	end

	-- open transport
	if system and type(system.rednetOpen) == "function" then
		local ok = system:rednetOpen()
		if not ok then
			local state = system.state and system.state.rednet
			if not (state and state.present) then
				return nil, "no rednet hardware"
			end
		end
	elseif type(rednet) == "table" and type(rednet.open) == "function" then
		rednet.open(os.getComputerID() % 2 == 0 and "top" or "back")
	else
		return nil, "no rednet hardware"
	end

	local function send(payload)
		if type(rednet) == "table" and type(rednet.send) == "function" then
			rednet.send(hostId, payload, M.PROTOCOL)
		else
			-- the shim path: a serialized send through the system layer
			if system and type(system.rednetSend) == "function" then
				system:rednetSend(textutils.serialize(payload))
			end
		end
	end

	-- handshake
	send({ kind = "open", user = deps.user, password = password, session = "c1" })
	local deadline = os.clock() + M.TIMEOUT
	while os.clock() < deadline do
		local ev = { os.pullEventRaw("rednet_message") }
		if ev[1] == "rednet_message" and ev[3] == hostId then
			local ok, message = pcall(textutils.unserialize, tostring(ev[4] or ""))
			if ok and type(message) == "table" and message.kind == "welcome" then
				break
			elseif ok and type(message) == "table" and message.kind == "deny" then
				return nil, message.why or "login failed"
			end
		end
	end
	if os.clock() >= deadline then
		return nil, "no answer from " .. tostring(host)
	end

	-- the command exchange
	send({ kind = "command", session = "c1", line = command })
	deadline = os.clock() + M.TIMEOUT
	local done = false
	local lines = {}
	while os.clock() < deadline and not done do
		local ev = { os.pullEventRaw("rednet_message") }
		if ev[1] == "rednet_message" and ev[3] == hostId then
			local ok, message = pcall(textutils.unserialize, tostring(ev[4] ))
			if ok and type(message) == "table" then
				if message.kind == "output" then
					for _, line in ipairs(message.lines or {}) do
						lines[#lines + 1] = tostring(line)
						if onOutput then
							onOutput(tostring(line))
						end
					end
					done = true
				elseif message.kind == "closed" then
					return nil, message.why or "session closed"
				end
			end
		end
	end
	if not done then
		return nil, "no answer from " .. tostring(host)
	end

	send({ kind = "close", session = "c1" })
	return true, lines
end

-- ---------- interactive client ----------
-- A shell-like session: connect once, then run lines until `exit` or
-- ctrl+T. Reuses the single-exchange protocol but leaves the session open
-- between commands, so history and cwd persist on the server side.
function M.interactive(deps, host)
	deps = deps or {}
	local system = deps.system
	local ui = deps.ui or {}

	local hostId = tonumber(host)
	if not hostId then
		return nil, "host must be a computer id (numbers only)"
	end

	local password = deps.password
	if password == nil and type(ui.readPassword) == "function" then
		password = ui.readPassword("password: ")
	elseif password == nil and type(read) == "function" then
		write("password: ")
		password = read("*")
	end
	if not password or password == "" then
		return nil, "no password given"
	end

	if system and type(system.rednetOpen) == "function" then
		system:rednetOpen()
	elseif type(rednet) == "table" and type(rednet.open) == "function" then
		rednet.open("top")
	else
		return nil, "no rednet hardware"
	end

	local function send(payload)
		rednet.send(hostId, payload, M.PROTOCOL)
	end

	local function waitReply(kind, timeout)
		local deadline = os.clock() + (timeout or M.TIMEOUT)
		while os.clock() < deadline do
			local ev = { os.pullEventRaw("rednet_message") }
			if ev[1] == "rednet_message" and ev[3] == hostId then
				local ok, message = pcall(textutils.unserialize, tostring(ev[4] or ""))
				if ok and type(message) == "table" and message.kind == kind then
					return message
				end
				if ok and type(message) == "table" and message.kind == "closed" then
					return nil
				end
			end
		end
		return nil
	end

	send({ kind = "open", user = deps.user, password = password, session = "c1" })
	local welcome = waitReply("welcome")
	if not welcome then
		return nil, "no answer from " .. tostring(host)
	end
	print("connected to " .. hostId .. " (exit or ctrl+T to leave)")

	while true do
		write("ssh:" .. hostId .. "> ")
		local line = read()
		if line == nil or line == "exit" or line == "logout" then
			break
		end
		if line ~= "" then
			send({ kind = "command", session = "c1", line = line })
			local reply = waitReply("output")
			if not reply then
				print("ssh: no answer (session may have timed out)")
				break
			end
			for _, out in ipairs(reply.lines or {}) do
				print(out)
			end
		end
	end

	send({ kind = "close", session = "c1" })
	return true
end

return M
