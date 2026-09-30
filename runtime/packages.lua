-- CloverOS package system (apt-style).
--
-- Catalog: etc/packages/<name>/package.lua metadata plus payload files.
-- Sources:  etc/apt/sources.list lists local catalog dirs and network
--           repositories; `apt update` merges their indexes.
-- State:    var/lib/packages/installed.cfg records version, payload
--           checksums (SHA-256), and auto-installed dependency flags.
--
-- Installation copies package files into place and is rolled back
-- automatically if any step fails. Dependencies (meta.depends) are
-- resolved and installed first.
local M = {}

M.__index = M

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

-- Compose a URL under a repository root. A source is written by a human
-- ("https://host/repo/") so it usually already ends in a slash, and naively
-- gluing "/index.lua" onto that asks the server for a path with "//" in it.
-- ---------- rednet transport ----------
-- A CloverOS apt server (bin/aptserver.lua) serves the same index.lua and
-- package files a GitHub source does, over rednet. A rednet source is a
-- table { kind = "rednet", host = <computer id> }; fetching is one
-- request/reply exchange per file with a bounded wait, and integrity is
-- unchanged: sha256 digests published in the index are still enforced by
-- installRemote before anything is written.
M.REDNET_TIMEOUT = 8
M.REDNET_PROTOCOL = "clover/apt"

-- One request/reply exchange. Returns the payload table, or nil plus a
-- reason. Kept out of installRemote so the wait loop is testable.
function M:rednetFetch(host, request)
	if type(rednet) ~= "table" or type(rednet.send) ~= "function"
		or type(rednet.receive) ~= "function" then
		return nil, "rednet is not available"
	end
	host = tonumber(host)
	if not host then
		return nil, "rednet source needs a numeric host id"
	end
	rednet.send(host, request, M.REDNET_PROTOCOL)
	local deadline = os.clock() + M.REDNET_TIMEOUT
	while os.clock() < deadline do
		local senderId, message, protocol = rednet.receive(M.REDNET_PROTOCOL, deadline - os.clock())
		if senderId == host then
			local ok, payload = pcall(textutils.unserialize, tostring(message or ""))
			if ok and type(payload) == "table" then
				if payload.kind == "file" then
					return payload
				elseif payload.kind == "missing" then
					return nil, "server does not have " .. tostring(request.name) .. "/" .. tostring(request.file)
				elseif payload.kind == "error" then
					return nil, "server error: " .. tostring(payload.why or "?")
				end
			end
		end
	end
	return nil, "no answer from computer " .. tostring(host)
end

