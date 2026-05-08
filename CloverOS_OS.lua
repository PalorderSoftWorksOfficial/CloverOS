-- CloverOS main interface and shell
---@diagnostic disable: undefined-global
-- luacheck: globals peripheral fs shell term colors textutils read write os
if not kernel then
	error("CloverOS requires the kernel API to be loaded in the global environment, Please run the OS via boot/kernel.lua or boot/pxboot.lua")
end
local monitor = peripheral.find("monitor")
local fs = fs
local shell = shell
local term = term
local colors = colors
local textutils = textutils

local function mirrorWrite(text)
	write(text)
	if monitor then
		monitor.write(text)
	end
end

local function mirrorClear()
	term.clear()
	term.setCursorPos(1, 1)
	if monitor then
		monitor.clear()
		monitor.setCursorPos(1, 1)
	end
end

local function mirrorSetCursor(x, y)
	term.setCursorPos(x, y)
	if monitor then
		monitor.setCursorPos(x, y)
	end
end
local function readInput(prompt, hidden)
	prompt = tostring(prompt or "")
	write(prompt)
	if hidden then
		return read("*")
	end
	return read()
end
local Terminal = {}

function Terminal.clear()
	local bg, fg = colors.black, colors.white
	if settingsLoaded then
		if editionSettings.theme == "dark" then
			bg, fg = colors.black, colors.gray
		elseif editionSettings.theme == "light" then
			bg, fg = colors.white, colors.black
		elseif editionSettings.theme == "colorful" then
			bg, fg = colors.blue, colors.yellow
		end
	end
	term.setBackgroundColor(bg)
	term.setTextColor(fg)
	if monitor then
		monitor.setBackgroundColor(bg)
		monitor.setTextColor(fg)
	end
	mirrorClear()
end

function Terminal.write(text)
	mirrorWrite(text)
end

function Terminal.print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	mirrorWrite(table.concat(parts, "\t"))
	mirrorWrite("\n")
end

function Terminal.read(hidden)
	if hidden then
		return read("*")
	end
	return read()
end

function Terminal.setCursor(x, y)
	mirrorSetCursor(x, y)
end

function Terminal.getSize()
	return term.getSize()
end

