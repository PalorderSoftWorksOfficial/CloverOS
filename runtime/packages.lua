local M = {}

function M.new(kernel, root, users, ui)
	local self = {
		kernel = kernel,
		root = root,
		users = users,
		ui = ui,
	}

	local apt = root .. "/etc/apt/packages"
	local installedFile = root .. "/etc/apt/installed"

	local function ensure(path)
		if not fs.exists(path) then
			fs.makeDir(path)
		end
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

	local function writeLines(path, lines)
		local h = fs.open(path, "w")
		if not h then
			return nil, "cannot write file"
		end
		for _, line in ipairs(lines) do
			h.write(tostring(line) .. "\n")
		end
		h.close()
		return true
	end

	local function readMeta(pkg)
		local path = fs.combine(apt, pkg)
		local meta = fs.combine(path, "package.json")
		if not fs.exists(meta) then
			return nil
		end
		local data = readAll(meta)
		if not data then
			return nil
		end
		if textutils and textutils.unserializeJSON then
			local ok, out = pcall(textutils.unserializeJSON, data)
			if ok and type(out) == "table" then
				return out
			end
		end
		return nil
	end

	function self:list()
		local out = {}
		if not fs.exists(apt) or not fs.isDir(apt) then
			return out
		end
		for _, name in ipairs(fs.list(apt)) do
			if fs.isDir(fs.combine(apt, name)) then
				out[#out + 1] = name
			end
		end
		table.sort(out)
		return out
	end

	function self:installed()
		local out = {}
		local data = readAll(installedFile)
		if not data then
			return out
		end
		for line in tostring(data):gmatch("[^
]+") do
			line = line:gsub("^%s+", ""):gsub("%s+$", "")
			if line ~= "" then
				out[#out + 1] = line
			end
		end
		return out
	end

	function self:isInstalled(name)
		for _, pkg in ipairs(self:installed()) do
			if pkg == name then
				return true
			end
		end
		return false
	end

	function self:info(name)
		return readMeta(name)
	end

	function self:search(term)
		term = tostring(term or ""):lower()
		local out = {}
		for _, name in ipairs(self:list()) do
			if term == "" or name:lower():find(term, 1, true) then
				out[#out + 1] = name
			end
		end
		return out
	end

	function self:install(name)
		name = tostring(name or "")
		if name == "" then
			return nil, "invalid package name"
		end
		ensure(root .. "/etc")
		ensure(root .. "/etc/apt")
		ensure(apt)
		local meta = readMeta(name)
		if not meta or type(meta.files) ~= "table" then
			return nil, "package not found"
		end
		ensure(root .. "/usr")
		ensure(root .. "/usr/bin")
		for _, file in ipairs(meta.files) do
			local src = fs.combine(fs.combine(apt, name), file)
			local dst = fs.combine(root .. "/usr/bin", file)
			if not fs.exists(src) then
				return nil, "missing package file: " .. file
			end
			local parent = fs.getDir(dst)
			if parent and parent ~= "" and not fs.exists(parent) then
				fs.makeDir(parent)
			end
			fs.copy(src, dst)
		end
		local installed = self:installed()
		for _, pkg in ipairs(installed) do
			if pkg == name then
				return true
			end
		end
		installed[#installed + 1] = name
		writeLines(installedFile, installed)
		return true
	end

	function self:remove(name)
		name = tostring(name or "")
		if name == "" then
			return nil, "invalid package name"
		end
		local meta = readMeta(name)
		if not meta or type(meta.files) ~= "table" then
			return nil, "package not found"
		end
		for _, file in ipairs(meta.files) do
			local dst = fs.combine(root .. "/usr/bin", file)
			if fs.exists(dst) then
				fs.delete(dst)
			end
		end
		local installed = {}
		for _, pkg in ipairs(self:installed()) do
			if pkg ~= name then
				installed[#installed + 1] = pkg
			end
		end
		writeLines(installedFile, installed)
		return true
	end

	return self
end

return M