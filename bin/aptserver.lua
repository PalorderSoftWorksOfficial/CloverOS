-- aptserver: serve the local apt catalog to other computers over rednet.
--
-- The network counterpart of `apt`: one computer publishes its installed
-- catalog (etc/packages plus whatever net/rednet sources contributed), and
-- every other CloverOS machine adds a rednet source pointing at it:
--
--   aptserver [--dir /etc/packages] [--quiet]
--   apt add-source rednet <computer id>
--
-- The wire protocol is tiny: a request is { kind = "index" } or
-- { kind = "file", name = ..., file = ... }; replies are
-- { kind = "file", data = ... } / { kind = "missing" } / { kind = "error" }.
-- Everything travels as serialized tables on the clover/apt protocol, and
-- the client-side integrity rules (sha256 or [unverified]) are unchanged.
local root = CLOVER_ROOT or fs.getDir(shell.getRunningProgram())
local okSys, system = pcall(function()
	return dofile(fs.combine(root, "runtime/system.lua"))
end)
local okPkg, packages = pcall(function()
	return dofile(fs.combine(root, "runtime/packages.lua"))
end)

if not okSys or type(system) ~= "table" or not okPkg or type(packages) ~= "table" then
	print("aptserver: runtime modules unavailable")
	return
end

local sys = system.attach(root)
if not sys then
	print("aptserver: cannot locate the CloverOS root")
	return
end

local pathsOk, paths = pcall(function()
	return dofile(fs.combine(root, "runtime/paths.lua")).new(root)
end)
if not pathsOk or type(paths) ~= "table" then
	print("aptserver: paths module unavailable")
	return
end

local pkg = packages.new(paths)
local PROTOCOL = packages.REDNET_PROTOCOL or "clover/apt"

local catalogDir = "etc/packages"
local quiet = false
local args = { ... }
for i = 1, #args do
	if args[i] == "--quiet" then
		quiet = true
	elseif args[i] == "--help" then
		print("usage: aptserver [--dir <catalog dir>] [--quiet]")
		print("serves etc/packages over rednet until terminated")
		return
	elseif args[i] == "--dir" and args[i + 1] then
		catalogDir = args[i + 1]
	end
end

-- open rednet through the system layer so the panel and `rednet status`
-- agree with what the server is doing
local opened = sys:rednetOpen()
if not opened then
	local state = sys.state and sys.state.rednet
	if not (state and state.present) then
		print("aptserver: no rednet hardware (attach a modem)")
		return
	end
end

local function say(message)
	if not quiet then
		print(message)
	end
end

print("apt server on computer " .. os.getComputerID() .. " serving " .. catalogDir)
print("clients: apt add-source rednet " .. os.getComputerID())
print("ctrl+T (terminate) stops the server")

-- build the index once at startup; restart to publish new packages
local index = {}
if fs.isDir(catalogDir) then
	for _, name in ipairs(fs.list(catalogDir)) do
		local metaPath = fs.combine(catalogDir, name .. "/package.lua")
		if fs.exists(metaPath) then
			local ok, meta = pcall(dofile, metaPath)
			if ok and type(meta) == "table" and meta.files then
				meta.name = meta.name or name
				meta.version = tostring(meta.version or "1")
				-- publish digests so clients verify downloads exactly like
				-- a GitHub source
				meta.sha256 = meta.sha256 or {}
				for _, file in ipairs(meta.files) do
					if meta.sha256[file] == nil then
						local filePath = fs.combine(catalogDir, name .. "/" .. file)
						if fs.exists(filePath) then
							local h = fs.open(filePath, "r")
							if h then
								meta.sha256[file] = pkg.hash.sha256hex(h.readAll() or "")
								h.close()
							end
						end
					end
				end
				index[name] = meta
			end
		end
	end
end
local indexCount = 0
for _ in pairs(index) do
	indexCount = indexCount + 1
end
say("index: " .. indexCount .. " packages")

local served, requests = 0, 0
local running = true

local function reply(target, payload)
	rednet.send(target, textutils.serialize(payload), PROTOCOL)
end

while running do
	local senderId, message = rednet.receive(PROTOCOL)
	if senderId and message then
		requests = requests + 1
		local ok, request = pcall(textutils.unserialize, tostring(message))
		if ok and type(request) == "table" then
			if request.kind == "index" then
				reply(senderId, { kind = "file", data = index })
				served = served + 1
				say("index -> " .. tostring(senderId))
			elseif request.kind == "file" then
				local name = tostring(request.name or "")
				local file = tostring(request.file or "")
				-- path traversal guard: reject anything with slashes or dots
				local safe = name ~= "" and file ~= ""
					and not name:find("[%.\\/]") and not file:find("%.%.")
				if safe then
					local filePath = fs.combine(catalogDir, name .. "/" .. file)
					if fs.exists(filePath) and not fs.isDir(filePath) then
						local h = fs.open(filePath, "r")
						if h then
							reply(senderId, { kind = "file", data = h.readAll() })
							h.close()
							served = served + 1
							say(name .. "/" .. file .. " -> " .. tostring(senderId))
						else
							reply(senderId, { kind = "error", why = "cannot read " .. file })
						end
					else
						reply(senderId, { kind = "missing" })
					end
				else
					reply(senderId, { kind = "error", why = "bad request" })
				end
			else
				reply(senderId, { kind = "error", why = "unknown request kind" })
			end
		else
			reply(senderId, { kind = "error", why = "unparseable request" })
		end
	end
end
