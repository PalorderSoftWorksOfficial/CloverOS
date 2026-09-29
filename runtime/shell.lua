-- CloverOS shell: a bash-style command language over builtin commands and
-- programs. The same engine backs the text-mode session and GUI terminal
-- windows (via forkWindowShell).
--
-- Language features: quoting/escapes, pipes (|), redirection (>, >>, <),
-- sequencing (;, &&, ||), variables ($NAME, ${NAME}, export), tilde and
-- glob expansion (* ? [..]), aliases, history (!N), tab completion.
local M = {}

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readAll(path)
	local h = fs.open(path, "r")
	if not h then
		return nil
	end
	local data = h.readAll()
	h.close()
	return data
end

local function writeAll(path, data)
	fs.makeDir(fs.getDir(path))
	local h = fs.open(path, "w")
	if not h then
		return nil, "cannot write " .. path
	end
	h.write(tostring(data or ""))
	h.close()
	return true
end

-- lightweight proxy passed as `shell` to programs run in window mode
local function childShellProxy(parent)
	return setmetatable({
		run = function(prog, ...)
			parent:execute(prog .. " " .. table.concat({ ... }, " "))
		end,
		dir = function()
			return parent.paths:cwd()
		end,
		resolve = function(p)
			return parent.paths:osPath(p)
		end,
		resolvePath = function(p)
			return parent.paths:osPath(p)
		end,
		getRunningProgram = function()
			return parent.paths:join("bin", "sh")
		end,
		setDir = function(p)
			parent.paths:setCwd(p)
		end,
	}, { __index = _ENV.shell or {} })
end

-- a terminal-like object that forwards writes to a line sink
local function makeVirtualTerm(sink)
	local pending = ""
	local function emit(text)
		pending = pending .. tostring(text or "")
		local nl = pending:find("\n", 1, true)
		while nl do
			sink(pending:sub(1, nl - 1))
			pending = pending:sub(nl + 1)
			nl = pending:find("\n", 1, true)
		end
	end
	local function flush()
		if pending ~= "" then
			sink(pending)
			pending = ""
		end
	end
	return {
		write = emit,
		flush = flush,
		setCursorPos = function() end,
		getCursorPos = function() return 1, 1 end,
		getSize = function() return 51, 19 end,
		clear = function() end,
		clearLine = function() end,
		isColor = term.isColor,
		isColour = term.isColour,
		setTextColor = function() end,
		setBackgroundColor = function() end,
		setTextColour = function() end,
		setBackgroundColour = function() end,
		blit = function(text) emit(text) end,
		setPaletteColor = function() end,
		setPaletteColour = function() end,
		getPaletteColor = function() end,
		getPaletteColour = function() end,
		scroll = function() end,
		setCursorBlink = function() end,
		getCursorBlink = function() return false end,
	}
end

