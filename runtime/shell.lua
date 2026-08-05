local M = {}

function M.new(kernel, root, users, ui, packages, rootmod)
	local self = {
		kernel = kernel,
		root = root,
		users = users,
		ui = ui,
		packages = packages,
		rootmod = rootmod,
		running = true,
		history = {},
		aliases = {},
	}

	local function trim(s)
		return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	end

	local function tokenize(line)
		local out = {}
		local word = {}
		local quote = nil
		local escape = false

		for i = 1, #line do
			local c = line:sub(i, i)
			if escape then
				word[#word + 1] = c
				escape = false
			elseif c == "\\" and quote ~= "'" then
				escape = true
			elseif c == '"' or c == "'" then
				if quote == c then
					quote = nil
				elseif not quote then
					quote = c
				else
					word[#word + 1] = c
				end
			elseif c:match("%s") and not quote then
				if #word > 0 then
					out[#out + 1] = table.concat(word)
					word = {}
				end
			else
				word[#word + 1] = c
			end
		end

		if #word > 0 then
			out[#out + 1] = table.concat(word)
		end

		return out
	end

	local function resolvePath(p)
		p = tostring(p or "")
		if p == "" then
			return kernel.process.dir() or root
		end
		if fs.exists(p) then
			return p
		end
		local cwd = kernel.process.dir() or root
		local rel = fs.combine(cwd, p)
		if fs.exists(rel) then
			return rel
		end
		local abs = fs.combine(root, p)
		if fs.exists(abs) then
			return abs
		end
		return rel
	end

	local function listPrograms()
		local dirs = {
			"/bin",
			"/usr/bin",
			root .. "/bin",
			root .. "/usr/bin",
		}
		local out = {}
		local seen = {}
		for _, dir in ipairs(dirs) do
			if fs.exists(dir) and fs.isDir(dir) then
				for _, file in ipairs(fs.list(dir)) do
					local full = fs.combine(dir, file)
					if fs.exists(full) and not fs.isDir(full) then
						local ok = file:match("%.[lL][uU][aA]$") or file:match("%.[eE][xX][eE]$") or not file:match("%.")
						if ok then
							local name = file:gsub("%..+$", "")
							if not seen[name] then
								seen[name] = true
								out[name] = full
							end
						end
					end
				end
			end
		end
		return out
	end

	local function readAll(path)
		local h = fs.open(path, "r")
		if not h then
			return nil
		end
		local d = h.readAll()
		h.close()
		return d
	end

	local function printLines(data)
		for line in tostring(data or ""):gmatch("([^
]*)\n?") do
			if line == "" and #tostring(data or "") > 0 and tostring(data or ""):sub(-1) == "\n" then
				break
			end
			ui:println(line)
		end
	end

	local function doLs(path)
		path = path and resolvePath(path) or (kernel.process.dir() or root)
		if not fs.exists(path) then
			ui:println("No such path")
			return
		end
		local items = fs.list(path)
		table.sort(items)
		for _, item in ipairs(items) do
			ui:println(item)
		end
	end

	local function doCat(path)
		if not path then
			ui:println("Usage: cat <file>")
			return
		end
		local data = readAll(resolvePath(path))
		if not data then
			ui:println("Unable to open file")
			return
		end
		printLines(data)
	end

	local function doRm(path)
		if not path then
			ui:println("Usage: rm <path>")
			return
		end
		local target = resolvePath(path)
		if fs.exists(target) then
			fs.delete(target)
		end
	end

	local builtins = {}

	builtins.help = function()
		ui:println("help exit shutdown reboot clear pwd cd ls cat echo history whoami hostname date time touch mkdir rm cp mv useradd passwd su run apt alias unalias")
		local names = {}
		for name in pairs(listPrograms()) do
			names[#names + 1] = name
		end
		table.sort(names)
		for _, name in ipairs(names) do
			ui:println(name)
		end
	end

	builtins.exit = function()
		self.running = false
	end

	builtins.shutdown = function()
		kernel.shutdown()
	end

	builtins.reboot = function()
		kernel.reboot()
	end

	builtins.clear = function()
		ui:clear()
	end

	builtins.pwd = function()
		ui:println(kernel.process.dir() or root)
	end

	builtins.cd = function(path)
		if not path or trim(path) == "" then
			kernel.process.setDir(root)
			return
		end
		local target = resolvePath(path)
		if fs.exists(target) and fs.isDir(target) then
			kernel.process.setDir(target)
		else
			ui:println("Not a directory")
		end
	end

	builtins.ls = function(path)
		doLs(path)
	end

	builtins.cat = function(path)
		doCat(path)
	end

	builtins.echo = function(...)
		local parts = { ... }
		for i = 1, #parts do
			parts[i] = tostring(parts[i])
		end
		ui:println(table.concat(parts, " "))
	end

	builtins.history = function()
		for i, line in ipairs(self.history) do
			ui:println(string.format("%4d  %s", i, line))
		end
	end

	builtins.whoami = function()
		ui:println(users:currentName() or "unknown")
	end

	builtins.hostname = function()
		ui:println(ui:hostname())
	end

	builtins.date = function()
		ui:println(os.date("%c"))
	end

	builtins.time = function()
		ui:println(os.time())
	end

	builtins.touch = function(path)
		if not path then
			ui:println("Usage: touch <file>")
			return
		end
		local target = resolvePath(path)
		local parent = fs.getDir(target)
		if parent and parent ~= "" and not fs.exists(parent) then
			fs.makeDir(parent)
		end
		if not fs.exists(target) then
			local h = fs.open(target, "w")
			if h then
				h.write("")
				h.close()
			end
		end
	end

	builtins.mkdir = function(path)
		if not path then
			ui:println("Usage: mkdir <dir>")
			return
		end
		local target = resolvePath(path)
		if not fs.exists(target) then
			fs.makeDir(target)
		end
	end

	builtins.rm = function(path)
		doRm(path)
	end

	builtins.cp = function(src, dst)
		if not src or not dst then
			ui:println("Usage: cp <src> <dst>")
			return
		end
		local a = resolvePath(src)
		local b = resolvePath(dst)
		if fs.exists(a) then
			fs.copy(a, b)
		end
	end

	builtins.mv = function(src, dst)
		if not src or not dst then
			ui:println("Usage: mv <src> <dst>")
			return
		end
		local a = resolvePath(src)
		local b = resolvePath(dst)
		if fs.exists(a) then
			fs.move(a, b)
		end
	end

	builtins.useradd = function(name)
		if not name or name == "" then
			ui:println("Usage: useradd <name>")
			return
		end
		local pass = kernel.input.line("Password: ", true)
		local ok, err = users:addUser(name, pass)
		if not ok then
			ui:println(err)
		end
	end

	builtins.passwd = function(name)
		name = name and name ~= "" and name or users:currentName()
		if not name then
			ui:println("No active user")
			return
		end
		local pass = kernel.input.line("New password: ", true)
		local ok, err = users:setPassword(name, pass)
		if not ok then
			ui:println(err)
		end
	end

	builtins.su = function(name)
		name = name and name ~= "" and name or "root"
		local pass = kernel.input.line("Password: ", true)
		if users:authenticate(name, pass) then
			users:setCurrent(name)
			ui:println("Switched to " .. name)
		else
			ui:println("Authentication failed")
		end
	end

	builtins.run = function(...)
		local args = { ... }
		if #args == 0 then
			ui:println("Usage: run <command>")
			return
		end
		local name = table.remove(args, 1)
		local path = listPrograms()[self.aliases[name] or name]
		if not path then
			ui:println("No such command")
			return
		end
		local ok, err = pcall(kernel.process.run, path, table.unpack(args))
		if not ok then
			ui:println(err)
		end
	end

	builtins.alias = function(name, value)
		if not name then
			for k, v in pairs(self.aliases) do
				ui:println(k .. "=" .. v)
			end
			return
		end
		self.aliases[name] = value or ""
	end

	builtins.unalias = function(name)
		if name then
			self.aliases[name] = nil
		end
	end

	builtins.apt = function(action, ...)
		action = tostring(action or "")
		local args = { ... }
		if action == "list" then
			for _, name in ipairs(packages:list()) do
				ui:println(name)
			end
		elseif action == "installed" then
			for _, name in ipairs(packages:installed()) do
				ui:println(name)
			end
		elseif action == "search" then
			for _, name in ipairs(packages:search(args[1] or "")) do
				ui:println(name)
			end
		elseif action == "info" then
			local meta = packages:info(args[1])
			if not meta then
				ui:println("Package not found")
				return
			end
			for k, v in pairs(meta) do
				ui:println(k .. ": " .. textutils.serialize(v))
			end
		elseif action == "install" then
			local ok, err = packages:install(args[1])
			if not ok then
				ui:println(err)
			end
		elseif action == "remove" then
			local ok, err = packages:remove(args[1])
			if not ok then
				ui:println(err)
			end
		else
			ui:println("Usage: apt <list|installed|search|info|install|remove>")
		end
	end

	function self:complete(index, current)
		if index ~= 1 then
			return nil
		end
		local out = {}
		local seen = {}
		for name in pairs(builtins) do
			if name:sub(1, #current) == current and not seen[name] then
				seen[name] = true
				out[#out + 1] = name:sub(#current + 1)
			end
		end
		for name in pairs(listPrograms()) do
			if name:sub(1, #current) == current and not seen[name] then
				seen[name] = true
				out[#out + 1] = name:sub(#current + 1)
			end
		end
		table.sort(out)
		return out
	end

	function self:execute(line)
		line = trim(line)
		if line == "" then
			return
		end
		self.history[#self.history + 1] = line
		local args = tokenize(line)
		local cmd = args[1]
		table.remove(args, 1)
		cmd = self.aliases[cmd] or cmd
		if builtins[cmd] then
			return builtins[cmd](table.unpack(args))
		end
		local path = listPrograms()[cmd]
		if not path then
			ui:println("No such command: " .. tostring(cmd))
			return
		end
		local ok, err = pcall(kernel.process.run, path, table.unpack(args))
		if not ok then
			ui:println(err)
		end
	end

	function self:run()
		users:login(ui)
		kernel.process.setDir(root)
		while self.running do
			local user = users:currentName() or "user"
			local cwd = kernel.process.dir() or root
			local prompt = string.format("%s@%s:%s$ ", user, ui:hostname(), cwd)
			local line = kernel.input.readline(prompt, nil, function(index, current, previous)
				return self:complete(index, current, previous)
			end)
			if line ~= nil then
				local ok, err = pcall(function()
					self:execute(line)
				end)
				if not ok then
					ui:println(err)
				end
			end
		end
	end

	return self
end

return M