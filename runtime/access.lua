-- CloverOS access policy: who may read and write what.
--
-- One module owns the rules so the shell builtins and the external commands
-- in bin/ cannot drift apart. The model is deliberately Ubuntu-shaped rather
-- than complete: CC:Tweaked has no real uid, so a user is whoever is logged
-- in (CLOVER_USER) unless a privileged command has set CLOVER_ELEVATED.
--
-- Three rules:
--   1. the system tree is root-owned, so a normal user cannot replace a
--      command, a library or a config file and become root that way
--   2. the credential and permission databases are root-readable only, so no
--      user can lift another user's password digest or edit the rules
--   3. a user cannot see inside another user's home
--
-- Ownership still has an escape hatch: an explicit chmod record in
-- etc/clover/permissions.cfg overrides the owner of that one path, which is
-- how an admin shares a file deliberately.
local M = {}
M.__index = M

-- root-owned: writable by root alone
local ROOT_OWNED = {
	"^/etc/?",
	"^/boot/?",
	"^/bin/?",
	"^/usr/?",
	"^/libs/?",
	"^/runtime/?",
	"^/apps/?",
	"^/CloverOS_OS%.lua$",
	"^/startup%.lua$",
	"^/install%.lua$",
	"^/netinstall%.lua$",
}

-- root-readable only: credentials and the access rules themselves
local ROOT_ONLY = {
	"^/etc/clover/users%.db$",
	"^/etc/clover/permissions%.cfg$",
	"^/var/lib/clover/sudo%.cache$",
}

local function matches(list, display)
	for _, pattern in ipairs(list) do
		if display:match(pattern) then
			return true
		end
	end
	return false
end

function M.new(deps)
	deps = deps or {}
	return setmetatable({
		paths = deps.paths,
		users = deps.users,
	}, M)
end

-- the account the rules apply to: the elevated one if a privileged command
-- is running, otherwise whoever is logged in
function M:effectiveUser()
	if type(CLOVER_ELEVATED) == "table" and CLOVER_ELEVATED.active then
		return "root"
	end
	if self.users and type(self.users.currentName) == "function" then
		local ok, name = pcall(self.users.currentName, self.users)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	if type(CLOVER_USER) == "string" and CLOVER_USER ~= "" then
		return CLOVER_USER
	end
	return "user"
end

function M:isRoot()
	return self:effectiveUser() == "root"
end

function M:protectedPath(display)
	return matches(ROOT_OWNED, display)
end

function M:isRootOnly(display)
	return matches(ROOT_ONLY, display)
end

-- which user owns this path, either because it is their home or because an
-- explicit chmod/chown record says so
function M:ownerOf(display)
	local record = self:records()[display]
	if record and type(record.owner) == "string" and record.owner ~= "" then
		return record.owner
	end
	local home = display:match("^/home/([^/]+)")
	if home then
		return home
	end
	if self:protectedPath(display) then
		return "root"
	end
	return nil
end

function M:records()
	if self._records then
		return self._records
	end
	self._records = {}
	if not self.paths or type(fs) ~= "table" then
		return self._records
	end
	local handle = fs.open(self.paths:join("etc", "clover", "permissions.cfg"), "r")
	if not handle then
		return self._records
	end
	local data = handle.readAll()
	handle.close()
	if type(data) ~= "string" then
		return self._records
	end
	local ok, db = pcall(textutils.unserialize, data)
	if ok and type(db) == "table" then
		self._records = db
	end
	return self._records
end

function M:reload()
	self._records = nil
	return self:records()
end

-- the owner of another user's home, or nil when the path is not one
function M:foreignHome(display)
	if self:isRoot() then
		return nil
	end
	local owner = display:match("^/home/([^/]+)")
	if owner and owner ~= self:effectiveUser() then
		return owner
	end
	return nil
end

-- chmod records a three digit octal mode: owner, group, other. Returns those
-- three digits, padding anything shorter so a 2 digit "64" cannot silently
-- shift every permission by one position.
local function modeTriples(mode)
	mode = tostring(mode or "")
	mode = mode:gsub("[^0-7]", "")
	while #mode < 3 do
		mode = "0" .. mode
	end
	return mode:sub(1, 1), mode:sub(2, 2), mode:sub(3, 3)
end

-- A mode digit is octal: 4 means r, 2 means w, 1 means x. Testing the digit
-- for the letter "r" would deny every file the admin just shared.
local function allows(digit, what)
	local value = tonumber(digit) or 0
	if what == "r" then
		return value >= 4
	elseif what == "w" then
		return value >= 2
	end
	return value % 2 == 1
end

-- pick the digit that applies to the user asking
function M:bitsFor(record, user, what)
	local ownerBits, groupBits, otherBits = modeTriples(record.mode)
	if record.owner == user then
		return allows(ownerBits, what)
	end
	if record.group and record.group == (self:groupOf(record.owner) or "") then
		return allows(groupBits, what)
	end
	return allows(otherBits, what)
end

-- the primary group of a user, used to pick between the group and other bits
function M:groupOf(name)
	if self.users and type(self.users.groups) == "function" then
		local ok, groups = pcall(self.users.groups, self.users, name)
		if ok and type(groups) == "table" and type(groups[1]) == "string" then
			return groups[1]
		end
	end
	return nil
end

function M:canRead(display)
	display = tostring(display or "")
	local user = self:effectiveUser()
	if user == "root" then
		return true
	end
	-- an explicit chmod is the documented way to share or hide one file
	local record = self:records()[display]
	if record and type(record.mode) == "string" then
		return self:bitsFor(record, user, "r")
	end
	if self:isRootOnly(display) then
		return false
	end
	return self:foreignHome(display) == nil
end

function M:canWrite(display)
	display = tostring(display or "")
	local user = self:effectiveUser()
	if user == "root" then
		return true
	end
	local record = self:records()[display]
	if record and type(record.mode) == "string" then
		return self:bitsFor(record, user, "w")
	end
	if self:protectedPath(display) then
		return false
	end
	return self:foreignHome(display) == nil
end

-- Path helpers so callers do not have to remember the root/cwd dance.
-- displayPath already resolves through osPath internally, so the raw
-- user-supplied path is what it wants.
function M:displayOf(path)
	return self.paths:displayPath(path)
end

function M:canReadPath(path)
	return self:canRead(self:displayOf(path))
end

function M:canWritePath(path)
	return self:canWrite(self:displayOf(path))
end

-- Resolve a user-supplied path and open it, honouring the policy. Commands in
-- bin/ use this so they neither bypass the access rules nor forget that a
-- CloverOS path like /home/x is really <root>/home/x on disk.
-- Returns handle, err.
function M:openForRead(path)
	if not self:canReadPath(path) then
		return nil, "permission denied: " .. self:displayOf(path)
	end
	return fs.open(self.paths:osPath(path), "r")
end

-- Attach to the access policy from a program outside the session. Returns nil
-- when the CloverOS root cannot be found, so callers can fall back to plain fs.
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
		root = program and fs.getDir(program) or nil
	end
	if not root then
		return nil
	end
	local pathsOk, pathsModule = pcall(dofile, fs.combine(root, "runtime/paths.lua"))
	if not pathsOk or type(pathsModule) ~= "table" or type(pathsModule.new) ~= "function" then
		return nil
	end
	local selfOk, self = pcall(dofile, fs.combine(root, "runtime/access.lua"))
	if not selfOk or type(self) ~= "table" or type(self.new) ~= "function" then
		return nil
	end
	return self.new({ paths = pathsModule.new(root) })
end

return M