-- ---------- tokenizer ----------
-- returns tokens: { text=..., quoted=bool } or { op = "|", ... }
local function tokenize(line)
	local tokens = {}
	local word, quoted, squote = {}, false, false
	local quote = nil
	local escape = false

	local function pushWord()
		if #word > 0 or quoted then
			tokens[#tokens + 1] = { text = table.concat(word), quoted = quoted, squote = squote }
			word, quoted, squote = {}, false, false
		end
	end

	local i = 1
	while i <= #line do
		local c = line:sub(i, i)
		if escape then
			word[#word + 1] = c
			escape = false
			i = i + 1
		elseif c == "\\" and quote ~= "'" then
			escape = true
			i = i + 1
		elseif c == '"' or c == "'" then
			if quote == c then
				quote = nil
			elseif not quote then
				quote = c
				quoted = true
				squote = squote or c == "'"
			else
				word[#word + 1] = c
			end
			i = i + 1
		elseif not quote and c:match("%s") then
			pushWord()
			i = i + 1
		elseif not quote and (c == "|" or c == ";" or c == "<" or c == ">") then
			pushWord()
			local two = line:sub(i, i + 1)
			if two == "&&" or two == "||" then
				tokens[#tokens + 1] = { op = two }
				i = i + 2
			elseif two == ">>" then
				tokens[#tokens + 1] = { op = ">>" }
				i = i + 2
			else
				tokens[#tokens + 1] = { op = c }
				i = i + 1
			end
		elseif not quote and c == "&" and line:sub(i + 1, i + 1) == "&" then
			pushWord()
			tokens[#tokens + 1] = { op = "&&" }
			i = i + 2
		elseif not quote and c == "|" and line:sub(i + 1, i + 1) == "|" then
			pushWord()
			tokens[#tokens + 1] = { op = "||" }
			i = i + 2
		else
			word[#word + 1] = c
			i = i + 1
		end
	end
	pushWord()
	return tokens
end

function M.new(deps)
	deps = deps or {}
	local self = {
		paths = deps.paths,
		users = deps.users,
		ui = deps.ui,
		packages = deps.packages,
		running = true,
		historyFile = nil,
		history = {},
		aliases = {},
		vars = {},
		term = deps.ui and deps.ui.term or term,
		lastStatus = 0,
		-- window-shell mode: output is buffered for drainOutput(), read() is refused
		captured = nil,
		_sink = nil,
		_stdin = nil,
		_elevated = false,
	}
	self.permFile = self.paths:join("etc", "clover", "permissions.cfg")
	self.sudoCacheFile = self.paths:join("var", "lib", "clover", "sudo.cache")

	local function emitLine(line)
		if self._sink then
			self._sink(line)
		elseif self.captured then
			self.captured[#self.captured + 1] = line
			while #self.captured > 200 do
				table.remove(self.captured, 1)
			end
		elseif self.ui then
			self.ui:println(line)
		else
			print(line)
		end
	end

	-- direct program execution (interactive text shell, no pipes involved)
	local function runProgram(path, args)
		local ok, result = pcall(shell.run, path, table.unpack(args or {}))
		if not ok then
			println("sh: program crashed: " .. tostring(result))
		end
	end

	local function println(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		emitLine(table.concat(parts, " "))
	end

	local function printLines(data)
		local body = tostring(data or "")
		if body == "" then
			return
		end
		if body:sub(-1) ~= "\n" then
			body = body .. "\n"
		end
		for line in body:gmatch("(.-)\n") do
			emitLine(line)
		end
	end

	-- Access rules live in runtime/access.lua so the shell and the external
	-- commands in bin/ enforce exactly the same policy. It is built before
	-- effectiveUser so the two never disagree about who is running.
	local access = dofile(self.paths:join("runtime", "access.lua")).new({
		paths = self.paths,
		users = self.users,
	})
	self.access = access

	-- effective user for privilege checks (sudo switches it per command)
	local function effectiveUser()
		return access:effectiveUser()
	end

	-- ---------- permissions (Ubuntu-style ownership on system paths) ----------
	local function savePerms(db)
		local ok = writeAll(self.permFile, textutils.serialize(db))
		-- the access module caches; a chmod must not be masked by a stale read
		access:reload()
		return ok
	end

	local function perms()
		return access:records()
	end

	local function canWrite(display)
		return access:canWrite(display)
	end

	local function denyRead(path)
		println("sh: permission denied: " .. tostring(path))
		self.lastStatus = 1
		return false
	end

	-- Every user-supplied path that is about to be read goes through this
	local function checkRead(path)
		if access:canReadPath(path) then
			return true
		end
		return denyRead(access:displayOf(path))
	end

	local function denyWrite(path)
		println("sh: permission denied: " .. tostring(path) .. " (try sudo)")
	end

	-- ---------- programs ----------
	local function listPrograms()
		local dirs = {
			self.paths:join("bin"),
			self.paths:join("usr", "bin"),
			self.paths:join("apps"),
		}
		local out = {}
		for _, dir in ipairs(dirs) do
			if fs.isDir(dir) then
				for _, file in ipairs(fs.list(dir)) do
					local full = fs.combine(dir, file)
					if not fs.isDir(full) then
						local name = file:match("^(.*)%.[lL][uU][aA]$")
							or file:match("^(.*)%.[eE][xX][eE]$")
							or (not file:match("%.") and file)
							or nil
						if name and not out[name] then
							out[name] = full
						end
					end
				end
			end
		end
		return out
	end

	-- ---------- history ----------
	-- History is per user. A shared file leaked one account's commands to
	-- another and let any user tamper with it, since var/log is writable.
	-- `name` defaults to the account the session is on; saving passes the
	-- account that actually owns the in-memory list, which is not the same
	-- one at the moment the session switches over.
	local function historyFile(name)
		name = name or (self.users and self.users:currentName()) or effectiveUser()
		if not self.paths or not name or name == "" then
			return nil
		end
		return self.paths:join("var", "log", "history", tostring(name))
	end

	local function loadHistory()
		self.history = {}
		self._historyUser = (self.users and self.users:currentName()) or nil
		local data = readAll(historyFile(self._historyUser))
		if not data then
			return
		end
		for line in data:gmatch("[^\n]+") do
			self.history[#self.history + 1] = line
		end
	end

	local function saveHistory()
		local file = historyFile(self._historyUser)
		if not file then
			return
		end
		local maxKeep = 100
		local startAt = math.max(1, #self.history - maxKeep + 1)
		local keep = {}
		for i = startAt, #self.history do
			keep[#keep + 1] = self.history[i]
		end
		fs.makeDir(fs.getDir(file))
		writeAll(file, table.concat(keep, "\n") .. "\n")
	end

	-- ---------- expansion ----------
	local function specialVar(name)
		if name == "USER" then
			return effectiveUser()
		elseif name == "HOME" then
			return self.paths:displayPath(self.paths:homePath(effectiveUser()))
		elseif name == "HOSTNAME" then
			return self.ui and self.ui:hostname() or tostring(os.getComputerLabel() or "computer")
		elseif name == "PWD" then
			return self.paths:displayPath()
		elseif name == "?" then
			return tostring(self.lastStatus)
		elseif name == "SHELL" then
			return "/bin/sh"
		end
		return nil
	end

	local function expandVars(text)
		text = text:gsub("%$%{([%w_]+)%}", function(name)
			return tostring(specialVar(name) or self.vars[name] or "")
		end)
		text = text:gsub("%$([%w_]+)", function(name)
			return tostring(specialVar(name) or self.vars[name] or "")
		end)
		text = text:gsub("%$%?", function()
			return tostring(self.lastStatus)
		end)
		return text
	end

	local function globToPattern(pattern)
		local out = { "^" }
		local i = 1
		while i <= #pattern do
			local c = pattern:sub(i, i)
			if c == "*" then
				out[#out + 1] = ".*"
			elseif c == "?" then
				out[#out + 1] = "."
			elseif c == "[" then
				local close = pattern:find("]", i + 1, true)
				if close then
					out[#out + 1] = pattern:sub(i, close)
					i = close
				else
					out[#out + 1] = "%["
				end
			else
				out[#out + 1] = c:gsub("(%W)", "%%%1")
			end
			i = i + 1
		end
		out[#out + 1] = "$"
		return table.concat(out)
	end

	-- expands one token's text (tilde, variables, globs); returns a list of
	-- literal words (glob may multiply a token)
	local function expandToken(tok)
		local text = tok.text
		if tok.squote then
			return { text }
		end
		if not tok.quoted then
			if text:sub(1, 1) == "~" then
				text = self.paths:displayPath(self.paths:homePath(effectiveUser())) .. text:sub(2)
			end
			text = expandVars(text)
		else
			text = expandVars(text)
		end
		if tok.quoted or not text:find("[%*%?%[]") then
			return { text }
		end
		-- glob against the filesystem
		local dirPart, namePart = text:match("^(.*[/\\])([^/\\]*)$")
		if not dirPart then
			dirPart, namePart = "", text
		end
		local osDir = dirPart == "" and self.paths:osPath(".") or self.paths:osPath(dirPart)
		if not fs.isDir(osDir) then
			return { text }
		end
		local pattern = globToPattern(namePart)
		local matches = {}
		for _, name in ipairs(fs.list(osDir)) do
			if name:match(pattern) then
				matches[#matches + 1] = dirPart .. name
			end
		end
		table.sort(matches)
		if #matches == 0 then
			return { text }
		end
		return matches
	end

	-- ---------- sudo ----------
	local function sudoCached(user)
		local data = readAll(self.sudoCacheFile)
		if not data then
			return false
		end
		local ok, db = pcall(textutils.unserialize, data)
		if not ok or type(db) ~= "table" or type(db[user]) ~= "number" then
			return false
		end
		return (os.epoch("utc") - db[user]) < 5 * 60 * 1000
	end

	local function sudoRemember(user)
		local data = readAll(self.sudoCacheFile)
		local ok, db = pcall(textutils.unserialize, data or "")
		if not ok or type(db) ~= "table" then
			db = {}
		end
		db[user] = os.epoch("utc")
		writeAll(self.sudoCacheFile, textutils.serialize(db))
	end

	-- ---------- builtins ----------
	local builtins = {}

	builtins.help = function()
		local names = {}
		for name in pairs(builtins) do
			names[#names + 1] = name
		end
		for name in pairs(listPrograms()) do
			names[#names + 1] = name
		end
		table.sort(names)
		println("CloverOS shell")
		println("builtins and programs:")
		local line = ""
		for _, name in ipairs(names) do
			if #line + #name + 2 > 60 then
				println("  " .. line)
				line = name
			else
				line = (line == "") and name or (line .. "  " .. name)
			end
		end
		if line ~= "" then
			println("  " .. line)
		end
	end

	builtins.exit = function()
		self.running = false
	end

	builtins.logout = function()
		self.running = false
		self.logoutRequested = true
	end

	builtins.clear = function()
		if self.ui then
			self.ui:clear()
		else
			term.clear()
			term.setCursorPos(1, 1)
		end
	end

	builtins.pwd = function()
		println(self.paths:displayPath())
	end

	builtins.cd = function(path)
		if not path or path == "" then
			path = self.paths:homePath(effectiveUser())
		end
		local ok, err = self.paths:setCwd(path)
		if not ok then
			println("cd: " .. tostring(err or "cannot change directory"))
			self.lastStatus = 1
		end
	end

	builtins.ls = function(...)
		local args = { ... }
		local long = false
		local targets = {}
		for _, a in ipairs(args) do
			if a == "-l" then
				long = true
			else
				targets[#targets + 1] = a
			end
		end
		if #targets == 0 then
			targets[1] = "."
		end
		local function entryLine(name, full)
			if long then
				local display = self.paths:displayPath(full)
				local record = perms()[display] or {}
				local mode = record.mode or (fs.isDir(full) and "755" or "644")
				local owner = record.owner or effectiveUser()
				local size = fs.isDir(full) and 0 or #(readAll(full) or "")
				println(string.format("%s %s %4d %s", mode, owner, size, name))
			else
				println(name)
			end
		end
		local function listOne(path)
			local target = self.paths:osPath(path)
			if not checkRead(path) then
				return
			end
			if not fs.exists(target) then
				println("ls: no such path: " .. tostring(path))
				self.lastStatus = 1
				return
			end
			if not fs.isDir(target) then
				entryLine(fs.getName(target), target)
				return
			end
			local items = fs.list(target)
			table.sort(items)
			for _, item in ipairs(items) do
				local full = fs.combine(target, item)
				if fs.isDir(full) then
					entryLine(item .. "/", full)
				else
					entryLine(item, full)
				end
			end
		end
		for i, path in ipairs(targets) do
			if #targets > 1 then
				println(path .. ":")
			end
			listOne(path)
		end
	end

	builtins.cat = function(...)
		local args = { ... }
		if #args == 0 then
			if self._stdin then
				for _, line in ipairs(self._stdin) do
					emitLine(line)
				end
			else
				println("usage: cat <file>")
			end
			return
		end
		for _, path in ipairs(args) do
			if path == "-" and self._stdin then
				for _, line in ipairs(self._stdin) do
					emitLine(line)
				end
			elseif not checkRead(path) then
				-- denied
			else
				local data = readAll(self.paths:osPath(path))
				if not data then
					println("cat: cannot open " .. tostring(path))
					self.lastStatus = 1
				else
					printLines(data)
				end
			end
		end
	end

	builtins.echo = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		println(table.concat(parts, " "))
	end

	builtins.history = function()
		for i, line in ipairs(self.history) do
			println(string.format("%4d  %s", i, line))
		end
	end

	builtins.whoami = function()
		println(effectiveUser())
	end

	builtins.id = function()
		local name = effectiveUser()
		println("uid=" .. tostring(self.users and self.users.users[name] and self.users.users[name].uid or 1000)
			.. "(" .. name .. ") groups=" .. table.concat(self.users and self.users:groups(name) or { name }, ","))
	end

	builtins.groups = function()
		local name = effectiveUser()
		println(table.concat(self.users and self.users:groups(name) or { name }, " "))
	end

	builtins.hostname = function()
		println(self.ui and self.ui:hostname() or (os.getComputerLabel() or "computer-" .. os.getComputerID()))
	end

	builtins.date = function()
		println(os.date("%Y-%m-%d %H:%M:%S"))
	end

	builtins.time = function()
		println(textutils.formatTime(os.time(), true))
	end

	builtins.uptime = function()
		println(string.format("up %.1f min", os.clock() / 60))
	end

	builtins.touch = function(path)
		if not path then
			println("usage: touch <file>")
			return
		end
		local display = self.paths:displayPath(path)
		if not canWrite(display) then
			denyWrite(path)
			self.lastStatus = 1
			return
		end
		local target = self.paths:osPath(path)
		if fs.exists(target) then
			return
		end
		local ok = writeAll(target, "")
		if not ok then
			println("touch: cannot create " .. tostring(path))
			self.lastStatus = 1
		end
	end

	builtins.mkdir = function(path)
		if not path then
			println("usage: mkdir <dir>")
			return
		end
		if not canWrite(self.paths:displayPath(path)) then
			denyWrite(path)
			self.lastStatus = 1
			return
		end
		local target = self.paths:osPath(path)
		if fs.exists(target) then
			println("mkdir: already exists: " .. tostring(path))
			self.lastStatus = 1
			return
		end
		fs.makeDir(target)
	end

	builtins.rm = function(...)
		local args = { ... }
		local recursive = false
		local targets = {}
		for _, a in ipairs(args) do
			if a == "-r" or a == "-rf" or a == "-fr" then
				recursive = true
			else
				targets[#targets + 1] = a
			end
		end
		if #targets == 0 then
			println("usage: rm [-r] <path>")
			return
		end
		for _, path in ipairs(targets) do
			if not canWrite(self.paths:displayPath(path)) then
				denyWrite(path)
				self.lastStatus = 1
			else
				local target = self.paths:osPath(path)
				if not fs.exists(target) then
					println("rm: no such file or directory: " .. tostring(path))
					self.lastStatus = 1
				elseif fs.isDir(target) and not recursive then
					println("rm: is a directory: " .. tostring(path) .. " (use -r)")
					self.lastStatus = 1
				else
					fs.delete(target)
				end
			end
		end
	end

	builtins.cp = function(src, dst)
		if not src or not dst then
			println("usage: cp <src> <dst>")
			return
		end
		local a = self.paths:osPath(src)
		local b = self.paths:osPath(dst)
		if not fs.exists(a) then
			println("cp: no such file: " .. tostring(src))
			self.lastStatus = 1
			return
		end
		if not canWrite(self.paths:displayPath(dst)) then
			denyWrite(dst)
			self.lastStatus = 1
			return
		end
		fs.copy(a, b)
	end

	builtins.mv = function(src, dst)
		if not src or not dst then
			println("usage: mv <src> <dst>")
			return
		end
		local a = self.paths:osPath(src)
		local b = self.paths:osPath(dst)
		if not fs.exists(a) then
			println("mv: no such file: " .. tostring(src))
			self.lastStatus = 1
			return
		end
		if not canWrite(self.paths:displayPath(dst)) or not canWrite(self.paths:displayPath(src)) then
			denyWrite(self.paths:displayPath(dst))
			self.lastStatus = 1
			return
		end
		fs.move(a, b)
	end

	builtins.chmod = function(mode, path)
		if not mode or not path then
			println("usage: chmod <mode> <path>   (e.g. chmod 644 note.txt)")
			return
		end
		if not tostring(mode):match("^%d%d%d$") then
			println("chmod: invalid mode: " .. tostring(mode))
			self.lastStatus = 1
			return
		end
		if not canWrite(self.paths:displayPath(path)) then
			denyWrite(path)
			self.lastStatus = 1
			return
		end
		local db = perms()
		local display = self.paths:displayPath(path)
		db[display] = db[display] or { owner = effectiveUser() }
		db[display].mode = tostring(mode)
		savePerms(db)
	end

	builtins.chown = function(spec, path)
		if not spec or not path then
			println("usage: chown <user[:group]> <path>")
			return
		end
		if effectiveUser() ~= "root" then
			println("chown: changing ownership requires root (try sudo)")
			self.lastStatus = 1
			return
		end
		local owner, group = spec:match("^([^:]+):?(.*)$")
		local db = perms()
		local display = self.paths:displayPath(path)
		db[display] = db[display] or { mode = "644" }
		db[display].owner = owner
		if group ~= "" then
			db[display].group = group
		end
		savePerms(db)
	end

	builtins.export = function(pair)
		if not pair then
			for k, v in pairs(self.vars) do
				println(k .. "=" .. v)
			end
			return
		end
		local name, value = tostring(pair):match("^([%w_]+)=(.*)$")
		if not name then
			println("usage: export NAME=value")
			return
		end
		self.vars[name] = value
	end

	builtins.unset = function(name)
		if name then
			self.vars[name] = nil
		end
	end

	builtins.env = function()
		println("USER=" .. effectiveUser())
		println("HOME=" .. self.paths:displayPath(self.paths:homePath(effectiveUser())))
		println("PWD=" .. self.paths:displayPath())
		println("SHELL=/bin/sh")
		for k, v in pairs(self.vars) do
			println(k .. "=" .. v)
		end
	end

	builtins.wc = function(...)
		local args = { ... }
		local mode = ""
		local files = {}
		for _, a in ipairs(args) do
			if a == "-l" or a == "-w" or a == "-c" then
				mode = a
			else
				files[#files + 1] = a
			end
		end
		local lines = {}
		if #files == 0 then
			lines = self._stdin or {}
		else
			for _, path in ipairs(files) do
				for line in (readAll(self.paths:osPath(path)) or ""):gmatch("(.-)\n") do
					lines[#lines + 1] = line
				end
			end
		end
		local words, chars = 0, 0
		for _, line in ipairs(lines) do
			words = words + select(2, line:gsub("%S+", ""))
			chars = chars + #line + 1
		end
		if mode == "-w" then
			println(tostring(words))
		elseif mode == "-c" then
			println(tostring(chars))
		else
			println(tostring(#lines))
		end
	end

	builtins.sort = function(path)
		local lines = {}
		if path then
			for line in (readAll(self.paths:osPath(path)) or ""):gmatch("(.-)\n") do
				lines[#lines + 1] = line
			end
		else
			for _, line in ipairs(self._stdin or {}) do
				lines[#lines + 1] = line
			end
		end
		table.sort(lines)
		for _, line in ipairs(lines) do
			emitLine(line)
		end
	end

	local function requireInteractive(name)
		if self.captured then
			error("'" .. name .. "' needs an interactive terminal; run it from the text shell", 0)
		end
	end

	builtins.edit = function(path)
		requireInteractive("edit")
		local target = path and self.paths:osPath(path) or nil
		if target and not fs.exists(target) then
			if not canWrite(self.paths:displayPath(path)) then
				denyWrite(path)
				return
			end
			local ok = writeAll(target, "")
			if not ok then
				println("edit: cannot create " .. tostring(path))
				return
			end
		end
		shell.run("edit", target)
	end

	builtins.man = function(name)
		if not name then
			println("usage: man <topic>")
			return
		end
		local path = self.paths:join("etc", "man", name .. ".man")
		local data = readAll(path)
		if not data then
			println("no manual entry for " .. tostring(name))
			self.lastStatus = 1
			return
		end
		printLines(data)
	end

	builtins.which = function(name)
		if not name then
			println("usage: which <command>")
			return
		end
		if builtins[name] then
			println(name .. ": shell builtin")
		else
			local prog = listPrograms()[name]
			if prog then
				println(self.paths:displayPath(prog))
			else
				println("which: not found: " .. tostring(name))
				self.lastStatus = 1
			end
		end
	end

	builtins.useradd = function(name)
		requireInteractive("useradd")
		if effectiveUser() ~= "root" then
			println("useradd: permission denied (try sudo useradd)")
			self.lastStatus = 1
			return
		end
		if not name then
			println("usage: useradd <name>")
			return
		end
		self.term.write("Password: ")
		local pass = read("*")
		local ok, err = self.users:createUser(name, pass or "")
		if ok then
			println("created user " .. name)
		else
			println("useradd: " .. tostring(err))
			self.lastStatus = 1
		end
	end

	builtins.userdel = function(name)
		if effectiveUser() ~= "root" then
			println("userdel: permission denied (try sudo userdel)")
			self.lastStatus = 1
			return
		end
		if not name then
			println("usage: userdel <name>")
			return
		end
		local ok, err = self.users:removeUser(name)
		if ok then
			println("removed user " .. name)
		else
			println("userdel: " .. tostring(err))
			self.lastStatus = 1
		end
	end

	builtins.passwd = function(name)
		requireInteractive("passwd")
		name = name or self.users:currentName()
		if not name then
			println("passwd: no active user")
			return
		end
		if name ~= self.users:currentName() and effectiveUser() ~= "root" then
			println("passwd: only your own password can be changed")
			self.lastStatus = 1
			return
		end
		self.term.write("New password: ")
		local pass = read("*")
		local ok, err = self.users:setPassword(name, pass or "")
		if ok then
			println("password updated")
		else
			println("passwd: " .. tostring(err))
			self.lastStatus = 1
		end
	end

	builtins.su = function(name)
		requireInteractive("su")
		name = name or "root"
		if not self.users:exists(name) then
			println("su: unknown user: " .. tostring(name))
			self.lastStatus = 1
			return
		end
		self.term.write("Password: ")
		local pass = read("*")
		if self.users:authenticate(name, pass or "") then
			self.users:login(name)
			println("switched to " .. name)
		else
			println("su: authentication failed")
			self.lastStatus = 1
		end
	end

	-- sudo: elevation with a five-minute authentication cache (Ubuntu-style).
	-- In a window shell, pass the password on stdin with: echo <pw> | sudo -S ...
	builtins.sudo = function(sub, ...)
		local rest = { ... }
		if not sub then
			println("usage: sudo <command> [args]   (-S reads the password from stdin)")
			return
		end
		if sub == "-S" then
			sub = table.remove(rest, 1)
		end
		if not sub then
			println("usage: sudo <command> [args]")
			return
		end
		local user = self.users and self.users:currentName() or "user"
		if effectiveUser() == "root" or sudoCached(user) then
			-- elevated
		elseif self.captured or self._stdin then
			if self._stdin and #self._stdin > 0 then
				local pass = table.remove(self._stdin, 1)
				if not self.users:authenticate(user, pass or "") then
					println("sudo: incorrect password")
					self.lastStatus = 1
					return
				end
				sudoRemember(user)
			else
				println("sudo: password required; use 'echo <password> | sudo -S <command>' or run from the text shell")
				self.lastStatus = 1
				return
			end
		else
			self.term.write("[sudo] password for " .. user .. ": ")
			local pass = read("*")
			if not self.users:authenticate(user, pass or "") then
				println("sudo: incorrect password")
				self.lastStatus = 1
				return
			end
			sudoRemember(user)
		end
		if self.users and not self.users:isSudoer(user) then
			println("sudo: " .. user .. " is not in the sudoers file")
			self.lastStatus = 1
			return
		end
		local previous = self._elevated
		self._elevated = true
		-- external commands read the access policy through this global, so
		-- `sudo wget /etc/...` is allowed while `wget` alone is not
		_G.CLOVER_ELEVATED = { active = true }
		local ran, err = pcall(self.execute, self,
			sub .. (#rest > 0 and (" " .. table.concat(rest, " ")) or ""))
		self._elevated = previous
		_G.CLOVER_ELEVATED = nil
		if not ran then
			-- re-raise so the dispatcher reports it the usual way, but only
			-- after the elevation flag has been taken back down
			error(err, 0)
		end
	end

	builtins.apt = function(action, arg, ...)
		action = tostring(action or "")
		if action == "list" then
			for _, name in ipairs(self.packages:list()) do
				local marker = self.packages:isInstalled(name) and " [installed]" or ""
				println(name .. marker)
			end
		elseif action == "installed" then
			for _, entry in ipairs(self.packages:installed()) do
				println(entry.name .. " " .. entry.version .. (entry.auto and " [auto]" or ""))
			end
		elseif action == "search" then
			for _, name in ipairs(self.packages:search(arg or "")) do
				println(name)
			end
		elseif action == "info" then
			local meta = self.packages:info(arg or "")
			if not meta then
				println("apt: unknown package: " .. tostring(arg))
				self.lastStatus = 1
				return
			end
			println("name: " .. meta.name)
			println("version: " .. meta.version)
			println("source: " .. tostring(meta.source or "local"))
			println("description: " .. tostring(meta.description or ""))
			if meta.depends and #meta.depends > 0 then
				println("depends: " .. table.concat(meta.depends, ", "))
			end
			println("files:")
			for _, f in ipairs(meta.files or {}) do
				println("  " .. f)
			end
		elseif action == "depends" then
			local order, err = self.packages:resolve(arg or "")
			if not order then
				println("apt depends: " .. tostring(err))
				self.lastStatus = 1
				return
			end
			println(table.concat(order, " -> "))
		elseif action == "update" then
			println("Reading package lists...")
			local ok, counts = self.packages:update()
			if not ok then
				println("apt update: failed")
				self.lastStatus = 1
				return
			end
			println(string.format("Fetched %d package(s) from %d local and %d net source(s).",
				counts.packages or 0, counts.local_sources or 0, counts.net_sources or 0))
		elseif action == "upgrade" then
			println("Reading package lists... Done")
			local report = self.packages:upgrade()
			for _, line in ipairs(report.upgraded) do
				println("upgraded: " .. line)
			end
			println(string.format("%d upgraded, %d kept.", #report.upgraded, report.kept))
			for _, line in ipairs(report.failed) do
				println("failed: " .. line)
				self.lastStatus = 1
			end
		elseif action == "install" then
			local name = arg or ""
			local order, err = self.packages:resolve(name)
			if not order then
				println("apt install: " .. tostring(err))
				self.lastStatus = 1
				return
			end
			local todo = {}
			for _, pkg in ipairs(order) do
				if not self.packages:isInstalled(pkg) then
					todo[#todo + 1] = pkg
				end
			end
			if #todo == 0 then
				println(name .. " is already the newest version.")
				return
			end
			println("The following packages will be installed: " .. table.concat(todo, " "))
			local ok, installErr = self.packages:install(name)
			if ok then
				println("installed " .. table.concat(todo, " "))
			else
				println("apt install: " .. tostring(installErr))
				self.lastStatus = 1
			end
		elseif action == "remove" then
			local ok, err = self.packages:remove(arg or "")
			if ok then
				println("removed " .. tostring(arg))
			else
				println("apt remove: " .. tostring(err))
				self.lastStatus = 1
			end
		elseif action == "autoremove" then
			local removed = self.packages:autoremove()
			if #removed == 0 then
				println("0 to remove.")
			else
				println("removing: " .. table.concat(removed, " "))
			end
		elseif action == "verify" then
			local broken = self.packages:verify(arg)
			if #broken == 0 then
				println("all packages verified")
			else
				for _, line in ipairs(broken) do
					println("BROKEN " .. line)
				end
				self.lastStatus = 1
			end
		else
			println("usage: apt <list|installed|search|info|depends|update|upgrade|install|remove|autoremove|verify> [package]")
		end
	end

	builtins.alias = function(pair)
		if not pair then
			for k, v in pairs(self.aliases) do
				println(k .. "=" .. v)
			end
			return
		end
		local name, value = tostring(pair):match("^([^=]+)=(.*)$")
		if not name then
			println("usage: alias name=value")
			return
		end
		self.aliases[trim(name)] = trim(value)
	end

	builtins.unalias = function(name)
		if name and self.aliases[name] then
			self.aliases[name] = nil
		else
			println("unalias: no such alias: " .. tostring(name))
		end
	end

	builtins.run = function(path, ...)
		if not path then
			println("usage: run <file> [args]")
			return
		end
		local target = self.paths:osPath(path)
		if not fs.exists(target) then
			println("run: file not found: " .. tostring(path))
			self.lastStatus = 1
			return
		end
		runProgram(target, { ... })
	end

	-- ---------- the CloverOS GNOME desktop ----------
	local function desktopLauncher()
		local loaded, module = pcall(dofile, self.paths:join("runtime", "launcher.lua"))
		if not loaded or type(module) ~= "table" or type(module.new) ~= "function" then
			return nil, "runtime/launcher.lua is missing"
		end
		local built, launcher = pcall(module.new, {
			paths = self.paths,
			users = self.users,
			ui = self.ui,
			packages = self.packages,
			session = self,
			kernel = kernel,
		})
		if not built then
			return nil, tostring(launcher)
		end
		return launcher
	end

	-- `cloveros` starts the GNOME desktop from the text shell, the same
	-- session the graphical login starts. Options only print information.
	builtins.cloveros = function(...)
		local args = { ... }
		if self.captured or self._stdin then
			println("cloveros: needs an interactive terminal; run it from the text shell")
			self.lastStatus = 1
			return
		end
		for _, arg in ipairs(args) do
			if arg == "--help" or arg == "-h" then
				println("usage: cloveros [--help] [--version] [--apps]")
				println("  (no options)  start the CloverOS GNOME desktop")
				println("  --apps        list desktop applications")
				println("  --version     show the CloverOS version")
				return
			elseif arg == "--version" or arg == "-v" then
				local ok, v = pcall(dofile, self.paths:join("etc", "version.lua"))
				if ok and type(v) == "table" and v.version then
					println(v.name .. " " .. v.version())
				else
					println("CloverOS (version unknown)")
				end
				return
			elseif arg == "--apps" then
				local launcher, lerr = desktopLauncher()
				if not launcher then
					println("cloveros: " .. tostring(lerr))
					self.lastStatus = 1
					return
				end
				println("desktop applications:")
				for _, app in ipairs(launcher:appList()) do
					println(string.format("  %-12s %s", app.id, app.program))
				end
				return
			else
				println("cloveros: unknown option " .. tostring(arg))
				self.lastStatus = 1
				return
			end
		end

		local launcher, err = desktopLauncher()
		if not launcher then
			println("cloveros: " .. tostring(err))
			println("Run the installer again to add the desktop files.")
			self.lastStatus = 1
			return
		end
		local result = launcher:startDesktop()
		if self.ui then
			self.ui:clear()
		end
		if not result.ok then
			println("cloveros: desktop session failed: " .. tostring(result.error))
			println("Remaining in the text shell.")
			self.lastStatus = 1
			return
		end
		if result.logout then
			-- logging out from the desktop ends this shell session as well
			self.logoutRequested = true
			self.running = false
		else
			println("Desktop session ended. Back in the CloverOS text shell.")
		end
	end

	builtins.shutdown = function()
		if kernel then
			kernel.shutdown()
		else
			os.shutdown()
		end
	end

	builtins.reboot = function()
		if kernel then
			kernel.reboot()
		else
			os.reboot()
		end
	end

	builtins.dmesg = function()
		if kernel and kernel.journal then
			for _, line in ipairs(kernel.journal()) do
				println(line)
			end
		else
			println("dmesg: kernel journal unavailable")
		end
	end

	builtins.service = function(action, name)
		if not kernel or not kernel.service then
			println("service: kernel unavailable")
			self.lastStatus = 1
			return
		end
		action = tostring(action or "list")
		if action == "list" then
			for _, svc in ipairs(kernel.service.list()) do
				println(string.format("%-16s %s", svc, kernel.service.isRunning(svc) and "running" or "stopped"))
			end
		elseif action == "start" or action == "stop" or action == "restart" then
			local ok, err = kernel.service[action](name)
			if not ok then
				println("service: " .. tostring(err))
				self.lastStatus = 1
			else
				println(action .. "ed " .. tostring(name))
			end
		elseif action == "status" then
			println(tostring(name) .. ": " .. (kernel.service.isRunning(name) and "running" or "stopped"))
		else
			println("usage: service <list|start|stop|restart|status> [name]")
		end
	end

	builtins.versions = function()
		local ok, v = pcall(dofile, self.paths:join("etc", "version.lua"))
		if ok and type(v) == "table" and v.version then
			println(v.name .. " " .. v.version())
		else
			println("CloverOS (version unknown)")
		end
		println("CraftOS " .. os.version())
		println("Computer " .. os.getComputerID())
	end

	-- ---------- pipeline machinery ----------
	local INTERACTIVE_ONLY = { music = true, mspaint = true }

	local function resolveAlias(cmd)
		local seen = {}
		while self.aliases[cmd] and not seen[cmd] do
			seen[cmd] = true
			cmd = self.aliases[cmd]
		end
		return cmd
	end

	local function parseCommand(tokens, from, to)
		-- splits a token range into pipeline stages with redirects
		local stages = {}
		local current = { words = {}, redir = {} }
		local i = from
		while i <= to do
			local tok = tokens[i]
			if tok.op == "|" then
				stages[#stages + 1] = current
				current = { words = {}, redir = {} }
			elseif tok.op == ">" or tok.op == ">>" or tok.op == "<" then
				local target = tokens[i + 1]
				if not target or target.op then
					return nil, "syntax error near '" .. tostring(tok.op) .. "'"
				end
				if tok.op == "<" then
					current.redir.input = target.text
				else
					current.redir.output = target.text
					current.redir.append = tok.op == ">>"
				end
				i = i + 1
			else
				current.words[#current.words + 1] = tok
			end
			i = i + 1
		end
		stages[#stages + 1] = current
		return stages
	end

	-- runs one stage; returns outputLines (array) and status code
	local function runStage(stage, stdinLines)
		-- expand all words
		local words = {}
		for _, tok in ipairs(stage.words) do
			for _, expanded in ipairs(expandToken(tok)) do
				words[#words + 1] = expanded
			end
		end
		if #words == 0 then
			return {}, 0
		end
		local cmd = words[1]
		table.remove(words, 1)

		-- stdin override from redirection
		local stdin = stdinLines
		if stage.redir.input then
			local data = readAll(self.paths:osPath(stage.redir.input))
			if not data then
				emitLine("sh: no such file: " .. tostring(stage.redir.input))
				return {}, 1
			end
			stdin = {}
			for line in data:gmatch("(.-)\n") do
				stdin[#stdin + 1] = line
			end
			if data ~= "" and data:sub(-1) ~= "\n" then
				stdin[#stdin + 1] = data:match("([^\n]*)$")
			end
		end

		local out, status = {}, 0
		local function sink(line)
			out[#out + 1] = line
		end

		local aliasTarget = resolveAlias(cmd)
		if aliasTarget ~= cmd then
			-- alias may carry arguments: re-split it
			local aliasWords = {}
			for _, tok in ipairs(tokenize(aliasTarget)) do
				for _, expanded in ipairs(expandToken(tok)) do
					aliasWords[#aliasWords + 1] = expanded
				end
			end
			cmd = table.remove(aliasWords, 1)
			for i = #aliasWords, 1, -1 do
				table.insert(words, 1, aliasWords[i])
			end
		end

		if builtins[cmd] then
			local previousSink, previousStdin = self._sink, self._stdin
			self._sink, self._stdin = sink, stdin
			-- a builtin reports failure by setting lastStatus; clear it first
			-- so a previous failure does not leak into this command
			self.lastStatus = 0
			local ok, err = pcall(builtins[cmd], table.unpack(words))
			self._sink, self._stdin = previousSink, previousStdin
			if not ok then
				sink("sh: " .. cmd .. " failed: " .. tostring(err))
				self.lastStatus = 1
			end
			status = self.lastStatus
			return out, status
		end

		local path = listPrograms()[cmd]
		if not path then
			sink("sh: no such command: " .. tostring(cmd))
			return out, 1
		end

		if INTERACTIVE_ONLY[cmd] and (self.captured or stdin or stage.redir.output) then
			sink("sh: '" .. cmd .. "' needs an interactive terminal; run it from the text shell")
			return out, 1
		end

		if self.captured or stdin or stage.redir.output then
			-- captured run: program output goes through the sink
			local vterm = makeVirtualTerm(sink)
			local stdinQueue = {}
			for _, line in ipairs(stdin or {}) do
				stdinQueue[#stdinQueue + 1] = line
			end
			local env = setmetatable({
				shell = childShellProxy(self),
				term = vterm,
				multishell = nil,
				print = function(...)
					local parts = {}
					for i = 1, select("#", ...) do
						parts[i] = tostring(select(i, ...))
					end
					sink(table.concat(parts, " "))
				end,
				write = function(text)
					vterm.write(text)
				end,
				printError = function(...)
					local parts = {}
					for i = 1, select("#", ...) do
						parts[i] = tostring(select(i, ...))
					end
					sink("Error: " .. table.concat(parts, " "))
				end,
				read = function()
					-- stdin EOF: end of the piped input queue
					return table.remove(stdinQueue, 1)
				end,
				io = setmetatable({ write = function(text) vterm.write(text) end }, { __index = _ENV.io }),
			}, { __index = _ENV })
			local ok, result = pcall(os.run, env, path, table.unpack(words))
			vterm.flush()
			if not ok then
				sink("sh: " .. cmd .. " crashed: " .. tostring(result))
				return out, 1
			end
			return out, 0
		end

		-- direct interactive run (text shell, no pipes/redirects involved)
		local ok, result = pcall(shell.run, path, table.unpack(words))
		if not ok then
			println("sh: " .. cmd .. " crashed: " .. tostring(result))
			return out, 1
		end
		return out, 0
	end

	function self:execute(line)
		line = trim(line)
		if line == "" then
			return
		end
		-- history is per user, so pick up the right file as soon as the
		-- session changes account (a logout followed by a login reuses the
		-- same shell instance)
		local who = self.users and self.users:currentName() or nil
		if who ~= self._historyUser then
			saveHistory()
			self._historyUser = who
			loadHistory()
		end
		if #line > 1 and line:sub(1, 1) == "!" then
			local num = tonumber(line:sub(2))
			if num and self.history[num] then
				return self:execute(self.history[num])
			end
			println("sh: event not found: " .. line)
			return
		end
		self.history[#self.history + 1] = line
		saveHistory()

		-- split on ; && || first (sequencing), then pipes within each command
		local tokens = tokenize(line)
		local segments = {}
		local current = { from = 1, cond = "any" }
		local n = #tokens
		for i = 1, n do
			local tok = tokens[i]
			if tok.op == ";" or tok.op == "&&" or tok.op == "||" then
				current.to = i - 1
				segments[#segments + 1] = current
				current = { from = i + 1, cond = tok.op }
			end
		end
		current.to = n
		segments[#segments + 1] = current

		for _, seg in ipairs(segments) do
			if seg.to >= seg.from then
				local shouldRun = true
				if seg.cond == "&&" and self.lastStatus ~= 0 then
					shouldRun = false
				elseif seg.cond == "||" and self.lastStatus == 0 then
					shouldRun = false
				end
				if shouldRun then
					local stages, err = parseCommand(tokens, seg.from, seg.to)
					if not stages then
						println("sh: " .. tostring(err))
						self.lastStatus = 2
					else
						local stdin = nil
						local status = 0
						for si, stage in ipairs(stages) do
							local out
							out, status = runStage(stage, stdin)
							if si < #stages then
								stdin = out
							else
								-- final stage: emit or redirect
								if stage.redir.output then
									local display = self.paths:displayPath(stage.redir.output)
									if not canWrite(display) then
										denyWrite(stage.redir.output)
										status = 1
									else
										local body = table.concat(out, "\n")
										if #out > 0 then
											body = body .. "\n"
										end
										local target = self.paths:osPath(stage.redir.output)
										if stage.redir.append then
											local existing = readAll(target) or ""
											writeAll(target, existing .. body)
										else
											writeAll(target, body)
										end
									end
								else
									for _, outLine in ipairs(out) do
										emitLine(outLine)
									end
								end
								self.lastStatus = status
							end
						end
					end
				end
			end
		end
	end

	function self:complete(before, after)
		if (after or "") ~= "" then
			return {}
		end
		local partial = before:match("(%S*)$")
		local isCommand = before:match("^%s*([^%s]*)$") ~= nil
		local out = {}
		local function offer(name)
			if name:sub(1, #partial) == partial then
				out[#out + 1] = name:sub(#partial + 1)
			end
		end
		if isCommand then
			for name in pairs(builtins) do
				offer(name)
			end
			for name in pairs(listPrograms()) do
				offer(name)
			end
		else
			-- complete file and directory names
			local dirPart, namePart = partial:match("^(.*[/\\])([^/\\]*)$")
			local osDir = dirPart and self.paths:osPath(dirPart) or self.paths:osPath(".")
			if fs.isDir(osDir) then
				for _, name in ipairs(fs.list(osDir)) do
					local suffix = name:sub(#(namePart or partial) + 1)
					if name:sub(1, #(namePart or partial)) == (namePart or partial) then
						if fs.isDir(fs.combine(osDir, name)) then
							out[#out + 1] = suffix .. "/"
						else
							out[#out + 1] = suffix
						end
					end
				end
			end
		end
		table.sort(out)
		return out
	end

	function self:forkWindowShell()
		local child = M.new({
			paths = self.paths,
			users = self.users,
			ui = nil,
			packages = self.packages,
		})
		child.captured = {}
		child.errors = {}
		child.users = self.users
		-- shell.run inside a window must not touch the real terminal; failing
		-- programs report through drainOutput like normal output
		function child:drainOutput()
			local out = self.captured
			self.captured = {}
			return out
		end
		local childExecute = child.execute
		function child:execute(line)
			child.captured = child.captured or {}
			local ok, err = pcall(childExecute, self, line)
			if not ok then
				self.errors[#self.errors + 1] = "sh: " .. tostring(err)
			end
		end
		return child
	end

	function self:promptLine()
		local user = effectiveUser()
		local cwd = self.paths:displayPath()
		if user == "root" then
			return string.format("root@clover:%s# ", cwd)
		end
		return string.format("%s@clover:%s$ ", user, cwd)
	end

	function self:run()
		loadHistory()
		-- Ubuntu-style message of the day
		local motd = readAll(self.paths:join("etc", "motd.txt"))
		if motd and trim(motd) ~= "" then
			printLines(motd)
		end
		while self.running do
			local prompt = self:promptLine()
			local line = self.ui:prompt(prompt, false, self.history, function(before, after)
				return self:complete(before, after)
			end)
			if line == nil then
				return
			end
			local ok, err = pcall(self.execute, self, line)
			if not ok then
				println("sh: internal error: " .. tostring(err))
			end
		end
	end

	loadHistory()
	return self
end

return M