local function repoUrl(base, ...)
	-- parentheses matter: gsub also returns a count, and inside a table
	-- constructor that count would become a path segment
	local out = { (tostring(base or ""):gsub("/+$", "")) }
	for _, part in ipairs({ ... }) do
		out[#out + 1] = (tostring(part):gsub("^/+", ""))
	end
	return table.concat(out, "/")
end

function M.new(paths)
	local self = setmetatable({}, M)
	self.paths = paths
	self.catalogDir = paths:join("etc", "packages")
	self.stateFile = paths:join("var", "lib", "packages", "installed.cfg")
	self.indexFile = paths:join("var", "lib", "apt", "index.cfg")
	self.sourcesFile = paths:join("etc", "apt", "sources.list")
	self.hash = dofile(paths:join("runtime", "hash.lua"))
	return self
end

-- ---------- catalog & index ----------

function M:list()
	local seen, out = {}, {}
	for _, name in ipairs(self:catalogNames()) do
		seen[name] = true
		out[#out + 1] = name
	end
	for _, name in ipairs(self:indexNames()) do
		if not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return out
end

function M:catalogNames()
	local out = {}
	if fs.isDir(self.catalogDir) then
		for _, name in ipairs(fs.list(self.catalogDir)) do
			if fs.isDir(fs.combine(self.catalogDir, name)) then
				out[#out + 1] = name
			end
		end
	end
	table.sort(out)
	return out
end

function M:readMeta(name)
	local path = fs.combine(self.catalogDir, tostring(name))
	if type(name) ~= "string" or name == "" or name:find("%.") or name:find("/") or not fs.isDir(path) then
		return nil, "unknown package"
	end
	local metaPath = fs.combine(path, "package.lua")
	if not fs.exists(metaPath) then
		return nil, "package metadata missing for " .. tostring(name)
	end
	local ok, meta = pcall(dofile, metaPath)
	if not ok or type(meta) ~= "table" then
		return nil, "invalid metadata for " .. tostring(name)
	end
	meta.name = meta.name or name
	meta.version = tostring(meta.version or "0")
	meta.description = tostring(meta.description or "")
	meta.files = meta.files or {}
	meta.depends = meta.depends or {}
	return meta
end

function M:info(name)
	local meta, err = self:readMeta(name)
	if meta then
		meta.source = "local"
		return meta
	end
	local remote = self:indexEntry(name)
	if remote then
		remote.source = remote.source or "net"
		return remote
	end
	return nil, err
end

function M:search(term)
	term = tostring(term or ""):lower()
	local out = {}
	for _, name in ipairs(self:list()) do
		if term == "" then
			out[#out + 1] = name
		else
			local meta = self:info(name)
			local haystack = name .. " " .. (meta and meta.description or "")
			if haystack:lower():find(term, 1, true) then
				out[#out + 1] = name
			end
		end
	end
	return out
end

function M:indexNames()
	local index = self:loadIndex()
	local out = {}
	for name in pairs(index) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

function M:indexEntry(name)
	return self:loadIndex()[tostring(name)]
end

function M:loadIndex()
	local data = readAll(self.indexFile)
	if not data then
		return {}
	end
	local ok, index = pcall(textutils.unserialize, data)
	if ok and type(index) == "table" then
		return index
	end
	return {}
end

-- ---------- sources & update ----------

-- sources.list lines: "local <fs dir of package folders>" or
-- "net <base url of a repository exposing index.lua and package files>"
function M:sources()
	local out = {}
	local data = readAll(self.sourcesFile)
	if data then
		for line in data:gmatch("[^\n]+") do
			local kind, loc = line:match("^%s*(%w+)%s+(%S+)")
			if kind and loc then
				out[#out + 1] = { kind = kind, location = loc }
			end
		end
	end
	if #out == 0 then
		out[1] = { kind = "local", location = self.catalogDir }
	end
	return out
end

-- Replace etc/apt/sources.list. Blank lines and '#' comments are dropped on
-- write so the file stays the single place a repository is configured.
function M:writeSources(list)
	local lines = {
		"# CloverOS package sources",
		"# One repository per line: <kind> <location>",
		"#   local <dir>   a catalog directory of <name>/package.lua",
		"#   net   <url>   a repository serving index.lua and <name>/<file>",
	}
	local written = {}
	local function emit(kind, location)
		location = tostring(location or "")
		if kind == "" or location == "" then
			return
		end
		local key = kind .. " " .. location
		if written[key] then
			return
		end
		written[key] = true
		lines[#lines + 1] = key
	end
	for _, source in ipairs(list or {}) do
		emit(tostring(source.kind or ""):lower(), source.location)
	end
	-- the bundled catalog is always available, but appending it blindly would
	-- duplicate the line the installation already ships
	emit("local", self.catalogDir)
	return writeAll(self.sourcesFile, table.concat(lines, "\n") .. "\n")
end

function M:addSource(kind, location)
	kind = tostring(kind or ""):lower()
	location = tostring(location or "")
	if kind ~= "local" and kind ~= "net" then
		return nil, "source kind must be 'local' or 'net'"
	end
	if location == "" then
		return nil, "source needs a location"
	end
	if kind == "net" and not location:match("^https?://") then
		return nil, "a net source must start with http:// or https://"
	end
	local list = {}
	local data = readAll(self.sourcesFile)
	if data then
		for line in data:gmatch("[^\n]+") do
			local existingKind, existingLoc = line:match("^%s*(%w+)%s+(%S+)")
			if existingKind and existingLoc then
				list[#list + 1] = { kind = existingKind, location = existingLoc }
			end
		end
	end
	for _, source in ipairs(list) do
		if source.location == location then
			return nil, "already a source: " .. location
		end
	end
	list[#list + 1] = { kind = kind, location = location }
	self:writeSources(list)
	return true
end

function M:removeSource(location)
	location = tostring(location or "")
	local list, found = {}, false
	local data = readAll(self.sourcesFile)
	if data then
		for line in data:gmatch("[^\n]+") do
			local kind, loc = line:match("^%s*(%w+)%s+(%S+)")
			if kind and loc then
				if loc == location then
					found = true
				else
					list[#list + 1] = { kind = kind, location = loc }
				end
			end
		end
	end
	if not found then
		return nil, "no such source: " .. location
	end
	self:writeSources(list)
	return true
end

function M:update()
	local index = {}
	local counts = { local_sources = 0, net_sources = 0, packages = 0 }
	for _, source in ipairs(self:sources()) do
		if source.kind == "local" and fs.isDir(source.location) then
			counts.local_sources = counts.local_sources + 1
			for _, name in ipairs(fs.list(source.location)) do
				local metaPath = fs.combine(fs.combine(source.location, name), "package.lua")
				if fs.isDir(fs.combine(source.location, name)) and fs.exists(metaPath) then
					local ok, meta = pcall(dofile, metaPath)
					if ok and type(meta) == "table" then
						meta.name = meta.name or name
						meta.version = tostring(meta.version or "0")
						meta.description = tostring(meta.description or "")
						meta.files = meta.files or {}
						meta.depends = meta.depends or {}
						meta.source = "local"
						meta.origin = source.location
						if not index[name] or self:compareVersions(meta.version, index[name].version) > 0 then
							index[name] = meta
						end
						counts.packages = counts.packages + 1
					end
				end
			end
		elseif source.kind == "rednet" then
			counts.rednet_sources = (counts.rednet_sources or 0) + 1
			local reply, err = self:rednetFetch(source.host, { kind = "index" })
			if reply then
				local index_data = reply.data
				if type(index_data) == "table" then
					for name, meta in pairs(index_data) do
						if type(meta) == "table" then
							meta.name = meta.name or name
							meta.version = tostring(meta.version or "0")
							meta.files = meta.files or {}
							meta.depends = meta.depends or {}
							meta.source = "rednet"
							meta.origin = source.host
							if not index[name] or self:compareVersions(meta.version, index[name].version) > 0 then
								index[name] = meta
							end
							counts.packages = counts.packages + 1
						end
					end
				end
			else
				counts.errors = counts.errors or {}
				counts.errors[#counts.errors + 1] = "computer " .. tostring(source.host) .. ": " .. tostring(err)
			end
		elseif source.kind == "net" then
			counts.net_sources = counts.net_sources + 1
			local body, err = self:fetch(repoUrl(source.location, "index.lua"))
			if body then
				local ok, remote = pcall(textutils.unserialize, body)
				if ok and type(remote) == "table" then
					for name, meta in pairs(remote) do
						if type(meta) == "table" then
							meta.name = meta.name or name
							meta.version = tostring(meta.version or "0")
							meta.files = meta.files or {}
							meta.depends = meta.depends or {}
							meta.source = "net"
							meta.origin = source.location
							if not index[name] or self:compareVersions(meta.version, index[name].version) > 0 then
								index[name] = meta
							end
							counts.packages = counts.packages + 1
						end
					end
				end
			else
				-- a repository that cannot be reached must be reported, not
				-- quietly counted: "updated" with a missing index is worse
				-- than a visible error
				counts.errors = counts.errors or {}
				counts.errors[#counts.errors + 1] = source.location .. ": " .. tostring(err)
			end
		end
	end
	writeAll(self.indexFile, textutils.serialize(index))
	return true, counts
end

function M:fetch(url)
	if not http or not http.get then
		return nil, "http is not available"
	end
	local ok, res = pcall(http.get, url)
	if not ok or not res then
		return nil, "download failed: " .. tostring(url)
	end
	local code = res.getResponseCode and res.getResponseCode() or 200
	if code ~= 200 then
		res.close()
		return nil, "HTTP " .. code
	end
	local data = res.readAll()
	res.close()
	return data
end

-- ---------- versions ----------

-- compares dotted numeric versions: returns -1, 0, 1
function M:compareVersions(a, b)
	local function parts(v)
		local out = {}
		for piece in tostring(v or "0"):gmatch("[^%.]+") do
			out[#out + 1] = tonumber(piece) or 0
		end
		return out
	end
	local pa, pb = parts(a), parts(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x < y then
			return -1
		elseif x > y then
			return 1
		end
	end
	return 0
end

-- ---------- installed state ----------

function M:state()
	local data = readAll(self.stateFile)
	if not data then
		return {}
	end
	local ok, db = pcall(textutils.unserialize, data)
	if ok and type(db) == "table" then
		return db
	end
	return {}
end

function M:saveState(db)
	return writeAll(self.stateFile, textutils.serialize(db))
end

function M:installed()
	local out = {}
	for name, meta in pairs(self:state()) do
		out[#out + 1] = {
			name = name,
			version = tostring(meta.version or "?"),
			auto = meta.auto and true or false,
			source = meta.source,
			verified = meta.verified,
		}
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

function M:isInstalled(name)
	return self:state()[tostring(name)] ~= nil
end

function M:infoInstalled(name)
	return self:state()[tostring(name)]
end

-- ---------- dependencies ----------

function M:dependsOn(name)
	-- which packages in the catalog require `name`
	local out = {}
	for _, entry in ipairs(self:installed()) do
		local other = self:readMeta(entry.name)
		if other then
			for _, dep in ipairs(other.depends or {}) do
				if dep == name then
					out[#out + 1] = entry.name
				end
			end
		end
	end
	return out
end

-- returns the ordered install list (dependencies first) or nil, err
function M:resolve(name)
	local ordered, visiting, done = {}, {}, {}
	local function walk(pkg)
		if done[pkg] then
			return true
		end
		if visiting[pkg] then
			return nil, "dependency cycle involving " .. pkg
		end
		visiting[pkg] = true
		local meta, err = self:readMeta(pkg)
		if not meta then
			-- remote-only packages carry metadata in the index
			meta = self:indexEntry(pkg)
			if not meta then
				return nil, err or ("unknown package: " .. tostring(pkg))
			end
		end
		for _, dep in ipairs(meta.depends or {}) do
			local ok, depErr = walk(dep)
			if not ok then
				return nil, depErr
			end
		end
		visiting[pkg] = nil
		done[pkg] = true
		ordered[#ordered + 1] = pkg
		return true
	end
	local ok, err = walk(name)
	if not ok then
		return nil, err
	end
	return ordered
end

-- ---------- install / remove ----------

function M:install(name, options)
	options = options or {}
	name = tostring(name or "")
	if name == "" or name:find("%.") or name:find("/") then
		return nil, "unknown package"
	end
	local meta, err = self:readMeta(name)
	if not meta then
		meta = self:indexEntry(name)
		if not meta then
			return nil, err or ("unknown package: " .. name)
		end
	end
	if self:isInstalled(name) then
		return nil, "already installed"
	end

	local order, orderErr = self:resolve(name)
	if not order then
		return nil, orderErr
	end

	local installedNow = {}
	for _, pkg in ipairs(order) do
		if not self:isInstalled(pkg) then
			local ok, installErr = self:installOne(pkg, {
				auto = (pkg ~= name) or options.auto and true or false,
			})
			if not ok then
				for i = #installedNow, 1, -1 do
					self:remove(installedNow[i], { purge = true })
				end
				return nil, installErr
			end
			installedNow[#installedNow + 1] = pkg
		end
	end
	return true
end

function M:installOne(name, options)
	options = options or {}
	local meta = self:readMeta(name)
	if meta then
		return self:installFiles(name, meta, options)
	end
	local remote = self:indexEntry(name)
	if remote then
		return self:installRemote(name, remote, options)
	end
	return nil, "unknown package: " .. tostring(name)
end

function M:installFiles(name, meta, options)
	local pkgDir = fs.combine(self.catalogDir, name)
	local copied, sums = {}, {}
	for _, file in ipairs(meta.files) do
		local src = fs.combine(pkgDir, file)
		local dst = self.paths:osPath(file)
		if not fs.exists(src) then
			for _, done in ipairs(copied) do
				fs.delete(done)
			end
			return nil, "package file missing: " .. file
		end
		fs.makeDir(fs.getDir(dst))
		fs.copy(src, dst)
		copied[#copied + 1] = dst
		sums[file] = self.hash.sha256hex(readAll(src) or "")
	end
	local db = self:state()
	db[name] = {
		version = meta.version,
		files = sums,
		auto = options.auto and true or false,
		installedAt = os.epoch("utc"),
	}
	local saved = self:saveState(db)
	if not saved then
		for _, done in ipairs(copied) do
			fs.delete(done)
		end
		return nil, "failed to record installation"
	end
	return true
end

function M:installRemote(name, meta, options)
	local base = meta.origin or ""
	local published = meta.sha256 or {}
	local copied, sums, unverified = {}, {}, {}
	for _, file in ipairs(meta.files) do
		local body, err
		if meta.source == "rednet" then
			local reply, rednetErr = self:rednetFetch(meta.origin, { kind = "file", name = name, file = file })
			if reply then
				body = reply.data
			else
				err = rednetErr
			end
		else
			body, err = self:fetch(repoUrl(base, name, file))
		end
		if not body then
			for _, done in ipairs(copied) do
				fs.delete(done)
			end
			return nil, err
		end
		local digest = self.hash.sha256hex(body)
		-- A remote package is code from a machine we do not control, so a
		-- digest published in the index is the only thing that makes the
		-- download safe to run. Enforce it, and never write a file first.
		local expected = published[file]
		if type(expected) == "string" and expected ~= "" then
			if expected:lower() ~= digest then
				for _, done in ipairs(copied) do
					fs.delete(done)
				end
				return nil, "checksum mismatch for " .. file .. " (expected " ..
					tostring(expected) .. ", got " .. digest .. ")"
			end
		else
			unverified[#unverified + 1] = file
		end
		local dst = self.paths:osPath(file)
		fs.makeDir(fs.getDir(dst))
		writeAll(dst, body)
		copied[#copied + 1] = dst
		sums[file] = digest
	end
	local db = self:state()
	db[name] = {
		version = meta.version,
		files = sums,
		auto = options.auto and true or false,
		installedAt = os.epoch("utc"),
		source = "net",
		-- recorded so `apt info` and `apt verify` can say plainly that this
		-- package came off the network without a published digest
		verified = (#unverified == 0) and true or false,
	}
	if #unverified > 0 then
		db[name].unverified = unverified
	end
	if not self:saveState(db) then
		for _, done in ipairs(copied) do
			fs.delete(done)
		end
		return nil, "failed to record installation"
	end
	return true
end

function M:remove(name, options)
	options = options or {}
	name = tostring(name or "")
	local record = self:state()[name]
	if not record then
		return nil, "not installed"
	end
	if not options.purge then
		local dependents = self:dependsOn(name)
		for i = #dependents, 1, -1 do
			if not self:isInstalled(dependents[i]) then
				table.remove(dependents, i)
			end
		end
		if #dependents > 0 then
			return nil, "required by " .. table.concat(dependents, ", ")
		end
	end
	for file in pairs(record.files or {}) do
		local dst = self.paths:osPath(file)
		if fs.exists(dst) then
			fs.delete(dst)
		end
	end
	local meta = self:readMeta(name)
	if meta then
		-- legacy records may lack the file map; fall back to metadata
		for _, file in ipairs(meta.files or {}) do
			local dst = self.paths:osPath(file)
			if fs.exists(dst) then
				fs.delete(dst)
			end
		end
	end
	local db = self:state()
	db[name] = nil
	return self:saveState(db)
end

-- ---------- upgrade / verify / autoremove ----------

function M:upgrade()
	local report = { upgraded = {}, kept = 0, failed = {} }
	for _, entry in ipairs(self:installed()) do
		local meta = self:info(entry.name)
		if meta and self:compareVersions(meta.version, entry.version) > 0 then
			local removed, removeErr = self:remove(entry.name, { purge = true })
			if removed then
				local ok, installErr = self:installOne(entry.name, { auto = entry.auto })
				if ok then
					report.upgraded[#report.upgraded + 1] = entry.name
						.. " " .. entry.version .. " -> " .. meta.version
				else
					report.failed[#report.failed + 1] = entry.name .. ": " .. tostring(installErr)
				end
			else
				report.failed[#report.failed + 1] = entry.name .. ": " .. tostring(removeErr)
			end
		else
			report.kept = report.kept + 1
		end
	end
	return report
end

-- verifies recorded payload checksums; returns a list of broken files
function M:verify(name)
	local broken = {}
	local names = {}
	if name and name ~= "" then
		names[1] = name
	else
		for _, entry in ipairs(self:installed()) do
			names[#names + 1] = entry.name
		end
	end
	for _, pkg in ipairs(names) do
		local record = self:state()[pkg]
		if not record then
			broken[#broken + 1] = pkg .. ": not installed"
		else
			for file, expected in pairs(record.files or {}) do
				local dst = self.paths:osPath(file)
				local actual = fs.exists(dst) and self.hash.sha256hex(readAll(dst) or "") or "missing"
				if actual ~= expected then
					broken[#broken + 1] = pkg .. ": " .. file .. " (" .. actual .. ")"
				end
			end
		end
	end
	return broken
end

function M:autoremove()
	local removed = {}
	local changed = true
	while changed do
		changed = false
		for _, entry in ipairs(self:installed()) do
			if entry.auto then
				local dependents = self:dependsOn(entry.name)
				local needed = false
				for _, dep in ipairs(dependents) do
					if self:isInstalled(dep) then
						needed = true
					end
				end
				if not needed then
					self:remove(entry.name, { purge = true })
					removed[#removed + 1] = entry.name
					changed = true
				end
			end
		end
	end
	return removed
end

return M