function Terminal.centerText(y, text, fg, bg)
	if fg then
		term.setTextColor(fg)
	end
	if bg then
		term.setBackgroundColor(bg)
	end
	local w = select(1, Terminal.getSize())
	local x = math.max(1, math.floor((w - #text) / 2) + 1)
	mirrorSetCursor(x, y)
	mirrorWrite(text)
	term.setTextColor(colors.white)
	term.setBackgroundColor(colors.black)
end

local function findCloverRoot()
	if fs.exists("/CloverOS_OS.lua") and fs.exists("/CloverOS_API.lua") then
		return "/"
	end
	for i = 0, 99 do
		local root = "/disk" .. (i == 0 and "" or i)
		if fs.exists(root .. "/CloverOS_OS.lua") and fs.exists(root .. "/CloverOS_API.lua") then
			return root
		end
	end
	return "/"
end

local ROOT = findCloverRoot()
local AUTH_FILE = ROOT .. "/auth"
local USERS_FILE = ROOT .. "/users"
local currentUser = nil

local settingsLoaded = false
local editionSettings = {}

if settings then
	editionSettings.softinstall = settings.get("softinstall", false)
	editionSettings.default = settings.get("default", true)
	editionSettings.emulator = settings.get("emulator", false)
	editionSettings.turtle = settings.get("turtle", false)
	editionSettings.envType = settings.get("envType", "cct")
	editionSettings.theme = settings.get("theme", "default")
	editionSettings.autoLogin = settings.get("autoLogin", false)
	editionSettings.soundEnabled = settings.get("soundEnabled", true)
	editionSettings.performanceMode = settings.get("performanceMode", "standard")
	settingsLoaded = true
end

local function loadAuth()
	if not fs.exists(AUTH_FILE) then
		return nil
	end

	local handle = fs.open(AUTH_FILE, "r")
	if not handle then
		return nil
	end

	local ok, auth = pcall(textutils.unserialize, handle.readAll())
	handle.close()

	if ok and type(auth) == "table" and auth.user and auth.pass then
		return auth
	end

	return nil
end

local function saveAuth(username, password)
	local handle = fs.open(AUTH_FILE, "w")
	if not handle then
		return false
	end
	handle.write(textutils.serialize({ user = tostring(username), pass = tostring(password) }))
	handle.close()
	return true
end

local function login()
	local auth = loadAuth()
	if not auth then
		Terminal.clear()
		Terminal.centerText(2, "CloverOS Setup", colors.white, colors.blue)
		Terminal.print("")
		local username = readInput("New username: ")
		local password = readInput("New password: ", true)
		saveAuth(username, password)
		Terminal.print("Account created. Starting CloverOS...")
		os.sleep(1.2)
		return
	end

	while true do
		Terminal.clear()
		Terminal.centerText(2, "CloverOS Login", colors.white, colors.blue)
		Terminal.print("")
		local username = readInput("Username: ")
		local password = readInput("Password: ", true)

		if username == auth.user and password == auth.pass then
			Terminal.print("Login successful.")
			os.sleep(1)
			return
		end

		Terminal.print("Invalid credentials. Try again.")
		os.sleep(1.2)
	end
end

local function simulateLoading()
	Terminal.clear()
	local logLines = {
		"[BOOT] Initializing CloverOS...",
		"[BOOT] Detecting hardware...",
		"[BOOT] Loading modules...",
		"[BOOT] Mounting filesystems...",
		"[BOOT] Starting core services...",
		"[OK] CloverOS ready.",
	}

	local sleepTime = 0.25
	if settingsLoaded and editionSettings.performanceMode == "low" then
		sleepTime = 0.1
	end

	local w, _ = Terminal.getSize()
	for i, message in ipairs(logLines) do
		Terminal.centerText(4 + i, message)
		os.sleep(sleepTime)
	end
	os.sleep(sleepTime * 2)
end
local function DISK_ROOT()
	local function isCloverRoot(root)
		return fs.exists(root .. "/CloverOS_API.lua") and fs.exists(root .. "/boot/kernel.lua")
	end

	if isCloverRoot("") or isCloverRoot("/") then
		return ""
	end
	for i = 1, 99 do
		local root = "/disk" .. (i == 1 and "" or i)
		if isCloverRoot(root) then
			return root
		end
	end

	return nil
end
local completionInfo = {}
local aliases = {}
local shellEnv = {}

local function listCommands()
	local commands = {}
	local paths = {}

	if ROOT and ROOT ~= "" then
		paths[#paths + 1] = ROOT .. "/bin"
	end

	paths[#paths + 1] = "/bin"

	for _, path in ipairs(paths) do
		if fs.exists(path) and fs.isDir(path) then
			for _, file in ipairs(fs.list(path)) do
				local full = fs.combine(path, file)
				if fs.exists(full) and not fs.isDir(full) then
					local isExecutable = file:match("%.[lL][uU][aA]$")
						or file:match("%.[eE][xX][eE]$")
						or file:match("%.[dD][lL][lL]$")
						or not file:match("%.")

					if isExecutable then
						local name = file:gsub("%..+$", "")
						commands[name] = full
					end
				end
			end
		end
	end

	return commands
end

local function tokenize(line)
	local words = {}
	local word = {}
	local quoted = false
	local singleQuoted = false
	local escape = false

	for i = 1, #line do
		local c = line:sub(i, i)

		if escape then
			word[#word + 1] = c
			escape = false
		elseif c == "\\" and not singleQuoted then
			escape = true
		elseif c == '"' and not singleQuoted then
			quoted = not quoted
		elseif c == "'" and not quoted then
			singleQuoted = not singleQuoted
		elseif not quoted and c:match("%s") then
			if #word > 0 then
				words[#words + 1] = table.concat(word)
				word = {}
			end
		else
			word[#word + 1] = c
		end
	end

	if #word > 0 then
		words[#words + 1] = table.concat(word)
	end

	return words
end

-- Expand environment variables like $VAR and ~
local function expandToken(tok)
	if not tok or tok == "" then
		return tok
	end
	-- Tilde expansion at start
	if tok:sub(1, 1) == "~" then
		local home = shellEnv.HOME or ROOT or "/"
		if tok == "~" then
			tok = home
		elseif tok:sub(2, 2) == "/" then
			tok = home .. tok:sub(2)
		end
	end

	-- Variable expansion: ${VAR} or $VAR
	local function repl(var)
		local name = var:match("^%${(.-)}$") or var:match("^%$(.-)$")
		if not name then
			return var
		end
		return tostring(shellEnv[name] or "")
	end

	-- Replace ${VAR}
	tok = tok:gsub("%${(.-)}", function(n)
		return tostring(shellEnv[n] or "")
	end)
	-- Replace $VAR (simple)
	tok = tok:gsub("%$(%w+)", function(n)
		return tostring(shellEnv[n] or "")
	end)

	return tok
end

local function startsWith(value, prefix)
	return value:sub(1, #prefix) == prefix
end

local function resolveAlias(name)
	return aliases[name] or name
end

local function registerCompletion(command, fn)
	completionInfo[command] = fn
end

local function completePrograms(prefix)
	local commands = listCommands()
	local results = {}
	local seen = {}

	for aliasName in pairs(aliases) do
		if startsWith(aliasName, prefix) then
			local suffix = aliasName:sub(#prefix + 1)
			if not seen[suffix] then
				seen[suffix] = true
				results[#results + 1] = suffix
			end
		end
	end

	for name in pairs(commands) do
		if startsWith(name, prefix) then
			local suffix = name:sub(#prefix + 1)
			if not seen[suffix] then
				seen[suffix] = true
				results[#results + 1] = suffix
			end
		end
	end

	table.sort(results)
	return results
end

local function completeLine(line)
	if not line or line == "" then
		return completePrograms("")
	end

	local words = tokenize(line)
	local endsWithSpace = line:sub(-1) == " "
	local index = #words

	if endsWithSpace then
		index = index + 1
	end

	if index <= 1 then
		local part = words[1] or ""
		local resolved = resolveAlias(part)

		if completionInfo[resolved] then
			return { " " }
		end

		local results = completePrograms(part)
		for i = 1, #results do
			local candidate = part .. results[i]
			local candidateResolved = resolveAlias(candidate)
			if completionInfo[candidateResolved] then
				results[i] = results[i] .. " "
			end
		end
		return results
	end

	local commandName = resolveAlias(words[1] or "")
	local fn = completionInfo[commandName]
	if fn then
		local current = words[index] or ""
		local previous = {}
		for i = 1, index - 1 do
			previous[i] = words[i]
		end
		return fn(index - 1, current, previous)
	end

	return nil
end

local function readLine(prompt, history)
	if type(read) == "function" then
		write(prompt)
		return read(nil, history, completeLine)
	end

	return readInput(prompt)
end

local function shellBuiltinHelp()
	Terminal.print("Available commands:")
	Terminal.print("  help")
	Terminal.print("  exit")
	Terminal.print("  shutdown")
	Terminal.print("  installer")
	Terminal.print("  run <command>")

	local commands = listCommands()
	local names = {}
	for name in pairs(commands) do
		names[#names + 1] = name
	end
	table.sort(names)

	for _, name in ipairs(names) do
		Terminal.print("  " .. name)
	end
end

local function shellBuiltinSettings()
	Terminal.print("CloverOS v1.0.0")
	Terminal.print("Author: CloverOS Team")
end

registerCompletion("help", function()
	local items = { "exit", "shutdown", "installer", "run" }
	local commands = listCommands()
	for name in pairs(commands) do
		items[#items + 1] = name
	end
	table.sort(items)
	return items
end)

registerCompletion("run", function(index, current)
	if index ~= 1 then
		return nil
	end

	local commands = listCommands()
	local items = {}
	local seen = {}

	for name in pairs(commands) do
		if startsWith(name, current) and not seen[name] then
			seen[name] = true
			items[#items + 1] = name:sub(#current + 1)
		end
	end

	for aliasName in pairs(aliases) do
		if startsWith(aliasName, current) and not seen[aliasName] then
			seen[aliasName] = true
			items[#items + 1] = aliasName:sub(#current + 1)
		end
	end

	table.sort(items)
	return items
end)
local commandHistory = {}
local shellEnv = {}
local function shellUsage(cmd, usage)
	Terminal.print("Usage: " .. cmd .. (usage and (" " .. usage) or ""))
end

local function resolvePath(path)
	if not path or path == "" then
		return shell.dir()
	end
	return shell.resolve(path)
end

local function printFile(path)
	local h = fs.open(path, "r")
	if not h then
		Terminal.print("Unable to open file: " .. tostring(path))
		return
	end

	while true do
		local line = h.readLine()
		if line == nil then
			break
		end
		Terminal.print(line)
	end

	h.close()
end

local function countLines(path)
	local h = fs.open(path, "r")
	if not h then
		return nil
	end

	local n = 0
	while h.readLine() do
		n = n + 1
	end
	h.close()
	return n
end

local function tailFile(path, n)
	n = tonumber(n) or 10
	local h = fs.open(path, "r")
	if not h then
		Terminal.print("Unable to open file: " .. tostring(path))
		return
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

	local start = math.max(1, #lines - n + 1)
	for i = start, #lines do
		Terminal.print(lines[i])
	end
end

local builtins = {
	help = function()
		Terminal.print("Available commands:")
		Terminal.print("  help")
		Terminal.print("  man <command>")
		Terminal.print("  exit")
		Terminal.print("  shutdown")
		Terminal.print("  reboot")
		Terminal.print("  installer")
		Terminal.print("  run <command>")
		Terminal.print("  cd <dir>")
		Terminal.print("  pwd")
		Terminal.print("  clear")
		Terminal.print("  echo <text>")
		Terminal.print("  sleep <seconds>")
		Terminal.print("  history")
		Terminal.print("  alias [name value]")
		Terminal.print("  unalias <name>")
		Terminal.print("  which <command>")
		Terminal.print("  touch <file>")
		Terminal.print("  cat <file>")
		Terminal.print("  head <file> [n]")
		Terminal.print("  tail <file> [n]")
		Terminal.print("  mkdir <dir>")
		Terminal.print("  rmdir <dir>")
		Terminal.print("  rm <path>")
		Terminal.print("  cp <src> <dst>")
		Terminal.print("  mv <src> <dst>")
		Terminal.print("  stat <path>")
		Terminal.print("  date")
		Terminal.print("  time")
		Terminal.print("  whoami")
		Terminal.print("  hostname")

		local commands = listCommands()
		local names = {}
		for name in pairs(commands) do
			names[#names + 1] = name
		end
		table.sort(names)

		Terminal.print("")
		Terminal.print("Programs:")
		for _, name in ipairs(names) do
			Terminal.print("  " .. name)
		end
	end,

	exit = function()
		return true
	end,

	shutdown = function()
		os.shutdown()
	end,

	reboot = function()
		os.reboot()
	end,

	installer = function()
		if _G.CloverOS and type(_G.CloverOS.runInstaller) == "function" then
			_G.CloverOS.runInstaller()
		else
			shell.run("wget", "run", "https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua")
		end
	end,

	run = function(...)
		local args = { ... }
		if #args == 0 then
			Terminal.print("Usage: run <command>")
			return
		end

		local target = table.remove(args, 1)
		local commands = listCommands()
		local targetPath = commands[resolveAlias(target)]

		if not targetPath then
			Terminal.print("No such program")
			return
		end

		shell.run(targetPath, table.unpack(args))
	end,

	cd = function(path)
		if not path or path == "" then
			shell.setDir(ROOT)
			return
		end

		local target = resolvePath(path)
		if fs.isDir(target) then
			shell.setDir(target)
		else
			Terminal.print("Not a directory: " .. tostring(path))
		end
	end,

	pwd = function()
		Terminal.print(shell.dir())
	end,

	clear = function()
		Terminal.clear()
	end,

	echo = function(...)
		Terminal.print(table.concat({ ... }, " "))
	end,

	sleep = function(sec)
		sec = tonumber(sec) or 0
		if sec > 0 then
			os.sleep(sec)
		end
	end,

	history = function()
		for i, line in ipairs(commandHistory) do
			Terminal.print(string.format("%4d  %s", i, line))
		end
	end,

	alias = function(name, ...)
		if not name or name == "" then
			local keys = {}
			for k in pairs(aliases) do
				keys[#keys + 1] = k
			end
			table.sort(keys)
			for _, k in ipairs(keys) do
				Terminal.print(k .. "=" .. aliases[k])
			end
			return
		end

		local value = table.concat({ ... }, " ")
		if value == "" then
			Terminal.print("Usage: alias <name> <command>")
			return
		end

		aliases[name] = value
	end,

	unalias = function(name)
		if not name or name == "" then
			Terminal.print("Usage: unalias <name>")
			return
		end
		aliases[name] = nil
	end,

	which = function(cmd)
		if not cmd or cmd == "" then
			Terminal.print("Usage: which <command>")
			return
		end
		local resolved = resolveAlias(cmd)
		if builtins[resolved] then
			Terminal.print(resolved .. " is a builtin")
			return
		end

		local commands = listCommands()
		if commands[resolved] then
			Terminal.print(commands[resolved])
			return
		end

		-- search PATH
		local pathEnv = shellEnv.PATH or shell.path and shell.path() or "/bin"
		for p in pathEnv:gmatch("[^:]+") do
			local candidate = fs.combine(p, resolved)
			if fs.exists(candidate) and not fs.isDir(candidate) then
				Terminal.print(candidate)
				return
			end
		end

		Terminal.print("Not found")
	end,

	export = function(name, value)
		if not name or name == "" then
			-- print all
			for k, v in pairs(shellEnv) do
				Terminal.print(k .. "=" .. tostring(v))
			end
			return
		end
		shellEnv[name] = tostring(value or "")
	end,

	man = function(cmd)
		if not cmd or cmd == "" then
			Terminal.print("Usage: man <command>")
			return
		end
		-- check builtin help usage and command metadata
		if builtins[cmd] and debug and type(builtins[cmd]) == "function" then
			Terminal.print("No manual entry for builtin: " .. cmd)
			return
		end
		local commands = listCommands()
		local path = commands[cmd]
		if not path then
			Terminal.print("No manual entry for: " .. cmd)
			return
		end
		-- try to read header comments as manual
		local header = readCommandHeader(path, 200)
		if header and #header > 0 then
			for _, line in ipairs(header) do
				Terminal.print(line)
			end
			return
		end
		Terminal.print("No manual entry for: " .. cmd)
	end,

	touch = function(path)
		if not path or path == "" then
			Terminal.print("Usage: touch <file>")
			return
		end

		local target = resolvePath(path)
		if fs.exists(target) then
			return
		end

		local h = fs.open(target, "w")
		if h then
			h.close()
		end
	end,

	cat = function(...)
		local args = { ... }
		if #args == 0 then
			Terminal.print("Usage: cat <file> [file...]")
			return
		end

		for _, p in ipairs(args) do
			local target = resolvePath(p)
			if not fs.exists(target) then
				Terminal.print("File not found: " .. tostring(p))
			elseif fs.isDir(target) then
				Terminal.print("Is a directory: " .. tostring(p))
			else
				printFile(target)
			end
		end
	end,

	head = function(path, n)
		if not path or path == "" then
			Terminal.print("Usage: head <file> [n]")
			return
		end

		local target = resolvePath(path)
		local count = tonumber(n) or 10
		local h = fs.open(target, "r")
		if not h then
			Terminal.print("Unable to open file: " .. tostring(path))
			return
		end

		local i = 0
		while i < count do
			local line = h.readLine()
			if not line then
				break
			end
			Terminal.print(line)
			i = i + 1
		end
		h.close()
	end,

	tail = function(path, n)
		if not path or path == "" then
			Terminal.print("Usage: tail <file> [n]")
			return
		end

		local target = resolvePath(path)
		tailFile(target, n)
	end,

	mkdir = function(path)
		if not path or path == "" then
			Terminal.print("Usage: mkdir <dir>")
			return
		end

		local target = resolvePath(path)
		if fs.exists(target) then
			Terminal.print("Path already exists: " .. tostring(path))
			return
		end

		fs.makeDir(target)
	end,

	rmdir = function(path)
		if not path or path == "" then
			Terminal.print("Usage: rmdir <dir>")
			return
		end

		local target = resolvePath(path)
		if not fs.exists(target) then
			Terminal.print("Not found: " .. tostring(path))
			return
		end

		if not fs.isDir(target) then
			Terminal.print("Not a directory: " .. tostring(path))
			return
		end

		fs.delete(target)
	end,

	rm = function(path)
		if not path or path == "" then
			Terminal.print("Usage: rm <path>")
			return
		end

		local target = resolvePath(path)
		if not fs.exists(target) then
			Terminal.print("Not found: " .. tostring(path))
			return
		end

		fs.delete(target)
	end,

	cp = function(src, dst)
		if not src or not dst then
			Terminal.print("Usage: cp <src> <dst>")
			return
		end

		local a = resolvePath(src)
		local b = resolvePath(dst)
		if not fs.exists(a) then
			Terminal.print("Source not found: " .. tostring(src))
			return
		end

		fs.copy(a, b)
	end,

	mv = function(src, dst)
		if not src or not dst then
			Terminal.print("Usage: mv <src> <dst>")
			return
		end

		local a = resolvePath(src)
		local b = resolvePath(dst)
		if not fs.exists(a) then
			Terminal.print("Source not found: " .. tostring(src))
			return
		end

		fs.move(a, b)
	end,

	stat = function(path)
		if not path or path == "" then
			Terminal.print("Usage: stat <path>")
			return
		end

		local target = resolvePath(path)
		if not fs.exists(target) then
			Terminal.print("Not found: " .. tostring(path))
			return
		end

		Terminal.print("Path: " .. target)
		Terminal.print("Type: " .. (fs.isDir(target) and "directory" or "file"))
		if not fs.isDir(target) then
			Terminal.print("Size: " .. tostring(fs.getSize(target)))
		end
	end,

	date = function()
		Terminal.print(textutils.formatTime(os.time(), true))
	end,

	time = function()
		Terminal.print(textutils.formatTime(os.time(), true))
	end,

	whoami = function()
		Terminal.print("root")
	end,

	hostname = function()
		if settingsLoaded and editionSettings.envType == "craftos" then
			Terminal.print("CloverOS-CraftOS")
		else
			Terminal.print("CloverOS")
		end
	end,
}
local commandMeta = {}

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function startsWith(s, prefix)
	return s:sub(1, #prefix) == prefix
end

local function readCommandHeader(path, maxLines)
	local f = fs.open(path, "r")
	if not f then
		return nil
	end

	local lines = {}
	for _ = 1, maxLines do
		local line = f.readLine()
		if not line then
			break
		end
		lines[#lines + 1] = line
		if not startsWith(trim(line), "--") then
			break
		end
	end

	f.close()
	return lines
end

local function parseCommandMeta(path)
	local header = readCommandHeader(path, 40)
	if not header then
		return nil
	end

	local meta = {
		usage = nil,
		completes = {},
	}

	for _, line in ipairs(header) do
		local usage = line:match("^%-%-%s*@usage%s+(.+)$")
		if usage then
			meta.usage = trim(usage)
		end

		local index, kind, extra = line:match("^%-%-%s*@complete%s+(%d+)%s+(%S+)%s*(.*)$")
		if index and kind then
			meta.completes[tonumber(index)] = {
				kind = kind,
				extra = trim(extra or ""),
			}
		end
	end

	return meta
end

local function scanCommandMetadata()
	local commands = listCommands()
	for name, path in pairs(commands) do
		local meta = parseCommandMeta(path)
		if meta then
			commandMeta[name] = meta
		end
	end
end

local function completeFiles(prefix)
	local results = {}
	local seen = {}

	local paths = { "/bin" }
	local root = DISK_ROOT()
	if root then
		paths[#paths + 1] = root .. "/bin"
	end

	for _, path in ipairs(paths) do
		if fs.exists(path) and fs.isDir(path) then
			for _, file in ipairs(fs.list(path)) do
				if startsWith(file, prefix) and not seen[file] then
					seen[file] = true
					results[#results + 1] = file:sub(#prefix + 1)
				end
			end
		end
	end

	table.sort(results)
	return results
end

local function completeFromMeta(commandName, index, current, previous)
	local meta = commandMeta[commandName]
	if not meta then
		return nil
	end

	local rule = meta.completes[index]
	if not rule then
		return nil
	end

	if rule.kind == "file" then
		return completeFiles(current)
	end

	if rule.kind == "command" then
		local cmds = listCommands()
		local out = {}
		for name in pairs(cmds) do
			if startsWith(name, current) then
				out[#out + 1] = name:sub(#current + 1)
			end
		end
		table.sort(out)
		return out
	end

	if rule.kind == "list" and rule.extra ~= "" then
		local out = {}
		for item in rule.extra:gmatch("[^,%s]+") do
			if startsWith(item, current) then
				out[#out + 1] = item:sub(#current + 1)
			end
		end
		table.sort(out)
		return out
	end

	return nil
end

local function autoRegisterCompletions()
	scanCommandMetadata()

	local commands = listCommands()
	for name in pairs(commands) do
		if commandMeta[name] then
			registerCompletion(name, function(index, current, previous)
				return completeFromMeta(name, index, current, previous)
			end)
		end
	end
end
local function formatPrompt()
	local dir = shell.dir()

	if dir == "" or dir == "/" then
		return "root@CloverOS:~$ "
	end

	local root = ROOT
	if root == "/" then
		return "root@CloverOS:~" .. dir .. "$ "
	end

	if dir:sub(1, #root) == root then
		local rel = dir:sub(#root + 1)
		if rel == "" then
			rel = "/"
		end
		if rel:sub(1, 1) ~= "/" then
			rel = "/" .. rel
		end
		return "root@CloverOS:~" .. rel .. "$ "
	end

	return "root@CloverOS:" .. dir .. "$ "
end
local function runShell()
	autoRegisterCompletions()
	Terminal.clear()
	Terminal.print("Welcome to CloverOS Shell. Type help for available commands.")

	local history = {}

	-- initialize basic shell environment
	shellEnv.PATH = shell.path and shell.path() or "/bin"
	shellEnv.HOME = "/"
	shellEnv.PWD = shell.dir()
	shellEnv["?"] = "0"

	while true do
		local line = readLine(formatPrompt(), history)
		local commandLine = line and line:match("^%s*(.-)%s*$") or ""

		if commandLine ~= "" then
			if history[#history] ~= commandLine then
				history[#history + 1] = commandLine
			end

			local parts = tokenize(commandLine)
			local command = table.remove(parts, 1)
			-- expand tokens
			for i = 1, #parts do
				parts[i] = expandToken(parts[i])
			end
			local commands = listCommands()

			local resolved = resolveAlias(command)

			if builtins[resolved] then
				local ok, err = pcall(builtins[resolved], table.unpack(parts))
				-- update last exit
				shellEnv["?"] = ok and "0" or "1"
				if not ok then
					Terminal.print("Error: " .. tostring(err))
				elseif resolved == "exit" then
					return
				end
			elseif commands[resolved] then
				local ok, err = pcall(shell.run, commands[resolved], table.unpack(parts))
				shellEnv["?"] = ok and "0" or "1"
				if not ok then
					Terminal.print("Error: " .. tostring(err))
				end
			else
				Terminal.print("Command not found: " .. tostring(command))
			end
		end
	end
end
local function getCustomApps()
	local appList = {}
	local appDirs = { ROOT .. "/apps", "/apps" }
	for _, dir in ipairs(appDirs) do
		if fs.exists(dir) and fs.isDir(dir) then
			for _, file in ipairs(fs.list(dir)) do
				if file:match("%.[lL][uU][aA]$") or file:match("%.[eE][xX][eE]$") or file:match("%.[dD][lL][lL]$") then
					local filePath = fs.combine(dir, file)
					local appName = file:gsub("%..+$", "")
					table.insert(appList, {
						name = appName,
						run = function()
							Terminal.clear()
							local ok, err = pcall(function()
								shell.run(filePath)
							end)
							if not ok then
								Terminal.print("App crash: " .. tostring(err))
								os.sleep(1.5)
							end
						end,
					})
				end
			end
		end
	end

	-- Add turtle apps if turtle edition
	if settingsLoaded and editionSettings.turtle then
		local turtleAppsDir = ROOT .. "/etc/apt/packages"
		if fs.exists(turtleAppsDir) and fs.isDir(turtleAppsDir) then
			for _, subdir in ipairs(fs.list(turtleAppsDir)) do
				local subpath = fs.combine(turtleAppsDir, subdir)
				if fs.isDir(subpath) then
					for _, file in ipairs(fs.list(subpath)) do
						if file:match("%.[eE][xX][eE]$") then
							local filePath = fs.combine(subpath, file)
							local appName = file:gsub("%..+$", "")
							table.insert(appList, {
								name = appName,
								run = function()
									Terminal.clear()
									local ok, err = pcall(function()
										shell.run(filePath)
									end)
									if not ok then
										Terminal.print("App crash: " .. tostring(err))
										os.sleep(1.5)
									end
								end,
							})
						end
					end
				end
			end
		end
	end

	return appList
end

local function fileManager()
	local currentDir = ROOT
	if currentDir == "/" then
		currentDir = "/"
	end
	while true do
		Terminal.clear()
		Terminal.print("File Manager")
		Terminal.print("Current directory: " .. currentDir)
		Terminal.print("")

		local entries = fs.list(currentDir)
		for index, name in ipairs(entries) do
			local path = fs.combine(currentDir, name)
			local suffix = fs.isDir(path) and "/" or ""
			Terminal.print(string.format("%2d) %s%s", index, name, suffix))
		end
		Terminal.print("")
		Terminal.print("Enter a number to browse, 'back' to go up, or 'exit' to return.")
		local selection = readInput("> ")
		if not selection then
			return
		end
		selection = selection:match("^%s*(.-)%s*$")
		if selection == "exit" then
			return
		elseif selection == "back" then
			if currentDir ~= ROOT and currentDir ~= "/" then
				currentDir = fs.getDir(currentDir)
			end
		else
			local index = tonumber(selection)
			if index and entries[index] then
				local chosen = fs.combine(currentDir, entries[index])
				if fs.isDir(chosen) then
					currentDir = chosen
				else
					local handle = fs.open(chosen, "r")
					if not handle then
						Terminal.print("Unable to open file.")
						os.sleep(1.2)
					else
						Terminal.clear()
						Terminal.print("Viewing: " .. chosen)
						Terminal.print("")
						local count = 0
						while true do
							local line = handle.readLine()
							if not line or count >= 20 then
								break
							end
							Terminal.print(line)
							count = count + 1
						end
						handle.close()
						Terminal.print("")
						Terminal.print("Press Enter to continue.")
						readInput("")
					end
				end
			end
		end
	end
end

local function desktop()
	local editionName = ""
	if settingsLoaded then
		if editionSettings.turtle then
			editionName = " (Turtle Edition)"
		elseif editionSettings.emulator then
			editionName = " (Emulator Edition)"
		elseif editionSettings.softinstall then
			editionName = " (Soft Edition)"
		end
	end

	local options = {
		{ name = "Terminal", run = runShell },
		{ name = "File Manager", run = fileManager },
		{
			name = "About",
			run = function()
				Terminal.clear()
				Terminal.print("CloverOS v1.0.0" .. editionName)
				Terminal.print("Author: CloverOS Team")
				Terminal.print("")
				Terminal.print("Press Enter to return.")
				readInput("")
			end,
		},
		{
			name = "Shutdown",
			run = function()
				Terminal.print("Shutting down...")
				os.sleep(1)
				os.shutdown()
			end,
		},
	}

	-- For soft install, remove File Manager
	if settingsLoaded and editionSettings.softinstall then
		table.remove(options, 2) -- remove File Manager
	end

	while true do
		Terminal.clear()
		Terminal.print("=== CloverOS Desktop" .. editionName .. " ===")
		Terminal.print("")
		local allOptions = {}
		for index, option in ipairs(options) do
			Terminal.print(string.format("%2d) %s", index, option.name))
			table.insert(allOptions, option)
		end
		for _, app in ipairs(getCustomApps()) do
			table.insert(allOptions, app)
		end
		Terminal.print("")
		Terminal.print("Select a number or app name. Type 'shutdown' to power off.")

		local choice = readInput("Choice: ")
		local key = choice and choice:match("^%s*(.-)%s*$") or ""
		if key == "" then
			goto continue
		end
		key = key:lower()
		if key == "shutdown" or key == "poweroff" then
			os.shutdown()
			return
		end

		local index = tonumber(key)
		local activated = false
		if index and allOptions[index] then
			local ok, err = pcall(allOptions[index].run)
			if not ok then
				Terminal.print("Execution error: " .. tostring(err))
				os.sleep(1.5)
			end
			activated = true
		else
			for _, option in ipairs(allOptions) do
				if option.name:lower() == key then
					local ok, err = pcall(option.run)
					if not ok then
						Terminal.print("Execution error: " .. tostring(err))
						os.sleep(1.5)
					end
					activated = true
					break
				end
			end
		end

		if not activated then
			Terminal.print("No matching app found.")
			os.sleep(1.2)
		end

		::continue::
	end
end

simulateLoading()
if not (settingsLoaded and editionSettings.autoLogin) then
	login()
end
desktop()

term.setCursorBlink(true)
