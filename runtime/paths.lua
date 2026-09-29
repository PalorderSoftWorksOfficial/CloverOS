local M = {}

M.__index = M

local function exists(path)
	return type(fs) == "table" and fs.exists(path) or false
end

function M.new(root)
	local self = setmetatable({}, M)
	self.root = root or "/"
	return self
end

-- note: the root path is the plain field self.root; a root() method would
-- be shadowed by that field and is therefore intentionally absent

-- fs.combine drops the leading slash on some hosts (CraftOS-PC and the
-- test shim both return "root/x" for combine("/root", "x")), while
-- CC:Tweaked keeps it. Normalising here means the rest of the OS can rely on
-- a path being absolute instead of each call site guessing.
local function absolute(path)
	path = tostring(path or "")
	path = path:gsub("\\", "/")
	if path ~= "" and path:sub(1, 1) ~= "/" then
		return "/" .. path
	end
	return path
end

M.absolute = absolute

function M:join(...)
	local parts = { ... }
	local path = self.root
	for i = 1, #parts do
		path = fs.combine(path, tostring(parts[i] or ""))
	end
	return path
end

function M:osPath(path)
	path = tostring(path or "")
	if path == "" then
		return absolute(self.root)
	end
	if path:sub(1, 1) == "/" then
		return absolute(fs.combine(self.root, path))
	end
	return absolute(fs.combine(self:cwd(), path))
end

function M:displayPath(path)
	-- both sides are absolute (see M.absolute) and trailing slashes are
	-- trimmed here rather than through fs.combine(path, ""), because how
	-- combine treats an empty child is not defined the same way on every
	-- host, and getting it wrong makes every access check miss its rule
	local function trim(path)
		path = absolute(path)
		while #path > 1 and path:sub(-1) == "/" do
			path = path:sub(1, -2)
		end
		return path
	end
	local base = trim(self.root)
	local full = trim(self:osPath(path))
	if base == "" or base == "/" then
		return "/" .. full
	end
	if full == base then
		return "/"
	end
	if full:sub(1, #base + 1) == base .. "/" then
		return "/" .. full:sub(#base + 2)
	end
	return "/" .. full
end

function M:cwd()
	if type(shell) == "table" and shell.dir then
		local dir = shell.dir()
		if dir:sub(1, #self.root) == self.root then
			return dir
		end
	end
	return self.root
end

function M:setCwd(path)
	local target = self:osPath(path or "")
	if fs.isDir(target) then
		if type(shell) == "table" and shell.setDir then
			shell.setDir(target)
		end
		return true
	end
	return nil, "not a directory: " .. tostring(path)
end

function M:home(user)
	if user and user ~= "" then
		return self:join("home", user)
	end
	local name = type(users) == "table" and users.currentName and users:currentName() or nil
	return self:join("home", name or "")
end

function M:homePath(user)
	local path = self:join("home", user or "")
	if not fs.isDir(path) then
		fs.makeDir(path)
	end
	return path
end

function M:setHomeCwd(user)
	return self:setCwd(self:homePath(user))
end

function M:systemDir(...)
	return self:join(...)
end

function M:protect(relative)
	local target = self:join(relative)
	if self.root == "/" then
		return target
	end
	if target:sub(1, #self.root) ~= self.root then
		return nil, "path escapes CloverOS root"
	end
	return target
end

return M
