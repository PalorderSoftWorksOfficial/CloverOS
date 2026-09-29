-- CloverOS user database, authentication, and privilege model.
-- Passwords are stored as salted SHA-256 digests (runtime/hash.lua).
-- Documented platform limitation: CC:Tweaked provides no key-stretching or
-- secret-storage primitives, so this raises the bar over readable storage
-- but is not a security boundary against filesystem access.
--
-- Privilege model (Ubuntu-style): every user has a primary group named
-- after them; members of the "sudo" group may elevate; the first created
-- user is granted sudo automatically.
local M = {}

M.__index = M

local PASSWORD_STORAGE = "salted sha256 digest (no key stretching on CC:T)"

local function validName(name)
	return type(name) == "string" and name:match("^[a-zA-Z_][a-zA-Z0-9_-]*$") ~= nil and #name <= 24
end

function M.new(paths)
	local self = setmetatable({}, M)
	self.paths = paths
	self.users = {}
	self.current = nil
	self.dbPath = paths:join("etc", "clover", "users.db")
	self.hash = dofile(paths:join("runtime", "hash.lua"))
	return self
end

function M:load()
	self.users = {}
	local h = fs.open(self.dbPath, "r")
	if not h then
		return false
	end
	local data = h.readAll()
	h.close()
	local ok, db = pcall(textutils.unserialize, data)
	if not ok or type(db) ~= "table" or type(db.users) ~= "table" then
		return false
	end
	self.users = db.users
	return true
end

function M:save()
	fs.makeDir(fs.getDir(self.dbPath))
	local h = fs.open(self.dbPath, "w")
	if not h then
		return nil, "cannot write user database"
	end
	h.write(textutils.serialize({ version = 2, users = self.users }))
	h.close()
	return true
end

function M:hasAnyUser()
	return next(self.users) ~= nil
end

function M:hashPassword(password, salt)
	return self.hash.hashPassword(password, salt)
end

function M:makeSalt(name)
	return tostring(os.epoch("utc")) .. "-" .. tostring((#tostring(name) * 31) % 997)
end

-- returns exact booleans: tests and login compare against true/false
function M:authenticate(name, password)
	local u = self.users[name]
	if not u or u.locked then
		return false
	end
	password = tostring(password or "")
	if u.digest then
		return self.hash.verifyPassword(password, u.digest) == true
	end
	-- legacy record from CloverOS 2.0 (salted plaintext digest): accept
	-- once and silently upgrade it to a real digest
	if u.password and u.salt then
		if (tostring(u.salt) .. "#" .. password .. "#" .. tostring(u.salt)) == u.password then
			u.digest = self.hash.hashPassword(password, u.salt)
			u.password = nil
			self:save()
			return true
		end
	end
	return false
end

function M:createUser(name, password, options)
	options = options or {}
	if not validName(name) then
		return nil, "invalid username (letters, digits, _ and - only, max 24 chars)"
	end
	if self.users[name] then
		return nil, "user already exists"
	end
	local uid = options.uid or (1000 + #self:list())
	local salt = self:makeSalt(name)
	local groups = { name, "users" }
	for _, g in ipairs(options.groups or {}) do
		groups[#groups + 1] = g
	end
	if #self:list() == 0 and name ~= "root" then
		-- first user is the administrator (Ubuntu convention)
		groups[#groups + 1] = "sudo"
	end
	self.users[name] = {
		uid = uid,
		gid = uid,
		groups = groups,
		home = self.paths:join("home", name),
		shell = "/bin/sh",
		salt = salt,
		digest = self.hash.hashPassword(password, salt),
		created = os.epoch("utc"),
		locked = false,
	}
	fs.makeDir(self.paths:join("home", name))
	local ok, err = self:save()
	if not ok then
		self.users[name] = nil
		return nil, err
	end
	return true
end

function M:setPassword(name, password)
	local u = self.users[name]
	if not u then
		return nil, "unknown user"
	end
	u.salt = self:makeSalt(name)
	u.digest = self.hash.hashPassword(password, u.salt)
	u.password = nil
	return self:save()
end

function M:removeUser(name)
	if not self.users[name] then
		return nil, "unknown user"
	end
	self.users[name] = nil
	return self:save()
end

function M:lock(name)
	local u = self.users[name]
	if not u then
		return nil, "unknown user"
	end
	u.locked = true
	return self:save()
end

function M:unlock(name)
	local u = self.users[name]
	if not u then
		return nil, "unknown user"
	end
	u.locked = false
	return self:save()
end

function M:list()
	local names = {}
	for name in pairs(self.users) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function M:exists(name)
	return self.users[name] ~= nil
end

function M:currentName()
	return self.current
end

function M:currentUser()
	return self.current and self.users[self.current] or nil
end

function M:login(name)
	if self.users[name] then
		self.current = name
		fs.makeDir(self.paths:homePath(name))
		self.paths:setCwd(self.paths:homePath(name))
		-- the access policy and the external commands in bin/ need to know
		-- who is running without being handed the users module
		_G.CLOVER_USER = name
		return true
	end
	return nil, "unknown user"
end

function M:logout()
	self.current = nil
	_G.CLOVER_USER = nil
	return true
end

function M:groups(name)
	local u = self.users[name]
	if not u then
		return {}
	end
	local out = {}
	for _, g in ipairs(u.groups or {}) do
		out[#out + 1] = g
	end
	return out
end

function M:inGroup(name, group)
	for _, g in ipairs(self:groups(name)) do
		if g == group then
			return true
		end
	end
	return false
end

function M:isSudoer(name)
	return name == "root" or self:inGroup(name, "sudo")
end

function M:addToGroup(name, group)
	local u = self.users[name]
	if not u then
		return nil, "unknown user"
	end
	u.groups = u.groups or { name, "users" }
	if not self:inGroup(name, group) then
		u.groups[#u.groups + 1] = group
	end
	return self:save()
end

function M:removeFromGroup(name, group)
	local u = self.users[name]
	if not u then
		return nil, "unknown user"
	end
	for i, g in ipairs(u.groups or {}) do
		if g == group then
			table.remove(u.groups, i)
			break
		end
	end
	return self:save()
end

function M:storageNote()
	return PASSWORD_STORAGE
end

return M
