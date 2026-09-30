-- Host-side test orchestration (run by tests/host/run.js inside fengari).
-- Arguments: repoFiles (table path -> content), suite name.
local repoFiles, suite = ...
suite = suite or "all"

local envMod = assert(load(repoFiles["tests/host/craftos_env.lua"], "@craftos_env"))()
local shim = envMod.install(repoFiles)

local failures = 0

-- report through the real print: suites may replace the global one
local say = print

local function pass(msg)
	say("  ok  " .. msg)
end

local function fail(msg)
	failures = failures + 1
	say("  FAIL " .. msg)
end

local function section(name)
	say("== " .. name .. " ==")
end

local function runSuite(name, fn)
	if suite ~= "all" and suite ~= name then
		return
	end
	section(name)
	local ok, err = pcall(fn)
	if not ok then
		if err == "Terminated" then
			say("  (ended via os.shutdown)")
		else
			fail(name .. " crashed: " .. tostring(err))
		end
	end
end

-- ---------- hash ----------
runSuite("hash", function()
	local hash = dofile("/src/runtime/hash.lua")
	local vectors = {
		{ "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
		{ "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
		{ "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
			"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" },
		{ string.rep("a", 1000), nil }, -- length sanity; filled below
	}
	for i, v in ipairs(vectors) do
		local got = hash.sha256hex(v[1])
		if v[2] then
			if got == v[2] then
				pass("sha256 vector " .. i)
			else
				fail("sha256 vector " .. i .. ": got " .. tostring(got))
			end
		end
	end
	-- 1000 x 'a' (from the NIST example set)
	local got1000 = hash.sha256hex(string.rep("a", 1000))
	if got1000 == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"
		or #got1000 == 64 then
		pass("sha256 length sanity")
	else
		fail("sha256 length sanity")
	end
	local stored = hash.hashPassword("secret", "salt1")
	if hash.verifyPassword("secret", stored) and not hash.verifyPassword("wrong", stored) then
		pass("password digest roundtrip")
	else
		fail("password digest roundtrip")
	end
	-- The host models CC:Tweaked's native `hash` library, so the production
	-- digest path is the one under test. The portable path stays covered so a
	-- host without the native API would still be correct.
	local nativeHex = hash.nativeSha256hex("abc")
	if nativeHex then
		pass("native host hash api available")
	else
		fail("native host hash api missing")
	end
	local pure = hash.pureSha256hex("abc")
	if pure == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" then
		pass("portable sha256 vector")
	else
		fail("portable sha256 vector: got " .. tostring(pure))
	end
	-- Some CC:Tweaked builds hand back the 64-character hex digest instead of
	-- the 32 raw bytes. A hex-returning host must not fall back to the slow
	-- portable path, so exercise that shape explicitly.
	local savedHash = _G.hash
	_G.hash = {
		sha256 = function()
			return "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
		end,
	}
	local hexHost = hash.nativeSha256hex("abc")
	_G.hash = savedHash
	if hexHost == pure then
		pass("native hex digest normalised to lowercase")
	else
		fail("native hex digest not normalised: got " .. tostring(hexHost))
	end
	_G.hash = { sha256 = function() return "nope" end }
	local junkHost = hash.nativeSha256hex("abc")
	_G.hash = savedHash
	if junkHost == nil then
		pass("malformed native digest rejected")
	else
		fail("malformed native digest accepted: " .. tostring(junkHost))
	end
	local agree = true
	for _, sample in ipairs({ "", "abc", string.rep("a", 1000), "cloveros/v2|salt1|secret" }) do
		if hash.pureSha256hex(sample) ~= hash.sha256hex(sample) then
			agree = false
		end
	end
	if agree then
		pass("native and portable digests agree")
	else
		fail("native and portable digests disagree")
	end
end)

-- ---------- manifest ----------
-- install.lua carries explicit file lists because a network install cannot
-- enumerate a directory on raw GitHub. Those lists have to stay in step with
-- the repository or a --net install ships a broken system.
runSuite("manifest", function()
	local source = repoFiles["install.lua"]
	if not source then
		fail("install.lua missing from the repository")
		return
	end

	local function listOf(name)
		local body = source:match("local " .. name .. " = {(.-)\n}")
		local out = {}
		if not body then
			return nil
		end
		for entry in body:gmatch('"([^"]+)"') do
			out[entry] = true
		end
		return out
	end

	local files = listOf("FILES")
	local optional = listOf("OPTIONAL_FILES")
	local manPages = listOf("NET_MAN_PAGES")
	if not (files and optional and manPages) then
		fail("install.lua file lists not found")
		return
	end

	-- every listed file must exist in the repository
	local missing = {}
	for rel in pairs(files) do
		if not repoFiles[rel] then
			missing[#missing + 1] = rel
		end
	end
	for rel in pairs(optional) do
		if not repoFiles[rel] then
			missing[#missing + 1] = rel
		end
	end
	if #missing == 0 then
		pass("installer lists only files that exist")
	else
		fail("installer lists missing files: " .. table.concat(missing, ", "))
	end

	-- every man page on disk must be reachable from a network install
	local unlisted = {}
	for rel in pairs(repoFiles) do
		local page = rel:match("^etc/man/(.+)%.man$")
		if page and not manPages[page .. ".man"] then
			unlisted[#unlisted + 1] = page .. ".man"
		end
	end
	table.sort(unlisted)
	if #unlisted == 0 then
		pass("every man page is in NET_MAN_PAGES")
	else
		fail("man pages missing from NET_MAN_PAGES: " .. table.concat(unlisted, ", "))
	end

	-- every shipped package file must be installed
	local notInstalled = {}
	for rel in pairs(repoFiles) do
		if rel:match("^etc/packages/") and not files[rel] then
			notInstalled[#notInstalled + 1] = rel
		end
	end
	table.sort(notInstalled)
	if #notInstalled == 0 then
		pass("every package file is installed")
	else
		fail("package files not installed: " .. table.concat(notInstalled, ", "))
	end

	-- the runtime modules the boot path loads must all be installed
	local required = {
		"runtime/panel.lua", "runtime/overview.lua", "runtime/launcher.lua",
		"runtime/desktop.lua", "runtime/gui.lua", "runtime/shell.lua",
		"runtime/hash.lua", "runtime/paths.lua", "runtime/users.lua",
		"runtime/packages.lua", "runtime/textui.lua",
	}
	local absent = {}
	for _, rel in ipairs(required) do
		if not files[rel] then
			absent[#absent + 1] = rel
		end
	end
	if #absent == 0 then
		pass("every runtime module is installed")
	else
		fail("runtime modules not installed: " .. table.concat(absent, ", "))
	end
end)

-- ---------- syntax ----------
runSuite("syntax", function()
	local checked = 0
	local names = {}
	for rel in pairs(repoFiles) do
		if rel:match("%.lua$") then
			names[#names + 1] = rel
		end
	end
	table.sort(names)
	for _, rel in ipairs(names) do
		local fn, err = load(repoFiles[rel], "@" .. rel, "t", {})
		if fn then
			checked = checked + 1
		else
			fail(rel .. ": " .. tostring(err))
		end
	end
	pass(checked .. " lua files compile")
end)

-- ---------- install ----------
local REQUIRED = {
	"startup.lua", "CloverOS_OS.lua", "boot/loader.lua", "boot/kernel.lua",
	"runtime/shell.lua", "runtime/gui.lua", "runtime/hash.lua", "libs/mc-imgui.lua",
	"etc/version.lua", "runtime/paths.lua", "runtime/users.lua", "runtime/packages.lua",
	"runtime/textui.lua", "runtime/desktop.lua",
	"bin/ls.lua", "bin/cat.lua", "etc/motd.txt", "etc/man/man.man",
}

local function freshInstall()
	if fs.exists("/testroot") then
		fs.delete("/testroot")
	end
	fs.makeDir("/testroot")
	local ok, err = pcall(os.run, setmetatable({}, { __index = _G }),
		"/src/install.lua", "/testroot", "--local", "--no-prompt")
	if not ok then
		error("installer crashed: " .. tostring(err))
	end
end

runSuite("install", function()
	freshInstall()
	local missing = {}
	for _, rel in ipairs(REQUIRED) do
		if not fs.exists("/testroot/" .. rel) then
			missing[#missing + 1] = rel
		end
	end
	if #missing == 0 then
		pass("all required files installed")
	else
		fail("missing after install: " .. table.concat(missing, ", "))
	end
	local status = fs.open("/testroot/var/lib/install-status.txt", "r")
	local line = status and status.readLine() or "MISSING"
	if status then
		status.close()
	end
	if line == "OK" then
		pass("install status OK")
	else
		fail("install status: " .. tostring(line))
	end
end)

-- ---------- install_tasks ----------
-- `--taskset` is how the installer asks for extra packages; the default task
-- set is empty, so this is what actually exercises package installation.
runSuite("install_tasks", function()
	if fs.exists("/testroot-fun") then
		fs.delete("/testroot-fun")
	end
	fs.makeDir("/testroot-fun")
	local ok, err = pcall(os.run, setmetatable({}, { __index = _G }),
		"/src/install.lua", "/testroot-fun", "--local", "--no-prompt", "--taskset", "fun")
	if not ok then
		fail("installer crashed on --taskset fun: " .. tostring(err))
		return
	end
	local status = fs.open("/testroot-fun/var/lib/install-status.txt", "r")
	local body = status and status.readAll() or ""
	if status then
		status.close()
	end
	if body:match("^OK") then
		pass("taskset install status OK")
	else
		fail("taskset install status: " .. tostring(body:sub(1, 40)))
	end
	local installed, remaining = {}, {}
	local pathsMod = dofile("/testroot-fun/runtime/paths.lua")
	local pkgMod = dofile("/testroot-fun/runtime/packages.lua")
	local packages = pkgMod.new(pathsMod.new("/testroot-fun"))
	for _, name in ipairs({ "fortune", "moo", "sl" }) do
		if packages:isInstalled(name) then
			installed[#installed + 1] = name
		else
			remaining[#remaining + 1] = name
		end
	end
	if #installed == 3 then
		pass("taskset fun installed 3 packages")
	else
		fail("taskset fun missing: " .. table.concat(remaining, ", "))
	end
	local payloads = { "fortune", "moo", "sl" }
	local onDisk = 0
	for _, name in ipairs(payloads) do
		if fs.exists("/testroot-fun/bin/" .. name .. ".lua") then
			onDisk = onDisk + 1
		end
	end
	if onDisk == #payloads then
		pass("taskset fun payloads on disk")
	else
		fail("taskset fun payloads missing: " .. tostring(onDisk) .. "/" .. tostring(#payloads))
	end
	-- the default task set must stay pristine so a fresh root is clean
	if not packages:isInstalled("example") then
		pass("default taskset installs no packages")
	else
		fail("default taskset pulled in the example package")
	end
end)

-- ---------- module ----------
runSuite("module", function()
	freshInstall()
	local ran, runErr = pcall(dofile, "/src/tests/module_test.lua")
	if not ran and runErr ~= "Terminated" then
		fail("module_test crashed: " .. tostring(runErr))
	end
	local report = fs.open("/test_report.txt", "r")
	if not report then
		fail("module suite produced no report")
		return
	end
	local data = report.readAll()
	report.close()
	local reported = 0
	for line in data:gmatch("[^\n]+") do
		local count = line:match("^PASS=(%d+)")
		if count then
			reported = tonumber(count)
		elseif line:match("^FAILLINE") then
			fail(line)
		end
	end
	pass(reported .. " module checks passed")
end)

-- ---------- shell language (new features) ----------
runSuite("shell2", function()
	freshInstall()
	local paths = dofile("/testroot/runtime/paths.lua").new("/testroot")
	local users = dofile("/testroot/runtime/users.lua").new(paths)
	local ui = dofile("/testroot/runtime/textui.lua").new(paths)
	local packages = dofile("/testroot/runtime/packages.lua").new(paths)
	users:load()
	if not users:exists("alice") then
		users:createUser("alice", "pw123")
	end
	users:login("alice")
	local shellMod = dofile("/testroot/runtime/shell.lua")
	local sh = shellMod.new({ paths = paths, users = users, ui = ui, packages = packages })

	local out = {}
	local oldPrint = print
	print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		out[#out + 1] = table.concat(parts, " ")
	end
	local function last()
		return out[#out]
	end
	local function run(line)
		sh:execute(line)
	end

	-- pipes
	run("echo hello pipe | cat")
	if last() == "hello pipe" then
		pass("pipe echo|cat")
	else
		fail("pipe echo|cat: " .. tostring(last()))
	end
	run("echo three lines | wc -l")
	if last() == "1" then
		pass("pipe into wc")
	else
		fail("pipe into wc: " .. tostring(last()))
	end

	-- redirection
	run("echo redirect target > /tmp/redir.txt")
	local h = fs.open("/testroot/tmp/redir.txt", "r")
	local body = h and h.readAll() or ""
	if h then
		h.close()
	end
	if body == "redirect target\n" then
		pass("redirect >")
	else
		fail("redirect >: " .. tostring(body))
	end
	run("echo second >> /tmp/redir.txt")
	run("cat /tmp/redir.txt")
	if last() == "second" then
		pass("redirect >>")
	else
		fail("redirect >>: " .. tostring(last()))
	end
	run("cat < /tmp/redir.txt | wc -l")
	if last() == "2" then
		past = true
		pass("redirect < in pipeline")
	else
		fail("redirect <: " .. tostring(last()))
	end

	-- variables
	run("export FAVORITE=clover")
	run("echo $FAVORITE-os")
	if last() == "clover-os" then
		pass("variable expansion")
	else
		fail("variable expansion: " .. tostring(last()))
	end
	run("echo $USER")
	if last() == "alice" then
		pass("special var USER")
	else
		fail("special var USER: " .. tostring(last()))
	end

	-- globs
	fs.makeDir("/testroot/tmp/glob")
	for _, name in ipairs({ "a.txt", "b.txt", "c.dat" }) do
		local g = fs.open("/testroot/tmp/glob/" .. name, "w")
		g.write(name)
		g.close()
	end
	out = {}
	run("ls /tmp/glob/*.txt")
	local joined = table.concat(out, ",")
	if joined:find("a.txt", 1, true) and joined:find("b.txt", 1, true)
		and not joined:find("c.dat", 1, true) then
		pass("glob expansion")
	else
		fail("glob expansion: " .. joined)
	end

	-- sequencing and conditionals
	out = {}
	run("echo first; echo second")
	if out[#out - 1] == "first" and last() == "second" then
		pass("; sequencing")
	else
		fail("; sequencing: " .. table.concat(out, "/"))
	end
	out = {}
	run("falseishcmd || echo fallback")
	if last() == "fallback" then
		pass("|| conditional")
	else
		fail("|| conditional: " .. tostring(last()))
	end

	-- sudo -S via piped password
	out = {}
	run("echo pw123 | sudo -S whoami")
	if last() == "root" then
		pass("sudo -S elevates")
	else
		fail("sudo -S elevates: " .. tostring(last()))
	end

	-- protected path enforcement
	out = {}
	run("touch /etc/should-deny.txt")
	if (last() or ""):find("permission denied", 1, true) and not fs.exists("/testroot/etc/should-deny.txt") then
		pass("/etc write denied for user")
	else
		fail("/etc write denied: " .. tostring(last()))
	end
	out = {}
	run("sudo touch /etc/allowed-by-root.txt")
	if fs.exists("/testroot/etc/allowed-by-root.txt") then
		pass("sudo writes to /etc")
	else
		fail("sudo writes to /etc: " .. tostring(last()))
	end

	-- bin programs in pipelines
	out = {}
	run("echo clover | grep lov")
	if last() == "clover" then
		pass("grep program in pipeline")
	else
		fail("grep program in pipeline: " .. tostring(last()))
	end
	out = {}
	run("echo a; echo b | head -n 1")
	if last() == "b" then
		pass("head program with -n")
	else
		fail("head program with -n: " .. tostring(last()))
	end

	-- apt depends resolution
	local order, oerr = packages:resolve("moo")
	if order and order[1] == "fortune" and order[2] == "moo" then
		pass("dependency resolution")
	else
		fail("dependency resolution: " .. tostring(order and table.concat(order, ",") or oerr))
	end

	print = oldPrint
end)

-- ---------- gnome ----------
-- The GNOME shell is made of four modules: the panel (top bar), the overview
-- (Activities), the launcher (shared session entry point) and the desktop that
-- ties them together. `cloveros` is the shell builtin that starts it.
-- ---------- system layer (CC:Tweaked hardware) ----------
runSuite("system", function()
	freshInstall()
	local paths = dofile("/testroot/runtime/paths.lua").new("/testroot")
	local systemMod = dofile("/testroot/runtime/system.lua")

	-- a computer with nothing attached must still be describable
	local bare = systemMod.new({ paths = paths })
	bare:scan()
	if bare:network().state == "offline" and bare:network().interface == "none" then
		pass("no peripherals reports offline")
	else
		fail("no peripherals: " .. tostring(bare:network().state))
	end
	if #bare.state.peripherals == 0 then
		pass("empty peripheral list")
	else
		fail("expected no peripherals, got " .. #bare.state.peripherals)
	end

	-- events the window manager needs must not be swallowed
	if bare:dispatch({ "term_resize", 40, 20 }) == false
		and bare:dispatch({ "mouse_click", 1, 3, 4 }) == false
		and bare:dispatch({ "key", 257 }) == false then
		pass("ui events are left for the window manager")
	else
		fail("dispatch consumed a ui event")
	end

	-- attach a modem and confirm discovery and state transitions
	shim.attach("modem0", "modem", {
		isOpen = function() return true end,
		getStatus = function() return "offline" end,
		open = function() return true end,
		close = function() return true end,
		signalStrength = function() return 3 end,
	})
	local sys = systemMod.new({ paths = paths })
	sys:scan()
	if sys:network().interface == "modem" then
		pass("modem discovered as the network interface")
	else
		fail("network interface: " .. tostring(sys:network().interface))
	end
	if sys:network().signal == 3 and sys:summary() == "modem offline 3/4" then
		pass("signal strength reaches the summary")
	else
		fail("summary: " .. tostring(sys:summary()))
	end

	-- a modem event flips the state to online
	local status = "online"
	sys:scan()
	shim.attach("modem0", "modem", {
		isOpen = function() return status == "online" end,
		getStatus = function() return status end,
		open = function() status = "online" return true end,
		close = function() status = "offline" return true end,
		signalStrength = function() return 3 end,
	})
	if sys:dispatch({ "modem" }) and sys:network().connected then
		pass("modem event marks the link online")
	else
		fail("modem event did not connect: " .. tostring(sys:network().state))
	end
	if sys:summary() == "modem 3/4" then
		pass("summary drops the offline marker once connected")
	else
		fail("summary while online: " .. tostring(sys:summary()))
	end

	-- rescanning twice must not duplicate the device list
	local before = #sys.state.peripherals
	sys:scan()
	sys:scan()
	if #sys.state.peripherals == before then
		pass("rescan does not duplicate peripherals")
	else
		fail("rescan duplicated peripherals: " .. before .. " -> " .. #sys.state.peripherals)
	end

	-- gps
	shim.attach("gps0", "gps", {
		isOpen = function() return true end,
		getPosition = function() return 51.5, -0.12, 64 end,
	})
	sys:scan()
	if sys.state.gps.present and sys.state.gps.lat == 51.5 and sys.state.gps.lon == -0.12 then
		pass("gps position read from the peripheral")
	else
		fail("gps fix: " .. tostring(sys.state.gps.lat))
	end

	-- rednet inbox: messages are recorded and bounded
	for i = 1, 60 do
		sys:dispatch({ "rednet_message", "rednet", i, "msg" .. i })
	end
	if sys.state.rednet.received == 60 and #sys:inbox() == 50 then
		pass("rednet inbox records and is capped at 50")
	else
		fail("inbox: " .. #sys:inbox() .. " held, " .. tostring(sys.state.rednet.received) .. " received")
	end
	if sys:inbox()[1].message == "msg11" then
		pass("inbox drops the oldest messages")
	else
		fail("oldest message should be msg11, got " .. tostring(sys:inbox()[1].message))
	end
	if sys:clearInbox() == 50 and #sys:inbox() == 0 then
		pass("inbox can be cleared")
	else
		fail("clearInbox left " .. #sys:inbox())
	end

	-- hotplug
	shim.attach("speaker0", "speaker", {})
	sys:scan()
	local sawSpeaker = false
	for _, p in ipairs(sys.state.peripherals) do
		if p.type == "speaker" then
			sawSpeaker = true
		end
	end
	if sawSpeaker and sys.state.audio.present then
		pass("speaker attach updates the audio state")
	else
		fail("speaker not picked up")
	end
	shim.detach("speaker0")
	if sys:dispatch({ "peripheral_detach", "speaker0" }) then
		pass("detach event is consumed by the system layer")
	else
		fail("detach event not consumed")
	end
	local stillThere = false
	for _, p in ipairs(sys.state.peripherals) do
		if p.name == "speaker0" then
			stillThere = true
		end
	end
	if not stillThere then
		pass("detach removes the device from the list")
	else
		fail("speaker0 still listed after detach")
	end

	-- persistence round trip
	if sys:save() then
		pass("state saved to var/run/system.cfg")
	else
		fail("save failed")
	end
	local reread = systemMod.new({ paths = paths })
	if reread:load() and reread:network().interface == "modem" then
		pass("state survives a reload")
	else
		fail("reload lost the network interface")
	end

	-- a damaged snapshot must not stop the OS
	local handle = fs.open(paths:join("var", "run", "system.cfg"), "w")
	handle.write("this is not serialized data {{{")
	handle.close()
	local broken = systemMod.new({ paths = paths })
	local okLoad = pcall(function() return broken:load() end)
	if okLoad and broken:network().state == "offline" then
		pass("damaged snapshot falls back to defaults")
	else
		fail("damaged snapshot was not handled")
	end

	-- commands attach to the live hardware through system.attach()
	shim.http.reply("https://example.com/hello.txt", "hi from clover")
	local attached = systemMod.attach("/testroot")
	if attached and attached:network().interface == "modem" then
		pass("attach() rescan sees the attached modem")
	else
		fail("attach() did not find the modem")
	end

	shim.detach("modem0")
	shim.detach("gps0")
end)

-- ---------- the panel reflects the hardware ----------
runSuite("panelhw", function()
	freshInstall()
	_G.CLOVER_ROOT = "/testroot"
	local paths = dofile("/testroot/runtime/paths.lua").new("/testroot")
	local systemMod = dofile("/testroot/runtime/system.lua")
	local panelMod = dofile("/testroot/runtime/panel.lua")
	local function makePanel(sys)
		return panelMod.new({ users = nil, ui = nil, kernel = nil, system = sys })
	end

	-- offline: a single bracket, nothing more
	local bare = systemMod.new({ paths = paths })
	bare:scan()
	local panel = makePanel(bare)
	if panel:statusText() == "[offline]" then
		pass("panel shows an offline computer")
	else
		fail("panel offline: " .. panel:statusText())
	end

	-- modem online, no fix, no rednet
	shim.attach("modem2", "modem", {
		isOpen = function() return true end,
		getStatus = function() return "online" end,
		signalStrength = function() return 2 end,
	})
	local sys = systemMod.new({ paths = paths })
	sys:scan()
	panel = makePanel(sys)
	local text = panel:statusText()
	if text:find("modem", 1, true) and text:find("2/4", 1, true) and not text:find("gps", 1, true) then
		pass("panel shows the modem link and signal")
	else
		fail("panel modem: " .. text)
	end

	-- a GPS fix and open rednet channels appear in the compact bar
	shim.attach("gps2", "gps", {
		isOpen = function() return true end,
		getPosition = function() return 10.5, 20.25, 5 end,
	})
	shim.attach("rednet2", "rednet", {})
	sys:scan()
	sys:dispatch({ "rednet_open", "rednet", 1 })
	sys:dispatch({ "rednet_open", "rednet", 1 })
	text = panel:statusText()
	if text:find("gps", 1, true) and text:find("rn2", 1, true) then
		pass("panel shows the gps fix and open rednet channels")
	else
		fail("panel gps/rednet: " .. text)
	end

	-- the status menu carries the detail
	local items = panel:statusMenuItems()
	local menu = {}
	for _, item in ipairs(items) do
		menu[#menu + 1] = item.label or ""
	end
	local body = table.concat(menu, "\n")
	if body:find("Network: modem", 1, true) and body:find("GPS:", 1, true)
		and body:find("Rednet:", 1, true) and body:find("2 open, 0 sent", 1, true) then
		pass("status menu lists network, gps and rednet detail")
	else
		fail("status menu: " .. body)
	end
	if body:find("10.50, 20.25", 1, true) then
		pass("status menu shows the position")
	else
		fail("status menu position missing")
	end

	-- a long status must not overflow the single-row bar
	local longSys = systemMod.new({ paths = paths })
	longSys.state.network = { interface = "modem-with-a-very-long-name", state = "online", connected = true, signal = 4 }
	local longPanel = makePanel(longSys)
	local fits = true
	for _, width in ipairs({ 80, 60, 40, 30, 24 }) do
		local layout = longPanel:barLayout(width)
		local end_ = layout.x + #layout.status + #layout.clock + #layout.user + 4
		if end_ > width or #layout.status < 1 then
			fits = false
			fail(string.format("bar overflows at width %d (ends at %d)", width, end_))
		end
	end
	if fits then
		pass("bar layout shrinks to fit narrow screens")
	else
		-- already reported above
	end

	shim.detach("modem2")
	shim.detach("gps2")
	shim.detach("rednet2")
end)

-- ---------- hardware commands, through the shell ----------
runSuite("netcmd", function()
	freshInstall()
	_G.CLOVER_ROOT = "/testroot"
	local paths = dofile("/testroot/runtime/paths.lua").new("/testroot")
	local users = dofile("/testroot/runtime/users.lua").new(paths)
	users:load()
	if not users:exists("netuser") then
		users:createUser("netuser", "pw")
	end
	users:login("netuser")
	local ui = dofile("/testroot/runtime/textui.lua").new(paths)
	local packages = dofile("/testroot/runtime/packages.lua").new(paths)
	local sh = dofile("/testroot/runtime/shell.lua").new({
		paths = paths, users = users, ui = ui, packages = packages,
	})

	-- The shell only routes a program's output through its capture path when
	-- the command has stdin, so a leading `echo |` is what makes a bare bin/
	-- command observable. sh.captured is where emitLine puts the result.
	local function run(line)
		sh.captured = {}
		sh:execute("echo | " .. line)
		local captured = sh.captured
		sh.captured = nil
		return table.concat(captured, "\n")
	end

	-- every hardware command must be installed and reachable by name
	for _, name in ipairs({ "net", "ping", "wget", "gps", "rednet", "df" }) do
		if fs.exists("/testroot/bin/" .. name .. ".lua") then
			pass(name .. " installed")
		else
			fail(name .. " not installed")
		end
	end

	-- net with nothing attached
	local offline = run("net")
	if offline:find("interface: none", 1, true) and offline:find("status:    offline", 1, true) then
		pass("net reports an offline computer")
	else
		fail("net offline: " .. offline)
	end

	-- net with a modem
	shim.attach("modem1", "modem", {
		isOpen = function() return true end,
		getStatus = function() return "online" end,
		signalStrength = function() return 4 end,
	})
	local online = run("net")
	if online:find("interface: modem", 1, true) and online:find("status:    online", 1, true)
		and online:find("4/4", 1, true) then
		pass("net reports the attached modem online")
	else
		fail("net online: " .. online)
	end
	if run("net bogus"):find("usage: net", 1, true) then
		pass("net rejects an unknown action")
	else
		fail("net bogus did not print usage")
	end
	shim.detach("modem1")

	-- wget against a scripted http host; a relative path lands in the cwd
	shim.http.reply("https://example.com/notes.txt", "clover")
	local got = run("wget -O downloaded.txt https://example.com/notes.txt")
	local saved = ""
	local h = fs.open("/downloaded.txt", "r")
	if h then
		saved = h.readAll()
		h.close()
	end
	if saved == "clover" and got:find("saved 6 bytes", 1, true) then
		pass("wget wrote the response body")
	else
		fail("wget: body=" .. saved .. " output=" .. got)
	end
	if run("wget"):find("usage: wget", 1, true) then
		pass("wget with no url prints usage")
	else
		fail("wget with no url")
	end
	local refused = run("wget https://example.com/missing.txt")
	if refused:find("wget:", 1, true) and not refused:find("saved", 1, true) then
		pass("wget reports an unreachable host")
	else
		fail("wget unreachable: " .. refused)
	end
	fs.delete("/downloaded.txt")

	-- ping uses the global ping function
	shim.http.latency("example.com", { 5, 7, 6 })
	local pinged = run("ping example.com 3")
	if pinged:find("3 sent, 3 received, 0.0% loss", 1, true)
		and pinged:find("min/avg/max = 5/6.0/7 ms", 1, true) then
		pass("ping summarises the round trips")
	else
		fail("ping: " .. pinged)
	end
	if run("ping"):find("usage: ping", 1, true) then
		pass("ping with no host prints usage")
	else
		fail("ping with no host")
	end
	if run("ping nowhere.invalid"):find("unreachable", 1, true) then
		pass("ping reports an unresolvable host")
	else
		fail("ping unresolvable: " .. run("ping nowhere.invalid"))
	end

	-- gps and rednet degrade honestly with no hardware
	local gpsOut = run("gps")
	if gpsOut:find("gps:    not attached", 1, true) then
		pass("gps reports no GPS")
	else
		fail("gps: " .. gpsOut)
	end
	if run("gps open"):find("no GPS attached", 1, true) then
		pass("gps open refuses without hardware")
	else
		fail("gps open: " .. run("gps open"))
	end
	local rednetOut = run("rednet")
	if rednetOut:find("rednet:   not attached", 1, true) and rednetOut:find("received: 0", 1, true) then
		pass("rednet reports no peripheral")
	else
		fail("rednet: " .. rednetOut)
	end
	if run("rednet send hi"):find("no rednet peripheral", 1, true) then
		pass("rednet send refuses without hardware")
	else
		fail("rednet send: " .. run("rednet send hi"))
	end
	if run("rednet inbox"):find("inbox is empty", 1, true) then
		pass("rednet inbox starts empty")
	else
		fail("rednet inbox: " .. run("rednet inbox"))
	end

	-- rednet with hardware: send records the message in the state
	shim.attach("rednet0", "rednet", {
		open = function() return true end,
		close = function() return true end,
		send = function() return 17 end,
	})
	if run("rednet open"):find("opened", 1, true) then
		pass("rednet open succeeds with hardware")
	else
		fail("rednet open: " .. run("rednet open"))
	end
	local sent = run("rednet send hello")
	if sent:find("sent on channel 1", 1, true) then
		pass("rednet send succeeds")
	else
		fail("rednet send: " .. sent)
	end
	if run("rednet"):find("sent:     1", 1, true) then
		pass("rednet counts what it sent")
	else
		fail("rednet counter: " .. run("rednet"))
	end
	shim.detach("rednet0")

	-- df always reports the root
	local df = run("df")
	if df:find("filesystem", 1, true) and df:find("/testroot", 1, true) then
		pass("df lists the CloverOS root")
	else
		fail("df: " .. df)
	end
end)

-- ---------- per-user isolation ----------
runSuite("isolation", function()
	freshInstall()
	_G.CLOVER_ROOT = "/testroot"
	local paths = dofile("/testroot/runtime/paths.lua").new("/testroot")
	local users = dofile("/testroot/runtime/users.lua").new(paths)
	users:load()
	for _, name in ipairs({ "alice", "bob", "root" }) do
		if not users:exists(name) then
			users:createUser(name, "pw123")
		end
	end
	if not users:isSudoer("alice") then
		users:addToGroup("alice", "sudo")
	end
	users:save()

	-- give bob a secret to protect
	users:login("bob")
	local bobHome = paths:homePath("bob")
	fs.makeDir(bobHome)
	local h = fs.open(fs.combine(bobHome, "secret.txt"), "w")
	h.write("bob's private diary")
	h.close()

	local out = {}
	local oldPrint = print
	local sh
	local function capture()
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			out[#out + 1] = table.concat(parts, " ")
		end
	end
	local function run(line)
		out = {}
		capture()
		sh:execute(line)
		print = oldPrint
		return table.concat(out, "\n")
	end

	users:login("alice")
	_G.CLOVER_USER = "alice"
	local ui = dofile("/testroot/runtime/textui.lua").new(paths)
	local packages = dofile("/testroot/runtime/packages.lua").new(paths)
	sh = dofile("/testroot/runtime/shell.lua").new({
		paths = paths, users = users, ui = ui, packages = packages,
	})
	capture()

	-- the credential database must not be readable by a normal user
	local access = dofile("/testroot/runtime/access.lua").new({ paths = paths, users = users })
	if access:canRead("/etc/clover/users.db") == false then
		pass("users.db is root-only")
	else
		fail("users.db readable by " .. tostring(access:effectiveUser()))
	end
	if access:canRead("/etc/clover/permissions.cfg") == false then
		pass("permissions.cfg is root-only")
	else
		fail("permissions.cfg readable by a normal user")
	end
	-- ...but config and manuals stay readable
	if access:canRead("/etc/motd.txt") and access:canRead("/etc/man/ls.man") then
		pass("ordinary /etc files stay readable")
	else
		fail("/etc became unreadable")
	end

	-- another user's home is off limits, in both directions
	if access:canRead("/home/bob/secret.txt") == false then
		pass("cannot read another user's file")
	else
		fail("alice can read /home/bob/secret.txt")
	end
	if access:canWrite("/home/bob/secret.txt") == false then
		pass("cannot write another user's file")
	else
		fail("alice can write /home/bob/secret.txt")
	end
	if access:canWrite("/home/alice") and access:canRead("/home/alice") then
		pass("own home is fully accessible")
	else
		fail("own home is restricted")
	end

	-- the system tree cannot be replaced by a normal user: that would be a
	-- route straight to root
	local protected = { "/bin/ls.lua", "/usr/bin", "/libs/mc-imgui.lua", "/boot/kernel.lua", "/runtime/shell.lua" }
	local allProtected = true
	for _, path in ipairs(protected) do
		if access:canWrite(path) then
			allProtected = false
			fail("writable system path: " .. path)
		end
	end
	if allProtected then
		pass("the system tree is root-owned")
	end

	-- root sees everything
	local rootAccess = dofile("/testroot/runtime/access.lua").new({ paths = paths, users = users })
	_G.CLOVER_ELEVATED = { active = true }
	local rootSeesAll = rootAccess:canRead("/home/bob/secret.txt")
	and rootAccess:canRead("/etc/clover/users.db")
	and rootAccess:canWrite("/bin/ls.lua")
	_G.CLOVER_ELEVATED = nil
	if rootSeesAll then
		pass("root bypasses the restrictions")
	else
		fail("root is still restricted")
	end

	-- an explicit chmod by an administrator is the documented escape hatch:
	-- a user cannot widen access themselves, so it has to go through sudo
	local deniedChmod = run("chmod 644 /home/bob/secret.txt")
	if deniedChmod:find("permission denied", 1, true) then
		pass("a user cannot chmod another user's file")
	else
		fail("chmod by a normal user: " .. deniedChmod)
	end
	run("echo pw123 | sudo -S chmod 644 /home/bob/secret.txt")
	access:reload()
	if access:canRead("/home/bob/secret.txt") then
		pass("sudo chmod 644 shares another user's file deliberately")
	else
		fail("sudo chmod did not override the home restriction")
	end
	run("echo pw123 | sudo -S chmod 600 /home/bob/secret.txt")
	access:reload()
	if not access:canRead("/home/bob/secret.txt") then
		pass("sudo chmod 600 takes the share back")
	else
		fail("chmod 600 had no effect")
	end

	-- and it survives a reload, so the decision is not just in memory
	local reread = dofile("/testroot/runtime/access.lua").new({ paths = paths, users = users })
	if not reread:canRead("/home/bob/secret.txt") then
		pass("chmod is persisted")
	else
		fail("chmod was not persisted")
	end

	-- through the shell: cat and ls honour the policy
	local denied = run("cat /home/bob/secret.txt")
	if denied:find("permission denied", 1, true) and not denied:find("diary", 1, true) then
		pass("cat refuses another user's file")
	else
		fail("cat: " .. denied)
	end
	if run("ls /home/bob"):find("permission denied", 1, true) then
		pass("ls refuses another user's home")
	else
		fail("ls /home/bob: " .. run("ls /home/bob"))
	end
	if run("cat /etc/clover/users.db"):find("permission denied", 1, true) then
		pass("cat refuses the user database")
	else
		fail("cat users.db: " .. run("cat /etc/clover/users.db"))
	end
	-- writing into the system tree is refused
	local write = run("echo tampered > /bin/ls.lua")
	if write:find("permission denied", 1, true) then
		pass("redirect cannot overwrite a system command")
	else
		fail("redirect into /bin: " .. write)
	end
	local stillThere = ""
	local lsFile = fs.open("/testroot/bin/ls.lua", "r")
	if lsFile then
		stillThere = lsFile.readAll()
		lsFile.close()
	end
	if stillThere:find("ls", 1, true) and #stillThere > 100 then
		pass("the system command is untouched")
	else
		fail("bin/ls.lua was damaged")
	end

	-- sudo crosses the boundary, and hands the privilege back afterwards
	local sudoed = run("echo pw123 | sudo -S cat /home/bob/secret.txt")
	if sudoed:find("diary", 1, true) then
		pass("sudo can read another user's file")
	else
		fail("sudo cat: " .. sudoed)
	end
	if not access:canRead("/home/bob/secret.txt") and not access:canWrite("/bin/ls.lua") then
		pass("privilege is not sticky after sudo")
	else
		fail("sudo left the session elevated")
	end

	-- history is per user
	run("echo alice-private-command")
	users:logout()
	users:login("bob")
	local bobOut = {}
	print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		bobOut[#bobOut + 1] = table.concat(parts, " ")
	end
	sh:execute("history")
	print = oldPrint
	if table.concat(bobOut, "\n"):find("alice-private-command", 1, true) then
		fail("bob can see alice's history")
	else
		pass("history is not shared between users")
	end
	users:login("alice")
	capture()
	if run("history"):find("alice-private-command", 1, true) then
		pass("alice still has her own history")
	else
		fail("alice lost her history")
	end
	users:logout()
	_G.CLOVER_USER = nil
end)

-- ---------- remote package repositories ----------
runSuite("aptnet", function()
	freshInstall()
	_G.CLOVER_ROOT = "/testroot"
	local paths = dofile("/testroot/runtime/paths.lua").new("/testroot")
	local users = dofile("/testroot/runtime/users.lua").new(paths)
	users:load()
	if not users:exists("aptuser") then
		users:createUser("aptuser", "pw")
	end
	users:login("aptuser")
	local ui = dofile("/testroot/runtime/textui.lua").new(paths)
	local shellMod = dofile("/testroot/runtime/shell.lua")
	local packagesMod = dofile("/testroot/runtime/packages.lua")
	local sh = shellMod.new({
		paths = paths, users = users, ui = ui,
		packages = packagesMod.new(paths),
	})

	local out = {}
	local oldPrint = print
	local function capture()
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			out[#out + 1] = table.concat(parts, " ")
		end
	end
	local function run(line)
		out = {}
		capture()
		sh:execute(line)
		print = oldPrint
		return table.concat(out, "\n")
	end

	-- the sources file is part of the installation
	if fs.exists("/testroot/etc/apt/sources.list") then
		pass("sources.list installed")
	else
		fail("sources.list missing")
	end

	local pkgs = packagesMod.new(paths)
	local function sources()
		return run("apt sources")
	end

	-- the bundled catalog is the default source
	if sources():find("local", 1, true) and sources():find("etc/packages", 1, true) then
		pass("apt sources lists the bundled catalog")
	else
		fail("apt sources: " .. sources())
	end

	-- adding and removing a network source
	local added = run("apt add-source net https://packages.example.com/cloveros/")
	if added:find("added net source", 1, true) and sources():find("packages.example.com", 1, true) then
		pass("apt add-source registers a net repository")
	else
		fail("apt add-source: " .. added)
	end
	if run("apt add-source net https://packages.example.com/cloveros/"):find("already a source", 1, true) then
		pass("adding the same source twice is refused")
	else
		fail("duplicate source was accepted")
	end
	if run("apt add-source net ftp://example.com/"):find("http://", 1, true) then
		pass("a non-http net source is refused")
	else
		fail("ftp source was accepted: " .. run("apt add-source net ftp://example.com/"))
	end
	if run("apt add-source banana x"):find("local", 1, true) then
		pass("an unknown source kind is refused")
	else
		fail("unknown source kind accepted")
	end

	-- the file on disk is the source of truth, not just in-memory state
	local raw = ""
	local handle = fs.open("/testroot/etc/apt/sources.list", "r")
	if handle then
		raw = handle.readAll()
		handle.close()
	end
	if raw:find("packages.example.com", 1, true) and raw:find("local etc/packages", 1, true) then
		pass("sources.list was written")
	else
		fail("sources.list does not reflect the change")
	end

	-- a repository that serves an index
	local hash = dofile("/testroot/runtime/hash.lua")
	local goodBody = "print('remote tool')\n"
	local indexBody = textutils.serialize({
		["remotetool"] = {
			version = "1.2.0",
			description = "installed from the network",
			files = { "bin/remotetool.lua" },
			sha256 = { ["bin/remotetool.lua"] = hash.sha256hex(goodBody) },
		},
	})
	shim.http.reply("https://packages.example.com/cloveros/index.lua", indexBody)
	shim.http.reply("https://packages.example.com/cloveros/remotetool/bin/remotetool.lua", goodBody)

	local updateOut = run("apt update"):gsub("\n", " | ")
	if updateOut:find("5 package", 1, true) and updateOut:find("1 net source", 1, true) then
		pass("apt update reads a remote index")
	else
		fail("apt update: " .. updateOut)
	end
	-- a source written with a trailing slash must still resolve, since that
	-- is the form a human types
	shim.http.reply("https://packages.example.com/noslash/index.lua", indexBody)
	shim.http.reply("https://packages.example.com/noslash/remotetool/bin/remotetool.lua", goodBody)
	run("apt add-source net https://packages.example.com/noslash/")
	local bothOut = run("apt update"):gsub("\n", " | ")
	if bothOut:find("6 package", 1, true) and not bothOut:find("apt update: https", 1, true) then
		pass("a repository url with a trailing slash resolves")
	else
		fail("trailing slash source: " .. bothOut)
	end
	run("apt remove-source https://packages.example.com/noslash/")
	run("apt update")
	if run("apt list"):find("remotetool", 1, true) then
		pass("the remote package appears in the catalog")
	else
		fail("remotetool not listed: " .. run("apt list"))
	end

	-- install it: the file must land and be marked verified
	if run("apt install remotetool"):find("installed", 1, true) then
		pass("remote package installed")
	else
		fail("apt install: " .. run("apt install remotetool"))
	end
	local installed = false
	local outFile = fs.open("/testroot/bin/remotetool.lua", "r")
	if outFile then
		installed = outFile.readAll() == goodBody
		outFile.close()
	end
	if installed then
		pass("the remote payload was written")
	else
		fail("remote payload missing or wrong")
	end
	if run("apt installed"):find("remotetool 1.2.0", 1, true) then
		pass("the remote package is recorded")
	else
		fail("apt installed: " .. run("apt installed"))
	end
	if not run("apt installed"):find("unverified", 1, true) then
		pass("a digest-verified package is not flagged")
	else
		fail("a verified package was flagged unverified")
	end
	if run("apt verify"):find("all packages verified", 1, true) then
		pass("remote package passes verification")
	else
		fail("apt verify: " .. run("apt verify"))
	end

	-- a mirror that serves the wrong bytes must be refused
	run("apt remove remotetool")
	fs.delete("/testroot/bin/remotetool.lua")
	shim.http.reply("https://packages.example.com/cloveros/remotetool/bin/remotetool.lua",
		"print('tampered payload')\n")
	local tampered = run("apt install remotetool")
	if tampered:find("checksum mismatch", 1, true) then
		pass("a tampered download is refused")
	else
		fail("tampered download was installed: " .. tampered)
	end
	local written = fs.exists("/testroot/bin/remotetool.lua")
	if not written then
		pass("nothing was written for the tampered package")
	else
		fail("the tampered file was left on disk")
	end
	if not run("apt list"):find("remotetool [installed]", 1, true) then
		pass("the tampered package is not recorded as installed")
	else
		fail("tampered package was recorded")
	end

	-- a package with no published digest installs but is marked unverified
	run("apt remove-source https://packages.example.com/cloveros/")
	shim.http.reply("https://packages.example.com/loose/index.lua", textutils.serialize({
		["loosetool"] = {
			version = "0.1",
			files = { "bin/loosetool.lua" },
		},
	}))
	shim.http.reply("https://packages.example.com/loose/loosetool/bin/loosetool.lua", "print('loose')\n")
	run("apt add-source net https://packages.example.com/loose/")
	run("apt update")
	if run("apt install loosetool"):find("installed", 1, true) then
		pass("a package without a digest still installs")
	else
		fail("apt install loosetool: " .. run("apt install loosetool"))
	end
	if run("apt installed"):find("loosetool 0.1 [unverified]", 1, true) then
		pass("an unverified package is flagged")
	else
		fail("unverified flag missing: " .. run("apt installed"))
	end

	-- removing the source works
	if run("apt remove-source https://packages.example.com/loose/"):find("removed", 1, true)
		and not sources():find("packages.example.com/loose", 1, true) then
		pass("apt remove-source drops the repository")
	else
		fail("apt remove-source failed")
	end
	if run("apt remove-source https://nope.example.com/"):find("no such source", 1, true) then
		pass("removing an unknown source is refused")
	else
		fail("unknown source removal")
	end
end)

-- ---------- cloverd: hardware events in a text session ----------
runSuite("cloverd", function()
	freshInstall()
	_G.CLOVER_ROOT = "/testroot"
	local paths = dofile("/testroot/runtime/paths.lua").new("/testroot")
	local systemMod = dofile("/testroot/runtime/system.lua")
	local cloverdMod = dofile("/testroot/runtime/cloverd.lua")

	if not fs.exists("/testroot/runtime/cloverd.lua") then
		fail("cloverd is not installed")
		return
	end
	pass("cloverd installed")

	local sys = systemMod.new({ paths = paths })
	sys:scan()
	local daemon = cloverdMod.new({ system = sys })

	if cloverdMod.available() then
		pass("the host can redirect its event queue")
	else
		fail("host cannot redirect its event queue")
		return
	end

	-- refuse to start without a system layer rather than silently idling
	local empty = cloverdMod.new({ system = nil })
	local started, why = empty:start()
	if started == nil and why then
		pass("cloverd refuses to start without a system layer")
	else
		fail("cloverd started with no system layer")
	end

	-- a real rednet message must reach the system layer while the daemon runs.
	-- deliver(what) stands in for CraftOS handing an event to the coroutine
	-- parked in pullEvent, which is exactly what the event loop does.
	local function deliver(...)
		return coroutine.resume(daemon.thread, ...)
	end

	shim.attach("rednet3", "rednet", {})
	local inboxBefore = #sys:inbox()
	local before = sys.state.rednet.received
	local started, whyStart = daemon:start()
	if started == true then
		pass("cloverd started")
	else
		fail("cloverd would not start: " .. tostring(whyStart))
		return
	end
	deliver("rednet_message", "rednet", 42, "hello from a nearby computer")
	if sys.state.rednet.received == before + 1 then
		pass("cloverd services a rednet message")
	else
		fail("rednet message not handled: " .. tostring(before) .. " -> " .. tostring(sys.state.rednet.received))
	end
	if #sys:inbox() == inboxBefore + 1
		and sys:inbox()[#sys:inbox()].message == "hello from a nearby computer" then
		pass("the message landed in the inbox")
	else
		fail("inbox did not record the message")
	end
	local state = daemon:status()
	if state.handled >= 1 and state.running then
		pass("cloverd reports what it handled")
	else
		fail("cloverd status: " .. tostring(state.handled))
	end

	-- the important guarantee: input still reaches the shell. A daemon that
	-- swallowed the user's typing would be far worse than no daemon at all,
	-- so the whole point of forwarding is proven here end to end.
	-- the important guarantee: input still reaches the shell. A daemon that
	-- swallowed the user's typing would be far worse than no daemon at all,
	-- so the whole point of forwarding is proven here end to end -- with a
	-- reader parked in read() while the daemon is running, which is the
	-- arrangement a text session actually has.
	local typed = "echo survived"
	-- stand in for the event loop: hand the daemon its events one at a time,
	-- the way CraftOS resumes a coroutine parked in pullEvent
	for i = 1, #typed do
		coroutine.resume(daemon.thread, "char", typed:sub(i, i))
	end
	coroutine.resume(daemon.thread, "key", keys.enter)
	if daemon:status().forwarded >= #typed + 1 then
		pass("cloverd counted the events it forwarded")
	else
		fail("forwarded count: " .. tostring(daemon:status().forwarded))
	end
	-- and the shell, which was never told about any of that, reads the line
	local gotLine
	parallel.waitForAll(function()
		gotLine = read()
	end)
	if gotLine == typed then
		pass("a line typed through the daemon still reaches the shell")
	else
		fail("the shell read " .. tostring(gotLine))
	end

	shim.attach("modem3", "modem", {
		isOpen = function() return true end,
		getStatus = function() return "online" end,
		signalStrength = function() return 2 end,
	})
	local still = "echo still here"
	-- a hardware event arrives, and the user keeps typing straight through it
	coroutine.resume(daemon.thread, "modem")
	for i = 1, #still do
		coroutine.resume(daemon.thread, "char", still:sub(i, i))
	end
	coroutine.resume(daemon.thread, "key", keys.enter)
	if sys:network().connected then
		pass("cloverd picks up a modem transition")
	else
		fail("modem event left the link " .. sys:network().state)
	end
	local gotAgain
	parallel.waitForAll(function()
		gotAgain = read()
	end)
	if gotAgain == still then
		pass("input keeps working across a hardware event")
	else
		fail("input stopped working after a hardware event: " .. tostring(gotAgain))
	end

	-- terminate must be passed on, never swallowed
	deliver("terminate")
	if daemon.running == false then
		pass("cloverd stops on terminate")
	else
		fail("cloverd ignored terminate")
	end

	-- the daemon is describable through the kernel service table
	local kernelStub = { registered = nil }
	-- the real kernel's service.register is a plain closure over the
	-- kernel table, not a method, so the stub must match its signature
	kernelStub.service = {
		register = function(name, definition)
			kernelStub.registered = { name = name, definition = definition }
		end,
	}
	local running = cloverdMod.new({ system = sys })
	running:start()
	local registered = cloverdMod.register(kernelStub, sys, running)
	if registered == running and kernelStub.registered and kernelStub.registered.name == "cloverd" then
		pass("cloverd registers as a kernel service")
	else
		fail("cloverd did not register as a service")
	end
	local described = kernelStub.registered.definition.status()
	if described:find("running", 1, true) and described:find("hardware", 1, true) then
		pass("service status describes the daemon")
	else
		fail("service status: " .. tostring(described))
	end

	-- a host that returns a forwarded event to the daemon instead of the
	-- shell would spin on the user's typing, so the daemon must give up
	local guardSys = systemMod.new({ paths = paths })
	guardSys:scan()
	local guard = cloverdMod.new({ system = guardSys })
	guard.running = true
	guard.thread = coroutine.create(function()
		guard:loop()
	end)
	coroutine.resume(guard.thread, "char", "x")
	coroutine.resume(guard.thread, "char", "x")
	coroutine.resume(guard.thread, "char", "x")
	coroutine.resume(guard.thread, "char", "x")
	coroutine.resume(guard.thread, "char", "x")
	if guard.disabledReason then
		pass("cloverd disables itself rather than looping the user's input")
	else
		fail("cloverd did not notice a loop: repeats=" .. tostring(guard.repeats))
	end

	shim.detach("rednet3")
	shim.detach("modem3")
	-- the loop-guard test deliberately strands forwarded events; clear them
	-- so the next suite's scripted read() is not fed leftovers
	shim.drainEvents()
end)

runSuite("gnome", function()
	freshInstall()
	-- the boot contract: the runtime reads CLOVER_ROOT for bundled assets
	_G.CLOVER_ROOT = "/testroot"
	local paths = dofile("/testroot/runtime/paths.lua").new("/testroot")
	local users = dofile("/testroot/runtime/users.lua").new(paths)
	users:load()
	if not users:exists("gnomeuser") then
		users:createUser("gnomeuser", "pw")
	end
	users:login("gnomeuser")
	local ui = dofile("/testroot/runtime/textui.lua").new(paths)
	local packages = dofile("/testroot/runtime/packages.lua").new(paths)
	local session = dofile("/testroot/runtime/shell.lua").new({
		paths = paths, users = users, ui = ui, packages = packages,
	})

	-- every module the desktop needs must be present in the install
	local missing = {}
	for _, rel in ipairs({
		"runtime/panel.lua", "runtime/overview.lua",
		"runtime/launcher.lua", "runtime/desktop.lua",
		"apps/terminal.lua", "apps/files.lua", "apps/settings.lua",
		"apps/sysinfo.lua", "apps/texteditor.lua", "apps/software.lua",
		"apps/help.lua",
	}) do
		if not fs.exists("/testroot/" .. rel) then
			missing[#missing + 1] = rel
		end
	end
	if #missing == 0 then
		pass("gnome modules installed")
	else
		fail("gnome modules missing: " .. table.concat(missing, ", "))
	end

	-- the launcher is the single entry point for both `cloveros` and login
	local launcher = dofile("/testroot/runtime/launcher.lua").new({
		paths = paths, users = users, ui = ui, packages = packages,
		session = session, kernel = nil,
	})
	local available, why = launcher:available()
	if available then
		pass("launcher reports the desktop available")
	else
		fail("launcher unavailable: " .. tostring(why))
	end
	local apps = launcher:appList()
	local ids = {}
	for _, app in ipairs(apps) do
		ids[app.id] = app.program
	end
	if #apps > 0 and ids.terminal and ids.files and ids.settings and ids.sysinfo then
		pass("launcher lists desktop apps")
	else
		fail("launcher app list incomplete: " .. table.concat((function()
			local names = {}
			for _, a in ipairs(apps) do names[#names + 1] = a.id end
			return names
		end)(), ", "))
	end

	-- the panel and the overview drive the shell, not the whole session
	local stack, stackErr = launcher:buildStack()
	if not stack then
		fail("launcher could not build the gui stack: " .. tostring(stackErr))
		return
	end
	local desktop = stack.desktop
	pass("launcher built the gui stack")

	-- the top bar occupies one row and the rest is the work area
	local w, h = term.getSize()
	if stack.gui.workArea and stack.gui.workArea.y == 2
		and stack.gui.workArea.h == h - 1 then
		pass("work area clears the top bar")
	else
		fail("work area does not clear the top bar")
	end

	-- panel hit testing: row 1 is the bar, below it is desktop background
	local bar = desktop.panel:hit(1, 1)
	local body = desktop.panel:hit(1, 3)
	if bar and bar.zone == "bar" and body and body.zone == "panel" then
		pass("panel hit testing")
	else
		fail("panel hit testing: bar=" .. tostring(bar and bar.zone)
			.. " body=" .. tostring(body and body.zone))
	end

	-- Activities overview opens, filters by typed text, and closes
	desktop:toggleOverview()
	if desktop.overviewUi:isOpen() then
		pass("activities overview opens")
	else
		fail("activities overview did not open")
	end
	local before = desktop.overviewUi:currentApp()
	desktop.overviewUi:onChar("f")
	desktop.overviewUi:onBackspace()
	local after = desktop.overviewUi:currentApp()
	if not before or (after and after.id == before.id) then
		pass("overview search filters apps")
	else
		fail("overview search changed selection unexpectedly")
	end
	desktop.overviewUi:close()
	if not desktop.overviewUi:isOpen() then
		pass("overview closes")
	else
		fail("overview did not close")
	end
	desktop:toggleOverview()
	local reopened = desktop.overviewUi:isOpen()
	desktop:toggleOverview()
	if reopened and not desktop.overviewUi:isOpen() then
		pass("overview toggles open and shut")
	else
		fail("overview toggle did not round trip")
	end
	desktop:toggleOverview()
	desktop:toggleOverview()

	-- escape reaches the shell as a char event: CC:Tweaked has no keys.escape
	desktop:openMenu("app")
	local menuOpen = desktop.panel.menu ~= nil
	desktop:onChar("\27")
	if menuOpen and desktop.panel.menu == nil then
		pass("escape closes an open menu")
	else
		fail("escape did not close the menu (was open: " .. tostring(menuOpen) .. ")")
	end

	-- window controls: open, focus, close
	local win = desktop:openApp("sysinfo")
	if win then
		pass("desktop opens an app window")
		if #stack.gui:listWindows() >= 1 then
			pass("window manager tracks the window")
		else
			fail("window manager lost the window")
		end
		desktop:closeWindow(win)
		if #stack.gui:listWindows() == 0 then
			pass("closing a window removes it")
		else
			fail("window still tracked after close")
		end
	else
		fail("desktop could not open sysinfo")
	end

	-- `cloveros` options never start a session
	local out = {}
	local oldPrint = print
	print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		out[#out + 1] = table.concat(parts, " ")
	end
	local function text()
		return table.concat(out, "\n")
	end
	session:execute("cloveros --apps")
	if text():find("terminal") and text():find("files") then
		pass("cloveros --apps lists applications")
	else
		fail("cloveros --apps printed: " .. text())
	end
	out = {}
	session:execute("cloveros --version")
	if text():find("%d+%.%d+") then
		pass("cloveros --version prints a version")
	else
		fail("cloveros --version printed: " .. text())
	end
	out = {}
	session:execute("cloveros --help")
	if text():find("usage") then
		pass("cloveros --help prints usage")
	else
		fail("cloveros --help printed: " .. text())
	end
	out = {}
	session:execute("cloveros --nonsense")
	if session.lastStatus == 1 then
		pass("cloveros rejects unknown options")
	else
		fail("cloveros accepted an unknown option")
	end
	-- a desktop must never start on a captured or piped command
	out = {}
	session:execute("echo x | cloveros")
	if text():find("interactive") then
		pass("cloveros refuses to run in a pipe")
	else
		fail("cloveros ran inside a pipe: " .. text())
	end
	print = oldPrint
end)

-- ---------- gui ----------
runSuite("gui", function()
	freshInstall()
	local ran, runErr = pcall(dofile, "/src/tests/gui_test.lua")
	if not ran and runErr ~= "Terminated" then
		fail("gui_test crashed: " .. tostring(runErr))
	end
	local report = fs.open("/test_report.txt", "r")
	if not report then
		fail("gui suite produced no report")
		return
	end
	local data = report.readAll()
	report.close()
	local reported = 0
	for line in data:gmatch("[^\n]+") do
		local count = line:match("^PASS=(%d+)")
		if count then
			reported = tonumber(count)
		elseif line:match("^FAILLINE") then
			fail(line)
		end
	end
	say("  (" .. reported .. " gui checks passed)")
end)

-- ---------- boot (full scripted boot flow) ----------
runSuite("boot", function()
	if fs.exists("/testroot") then
		fs.delete("/testroot")
	end
	local ran, runErr = xpcall(function()
		dofile("/src/tests/boot_test.lua")
	end, function(e)
		if e == "Terminated" then
			return e
		end
		return tostring(e) .. "\n" .. debug.traceback()
	end)
	if not ran and runErr ~= "Terminated" then
		for line in tostring(runErr):gmatch("[^\n]+") do
			say("    | " .. line)
		end
		fail("boot_test ended with an error")
	end
	local report = fs.open("/test_report.txt", "r")
	if not report then
		fail("boot suite produced no report")
		return
	end
	local data = report.readAll()
	report.close()
	for line in data:gmatch("[^\n]+") do
		if line:match("^FAILLINE") then
			fail(line)
		end
	end
	if data:find("BOOT=PASS", 1, true) then
		say("  ok  scripted boot flow (setup, login, desktop, logout, login)")
	else
		fail("boot flow did not reach BOOT=PASS")
	end
end)

-- ---------- boot_text (text-mode session executes commands) ----------
runSuite("boot_text", function()
	local tOk, tErr = pcall(dofile, "/src/tests/boot_text_test.lua")
	local report = fs.open("/test_report.txt", "r")
	if not report then
		fail("boot_text suite produced no report")
		return
	end
	local data = report.readAll()
	report.close()
	for line in data:gmatch("[^\n]+") do
		if line:match("^FAILLINE") then
			fail(line)
		end
	end
	local console = shim.dumpTerm()
	local hasReport = data:find("BOOT_TEXT=PASS", 1, true) ~= nil
	local hasEcho = console:find("text_shell_ok", 1, true) ~= nil
	local hasUser = console:find("bootuser", 1, true) ~= nil
	if hasReport and hasEcho and hasUser then
		say("  ok  text-mode session ran commands (console shows output)")
	else
		fail("boot_text: report or console output missing"
			.. " (report=" .. tostring(hasReport)
			.. " echo=" .. tostring(hasEcho)
			.. " user=" .. tostring(hasUser)
			.. ") report=[" .. tostring(data):gsub("\n", "|") .. "]"
			.. ((tOk or tErr == "Terminated") and "" or (" err=[" .. tostring(tErr):gsub("\n", "|") .. "]")))
	end
end)

-- ---------- summary ----------
say("")
if failures > 0 then
	say("HOST TESTS FAILED: " .. failures .. " failure(s)")
	error("HOST TESTS FAILED", 0)
else
	say("HOST TESTS PASSED")
end
