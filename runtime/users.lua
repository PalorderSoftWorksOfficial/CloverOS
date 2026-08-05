local M = {}

function M.new(root)
	local self = {
		root = root,
		users = {},
		groups = {},
		current = nil,
	}

	local passwd = root .. "/etc/passwd"
	local group = root .. "/etc/group"

	local function ensure(path)
		if not fs.exists(path) then
			fs.makeDir(path)
		end
	end

	function self:ensureBase()
		local dirs = {
			"/etc",
			"/etc/man",
			"/etc/apt",
			"/etc/apt/packages",
			"/usr",
			"/usr/bin",
			"/usr/local",
			"/usr/local/bin",
			"/bin",
			"/home",
			"/var",
			"/tmp",
		}

		for _, d in ipairs(dirs) do
			ensure(self.root .. d)
		end

		if not fs.exists(passwd) then
			local h = fs.open(passwd, "w")
			if h then
				h.write("root:x:0:0::/root:/bin/sh\n")
				h.close()
			end
		end

		if not fs.exists(group) then
			local h = fs.open(group, "w")
			if h then
				h.write("root:x:0:root\nusers:x:1000:\n")
				h.close()
			end
		end
	end

	function self:load()
		self:ensureBase()
		self.users = {}
		self.groups = {
			root = { gid = 0, members = { "root" } },
			users = { gid = 1000, members = {} },
		}

		local h = fs.open(passwd, "r")
		if h then
			while true do
				local line = h.readLine()
				if not line then
					break
				end
				local name, pass, uid, gid, _, home, shell = line:match("([^:]+):([^:]+):([^:]+):([^:]+):([^:]*):([^:]+):([^:]+)")
				if name then
					self.users[name] = {
						uid = tonumber(uid) or 0,
						gid = tonumber(gid) or 0,
						home = home,
						shell = shell,
						password = pass,
					}
				end
			end
			h.close()
		end

		h = fs.open(group, "r")
		if h then
			while true do
				local line = h.readLine()
				if not line then
					break
				end
				local name, _, gid, members = line:match("([^:]+):([^:]+):([^:]+):(.*)")
				if name then
					local out = { gid = tonumber(gid) or 0, members = {} }
					if members and members ~= "" then
						for member in members:gmatch("[^,]+") do
							out.members[#out.members + 1] = member
						end
					end
					self.groups[name] = out
				end
			end
			h.close()
		end

		if not self.groups.users then
			self.groups.users = { gid = 1000, members = {} }
		end
	end

	function self:save()
		self:ensureBase()

		local h = fs.open(passwd, "w")
		if h then
			local names = {}
			for name in pairs(self.users) do
				names[#names + 1] = name
			end
			table.sort(names)
			for _, name in ipairs(names) do
				local info = self.users[name]
				h.write(name .. ":" .. tostring(info.password or "") .. ":" .. tostring(info.uid or 0) .. ":" .. tostring(info.gid or 0) .. "::" .. tostring(info.home or "/home/" .. name) .. ":" .. tostring(info.shell or "/bin/sh") .. "\n")
			end
			h.close()
		end

		h = fs.open(group, "w")
		if h then
			local names = {}
			for name in pairs(self.groups) do
				names[#names + 1] = name
			end
			table.sort(names)
			for _, name in ipairs(names) do
				local info = self.groups[name]
				h.write(name .. ":x:" .. tostring(info.gid or 0) .. ":" .. table.concat(info.members or {}, ",") .. "\n")
			end
			h.close()
		end
	end

	function self:firstBoot()
		local count = 0
		for name, info in pairs(self.users) do
			count = count + 1
			if name ~= "root" or type(info) ~= "table" or info.uid ~= 0 or info.gid ~= 0 or info.password ~= "x" then
				return false
			end
		end
		return count == 1
	end

	function self:currentUser()
		return self.current and self.users[self.current] or nil
	end

	function self:currentName()
		return self.current
	end

	function self:setCurrent(name)
		if self.users[name] then
			self.current = name
			return true
		end
		return nil, "unknown user"
	end

	function self:authenticate(name, password)
		local u = self.users[name]
		return u and u.password == tostring(password or "")
	end

	function self:addUser(name, password)
		name = tostring(name or "")
		if name == "" then
			return nil, "invalid username"
		end
		if self.users[name] then
			return nil, "user exists"
		end
		self.users[name] = {
			uid = 1000,
			gid = 1000,
			home = "/home/" .. name,
			shell = "/bin/sh",
			password = tostring(password or ""),
		}
		self.groups.users = self.groups.users or { gid = 1000, members = {} }
		self.groups.users.members[#self.groups.users.members + 1] = name
		ensure(self.root .. "/home/" .. name)
		self:save()
		return true
	end

	function self:setPassword(name, password)
		local u = self.users[name]
		if not u then
			return nil, "unknown user"
		end
		u.password = tostring(password or "")
		self:save()
		return true
	end

	function self:login(ui)
		self:load()
		if self:firstBoot() then
			ui:clear()
			ui:center(2, "CloverOS Setup", colors.white, colors.blue)
			ui:println("")
			ui:println("Leave both fields blank for a default user.")
			local name = kernel.input.line("New username: ")
			local pass = kernel.input.line("New password: ", true)
			if name == nil or name == "" then
				name = "user"
			end
			if pass == nil then
				pass = ""
			end
			self.users = {}
			self.groups = {
				root = { gid = 0, members = { "root" } },
				users = { gid = 1000, members = { name } },
			}
			self.users[name] = {
				uid = 1000,
				gid = 1000,
				home = "/home/" .. name,
				shell = "/bin/sh",
				password = pass,
			}
			ensure(self.root .. "/home/" .. name)
			self:save()
			self.current = name
			ui:println("Account created: " .. name)
			kernel.sleep(0.8)
			return name
		end

		while true do
			ui:clear()
			ui:center(2, "CloverOS Login", colors.white, colors.blue)
			ui:println("")
			local name = kernel.input.line("Username: ")
			local pass = kernel.input.line("Password: ", true)
			if self:authenticate(name, pass) then
				self.current = name
				ensure(self.root .. "/home/" .. name)
				ui:println("Login successful.")
				kernel.sleep(0.6)
				return name
			end
			ui:println("Invalid credentials.")
			kernel.sleep(0.8)
		end
	end

	return self
end

return M