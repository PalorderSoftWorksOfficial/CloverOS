-- CloverOS installer: installs CloverOS onto a CraftOS computer.
--
-- The installer is Linux-like: it builds a plan (target, filesystem layout,
-- task set, account), asks for anything missing, copies and verifies the
-- files, writes /etc/fstab and the boot loader configuration, and records
-- everything in /var/log/install.log plus /var/lib/install-status.txt.
--
-- Usage (from a clean computer, inside a repository checkout):
--   install                       guided installation
--   install /disk                 install to a mounted disk
--   install --local               install from repository files on this computer
--   install --net                 install from GitHub (requires HTTP)
--   install --local-source <root> [target]    install from an explicit source
--   install --no-prompt           unattended, with defaults
--   install disks | tasks | status | verify    installer utilities
--   install --help                full option list
local BASE = "https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/"

-- Canonical runtime file list. The installer installs exactly this list.
-- Keep in sync with the repository; tests/syntax_check.lua verifies coverage.
local FILES = {
	"startup.lua",
	"CloverOS_OS.lua",
	"boot/loader.lua",
	"boot/kernel.lua",
	"runtime/paths.lua",
	"runtime/hash.lua",
	"runtime/users.lua",
	"runtime/textui.lua",
	"runtime/system.lua",
	"runtime/packages.lua",
	"runtime/shell.lua",
	"runtime/gui.lua",
	"runtime/panel.lua",
	"runtime/overview.lua",
	"runtime/launcher.lua",
	"runtime/desktop.lua",
	"libs/mc-imgui.lua",
	"etc/version.lua",
	"etc/motd.txt",
	"bin/clear.lua",
	"bin/ls.lua",
	"bin/cat.lua",
	"bin/copy.lua",
	"bin/move.lua",
	"bin/delete.lua",
	"bin/mkdir.lua",
	"bin/grep.lua",
	"bin/head.lua",
	"bin/tail.lua",
	"bin/which.lua",
	"bin/sleep.lua",
	"bin/stat.lua",
	"bin/neofetch.lua",
	"bin/net.lua",
	"bin/ping.lua",
	"bin/wget.lua",
	"bin/gps.lua",
	"bin/rednet.lua",
	"bin/df.lua",
	"etc/packages/example/package.lua",
	"etc/packages/example/bin/hello.lua",
	"etc/packages/fortune/package.lua",
	"etc/packages/fortune/bin/fortune.lua",
	"etc/packages/moo/package.lua",
	"etc/packages/moo/bin/moo.lua",
	"etc/packages/sl/package.lua",
	"etc/packages/sl/bin/sl.lua",
}

-- Desktop applications are optional: the OS boots and stays in text mode
-- without them (the `cloveros` command simply reports them missing).
local OPTIONAL_FILES = {
	"apps/desktop.lua",
	"apps/terminal.lua",
	"apps/files.lua",
	"apps/texteditor.lua",
	"apps/software.lua",
	"apps/settings.lua",
	"apps/sysinfo.lua",
	"apps/help.lua",
}

-- man pages: local mode copies the whole etc/man directory (so new pages
-- cannot be missed); net mode fetches this explicit list because raw GitHub
-- cannot enumerate directories. Keep it in step with etc/man.
local NET_MAN_PAGES = {
	"ae2.man", "alias.man", "apt.man", "cat.man", "cd.man",
	"chmod.man", "clear.man", "cloveros.man", "cls.man", "copy.man",
	"cp.man", "date.man", "df.man", "del.man", "dmesg.man", "echo.man",
	"export.man", "gps.man", "grep.man", "groups.man", "head.man",
	"history.man", "hostname.man", "install.man", "ls.man", "man.man",
	"mkdir.man", "mv.man", "neofetch.man", "net.man", "ping.man",
	"pwd.man", "reboot.man", "rednet.man", "ren.man", "rm.man",
	"rmdir.man", "run.man", "sleep.man", "stat.man", "sudo.man",
	"tail.man", "time.man", "touch.man", "type.man", "unalias.man",
	"wget.man", "which.man", "whoami.man",
}

local DIRS = {
	"boot",
	"runtime",
	"libs",
	"bin",
	"apps",
	"etc",
	"etc/clover",
	"etc/man",
	"etc/packages",
	"etc/packages/example",
	"etc/packages/fortune",
	"etc/packages/moo",
	"etc/packages/sl",
	"home",
	"var",
	"var/lib",
	"var/lib/clover",
	"var/log",
	"tmp",
}

-- Task sets, the installer's answer to Debian's package selections. Each
-- task lists the catalog packages that belong to it.
-- Task sets mirror what a real distribution ships in the base image: the
-- core tools are already on disk, so most tasks add nothing. `example` is a
-- demonstration package and is deliberately not part of any task; install it
-- yourself with `apt install example`.
local TASKS = {
	minimal = { description = "text shell only", packages = {} },
	terminal = { description = "full shell, editors and core tools", packages = {} },
	utilities = { description = "everyday command line tools", packages = {} },
	desktop = { description = "the GNOME desktop (CloverOS)", packages = {} },
	fun = { description = "fortune, cowsay and trains", packages = { "fortune", "moo", "sl" } },
	development = { description = "development extras", packages = {} },
}

local TASK_NAMES = {}
do
	local names = {}
	for name in pairs(TASKS) do
		names[#names + 1] = name
	end
	table.sort(names)
	TASK_NAMES = names
end

-- ---------- tiny output helpers ----------
local function colorWrite(text, color)
	local old = term.getTextColor()
	term.setTextColor(color or colors.white)
	term.write(text)
	term.setTextColor(old)
end

local function line(text)
	term.write(tostring(text or "") .. "\n")
end

local function say(text)
	colorWrite(tostring(text or "") .. "\n", colors.white)
end

local function good(text)
	colorWrite(tostring(text or "") .. "\n", colors.green)
end

local function bad(text)
	colorWrite(tostring(text or "") .. "\n", colors.red)
end

local function warn(text)
	colorWrite("warning: " .. tostring(text or "") .. "\n", colors.orange)
end

local function step(number, total, text)
	local prefix = "[" .. tostring(number) .. "/" .. tostring(total) .. "] "
	colorWrite(prefix, colors.lightGray)
	term.write(tostring(text or ""))
end

local function pass()
	colorWrite("OK\n", colors.green)
end

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
		return false
	end
	h.write(data)
	h.close()
	return true
end

-- ---------- install log ----------
local logLines = {}

-- CC:Tweaked has no textutils.date (it arrived in later CC:Tweaked versions
-- and is absent from CraftOS-PC 1.9), so the log is stamped with os.date.
local function stamp()
	local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
	if ok and type(value) == "string" then
		return value
	end
	return "-"
end

local function log(text)
	logLines[#logLines + 1] = stamp() .. "  " .. tostring(text)
end

local function flushLog(target)
	local path = fs.combine(target or "/", "var/log/install.log")
	fs.makeDir(fs.getDir(path))
	writeAll(path, table.concat(logLines, "\n") .. "\n")
	return path
end

-- ---------- argument parsing ----------
local ACTIONS = { install = true, verify = true, status = true, disks = true, tasks = true }

local VALUE_OPTIONS = {
	["--local-source"] = "sourceRoot",
	["--target"] = "target",
	["--root"] = "rootMount",
	["--home"] = "homeMount",
	["--boot"] = "bootMount",
	["--taskset"] = "taskset",
	["--user"] = "user",
	["--password"] = "password",
	["--hostname"] = "hostname",
	["--lang"] = "lang",
	["--session"] = "session",
	["--type"] = "type",
}

local options = {
	action = "install",
	target = nil,
	sourceRoot = nil,
	mode = "local",
	type = nil,
	taskset = nil,
	user = nil,
	password = nil,
	hostname = nil,
	lang = nil,
	session = nil,
	noPrompt = false,
	force = false,
	dryRun = false,
	eraseData = false,
	quiet = false,
	showHelp = false,
	showVersion = false,
}

local function parseArgs(argv)
	local index = 1
	while index <= #argv do
		local arg = tostring(argv[index])
		if ACTIONS[arg] and not options.target then
			options.action = arg
		elseif VALUE_OPTIONS[arg] then
			options[VALUE_OPTIONS[arg]] = argv[index + 1]
			index = index + 1
		elseif arg == "--local" then
			options.mode = "local"
		elseif arg == "--net" then
			options.mode = "net"
		elseif arg == "--no-prompt" or arg == "-y" then
			options.noPrompt = true
		elseif arg == "--force" then
			options.force = true
		elseif arg == "--dry-run" then
			options.dryRun = true
		elseif arg == "--erase-data" then
			options.eraseData = true
		elseif arg == "--quiet" or arg == "-q" then
			options.quiet = true
		elseif arg == "--help" or arg == "-h" then
			options.showHelp = true
		elseif arg == "--version" or arg == "-V" then
			options.showVersion = true
		elseif arg:sub(1, 2) == "--" then
			return nil, "unknown option " .. arg
		elseif not options.target then
			options.target = arg
		end
		index = index + 1
	end
	return options
end

local function usage()
	line("CloverOS installer")
	line("")
	line("usage: install [options] [target]")
	line("")
	line("actions:")
	line("  (default)        guided installation")
	line("  verify           check installed files against the sha256 manifest")
	line("  status           print what is installed")
	line("  disks            list installation targets")
	line("  tasks            list available task sets")
	line("")
	line("options:")
	line("  --local          install from repository files on this computer")
	line("  --net            install from GitHub (requires HTTP)")
	line("  --local-source <root>   install from an explicit repository root")
	line("  --target <path>  install target (default: /)")
	line("  --type erase|alongside|manual")
	line("  --root <path>    manual layout: root mount point")
	line("  --home <path>    manual layout: home mount point")
	line("  --boot <path>    manual layout: boot mount point")
	line("  --erase-data     allow the installer to erase existing data")
	line("  --taskset <list> comma separated task sets")
	line("  --user <name>    initial account")
	line("  --password <pw>  initial account password (unattended only)")
	line("  --hostname <name> system hostname")
	line("  --lang <code>    locale, e.g. en-US")
	line("  --session <name> gnome (default) or text")
	line("  --dry-run        show the plan without writing anything")
	line("  --no-prompt      never ask; use defaults")
	line("  --force          do not ask for confirmation")
	line("  --quiet          less output")
end

-- ---------- source discovery ----------
local function localSource()
	-- The repository checkout itself is the local source when running from it.
	-- A read-only mounted checkout (e.g. /src in the test harness) also counts.
	if fs.exists("/src/startup.lua") and fs.exists("/src/boot/kernel.lua") and fs.exists("/src/runtime/shell.lua") then
		return "/src"
	end
	if fs.exists("startup.lua") and fs.exists("boot/kernel.lua") and fs.exists("runtime/shell.lua") then
		return "/"
	end
	for i = 0, 99 do
		local root = "/disk" .. (i == 0 and "" or i)
		if fs.exists(fs.combine(root, "startup.lua")) and fs.exists(fs.combine(root, "boot/kernel.lua")) then
			return root
		end
	end
	return nil
end

local function sourceRoot()
	if options.sourceRoot then
		return options.sourceRoot
	end
	return localSource()
end

local function fetch(relPath)
	local url = BASE .. relPath
	local res = http.get(url)
	if not res then
		return nil, "download failed: " .. url
	end
	local code = res.getResponseCode and res.getResponseCode() or 200
	if code ~= 200 then
		res.close()
		return nil, "HTTP " .. code .. " for " .. url
	end
	local data = res.readAll()
	res.close()
	return data
end

-- bytes of a repository file, from disk or over HTTP
local function sourceBytes(relPath)
	if options.mode == "net" then
		return fetch(relPath)
	end
	local root = sourceRoot()
	if not root then
		return nil, "no local repository"
	end
	return readAll(fs.combine(root, relPath))
end

-- ---------- filesystem layout ----------
local function listDisks()
	local disks = { { name = "root filesystem", path = "/", free = fs.getSize("/") } }
	local ok, names = pcall(fs.list, "/")
	if ok and type(names) == "table" then
		for _, name in ipairs(names) do
			if name:sub(1, 4) == "disk" then
				local path = "/" .. name
				disks[#disks + 1] = {
					name = name,
					path = path,
					free = (fs.isDir(path) and fs.getSize(path) or 0),
				}
			end
		end
	end
	return disks
end

local function defaultHostname()
	local label = os.getComputerLabel()
	if label and label ~= "" then
		return (label:gsub("[^%w%-]", "-"):lower())
	end
	return "clover-" .. tostring(os.getComputerID())
end

-- ---------- prompting ----------
local function ask(label, default)
	if options.noPrompt then
		return default
	end
	term.write(label)
	if default ~= nil and default ~= "" then
		term.write(" [" .. tostring(default) .. "] ")
	else
		term.write(" ")
	end
	local answer = read()
	if answer == nil then
		return default
	end
	answer = answer:gsub("^%s+", ""):gsub("%s+$", "")
	if answer == "" then
		return default
	end
	return answer
end

local function askChoice(label, choices, defaultIndex)
	if options.noPrompt then
		return defaultIndex
	end
	line("")
	line(label)
	for i, choice in ipairs(choices) do
		line("  " .. i .. ") " .. tostring(choice))
	end
	local answer = tonumber(ask("Choice", tostring(defaultIndex)))
	if not answer or answer < 1 or answer > #choices then
		return defaultIndex
	end
	return answer
end

local function confirm(label, defaultYes)
	if options.noPrompt or options.force then
		return true
	end
	local answer = tostring(ask(label .. (defaultYes and " [Y/n] " or " [y/N] "), ""))
	local first = answer:lower():sub(1, 1)
	if first == "" then
		return defaultYes
	end
	return first == "y"
end

-- ---------- plan ----------
local function parseTaskList(text)
	local tasks = {}
	if not text or text == "" then
		return tasks
	end
	for name in tostring(text):gmatch("[^,]+") do
		name = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if name ~= "" then
			if not TASKS[name] then
				return nil, "unknown task: " .. name
			end
			tasks[#tasks + 1] = name
		end
	end
	return tasks
end

local function taskPackages(tasks)
	local list, seen = {}, {}
	for _, task in ipairs(tasks) do
		local definition = TASKS[task]
		for _, pkg in ipairs(definition and definition.packages or {}) do
			if not seen[pkg] then
				seen[pkg] = true
				list[#list + 1] = pkg
			end
		end
	end
	return list
end

local function buildPlan()
	local plan = {
		target = options.target or "/",
		mode = options.mode,
		type = options.type,
		tasks = {},
		mounts = {},
		hostname = options.hostname,
		lang = options.lang or "en-US",
		session = options.session or "gnome",
		user = options.user,
		password = options.password,
		erase = options.eraseData,
		dryRun = options.dryRun,
	}

	if plan.type and plan.type ~= "erase" and plan.type ~= "alongside" and plan.type ~= "manual" then
		return nil, "unknown installation type: " .. tostring(plan.type)
	end

	-- installation type: never destructive unless explicitly requested
	if not plan.type then
		if options.noPrompt then
			plan.type = "alongside"
		else
			local choice = askChoice("How should CloverOS use this drive?", {
				"Install alongside existing data (keeps your files)",
				"Erase the target and install (removes existing data)",
				"Manual layout (choose the mount points yourself)",
			}, 1)
			plan.type = ({ "alongside", "erase", "manual" })[choice]
		end
	end
	if plan.type == "erase" and not options.eraseData then
		-- unattended installs never destroy data without --erase-data
		if options.noPrompt then
			plan.type = "alongside"
			warn("erase requires --erase-data; keeping existing data instead")
		elseif not confirm("Erase all data on " .. tostring(plan.target) .. "?") then
			plan.type = "alongside"
		end
	end

	-- target
	if not options.target and not options.noPrompt then
		local disks = listDisks()
		if #disks > 1 then
			line("")
			line("Available targets:")
			for i, disk in ipairs(disks) do
				line("  " .. i .. ") " .. disk.name .. "  " .. disk.path ..
					"  (" .. tostring(disk.free) .. " bytes free)")
			end
			local choice = tonumber(ask("Target", "1")) or 1
			if choice < 1 or choice > #disks then
				choice = 1
			end
			plan.target = disks[choice].path
		end
	end
	plan.target = plan.target or "/"

	-- filesystem layout
	if plan.type == "manual" then
		plan.mounts["/"] = options.rootMount or ask("Root mount point", "/")
		plan.mounts["/home"] = options.homeMount or ask("Home mount point (blank to share)", "/home")
		plan.mounts["/boot"] = options.bootMount or ask("Boot mount point (blank for none)", "/boot")
	else
		plan.mounts["/"] = plan.target
		plan.mounts["/home"] = fs.combine(plan.target, "home")
		plan.mounts["/boot"] = fs.combine(plan.target, "boot")
	end

	-- task sets
	local taskset = options.taskset
	if not taskset then
		if options.noPrompt then
			taskset = "terminal,utilities"
		else
			line("")
			line("Task sets:")
			for _, name in ipairs(TASK_NAMES) do
				line("  " .. name .. " - " .. TASKS[name].description)
			end
			taskset = ask("Tasks to install (comma separated)", "terminal")
		end
	end
	local tasks, err = parseTaskList(taskset)
	if not tasks then
		return nil, err
	end
	plan.tasks = tasks

	-- account
	plan.hostname = plan.hostname or ask("Hostname", defaultHostname())
	if not plan.user and not options.noPrompt then
		line("")
		line("Create the first account (administrator).")
		plan.user = ask("Username", os.getComputerLabel() or "clover")
	end
	if not plan.user and options.noPrompt then
		plan.user = nil -- the OS runs first-run setup on first boot
	end
	if plan.user and not plan.password and not options.noPrompt then
		write("Password: ")
		plan.password = read("*") or ""
		write("Confirm:  ")
		local again = read("*") or ""
		if plan.password ~= again then
			plan.password = nil
			warn("passwords did not match; the account will be set up on first boot")
		end
	end

	plan.packages = taskPackages(plan.tasks)
	return plan
end

local function planSummary(plan)
	local lines = {
		"target:        " .. plan.target,
		"source:        " .. plan.mode,
		"type:          " .. plan.type .. (plan.erase and " (erase)" or ""),
		"hostname:      " .. tostring(plan.hostname),
		"language:      " .. plan.lang,
		"session:       " .. plan.session,
		"tasks:         " .. (plan.tasks[1] and table.concat(plan.tasks, ", ") or "none"),
		"packages:      " .. (plan.packages[1] and table.concat(plan.packages, ", ") or "none"),
		"account:       " .. (plan.user and (plan.user .. " (administrator)") or "created on first boot"),
	}
	for _, mount in ipairs({ "/", "/home", "/boot" }) do
		if plan.mounts[mount] then
			lines[#lines + 1] = "mount " .. string.format("%-6s", mount) .. plan.mounts[mount]
		end
	end
	return lines
end

-- ---------- system configuration ----------
local function fstabText(plan)
	local rows = {
		"# CloverOS filesystem table",
		"# device        mountpoint  type   options        dump  pass",
	}
	local pass = 1
	local function row(device, mount, kind, order)
		rows[#rows + 1] = string.format("%-14s %-12s %-6s %-14s %-5d %d",
			device, mount, kind, "defaults", 0, order)
		pass = pass + 1
	end
	row(plan.mounts["/"] or plan.target, "/", "cloverfs", pass)
	if plan.mounts["/home"] then
		row(plan.mounts["/home"], "/home", "cloverfs", pass)
	end
	if plan.mounts["/boot"] then
		row(plan.mounts["/boot"], "/boot", "cloverfs", pass)
	end
	rows[#rows + 1] = string.format("%-14s %-12s %-6s %-14s %-5d %d", "none", "none", "swap", "sw", 0, 0)
	return table.concat(rows, "\n") .. "\n"
end

local function writeSystemConfig(plan, results)
	local target = plan.target
	local written = 0
	local function write(relative, data)
		if writeAll(fs.combine(target, relative), data) then
			written = written + 1
			log("config " .. relative)
		else
			results.failed[#results.failed + 1] = relative
		end
	end

	write("etc/fstab", fstabText(plan))
	write("etc/clover/mounts.cfg", textutils.serialize({
		root = plan.mounts["/"] or plan.target,
		home = plan.mounts["/home"],
		boot = plan.mounts["/boot"],
		type = plan.type,
		erase = plan.erase and true or false,
	}))
	write("etc/clover/install.cfg", textutils.serialize({
		version = plan.version or "2.1.0",
		installed = os.epoch("utc"),
		type = plan.type,
		tasks = plan.tasks,
		source = plan.mode,
		hostname = plan.hostname,
		lang = plan.lang,
		session = plan.session,
		user = plan.user,
	}))
	-- boot loader: CloverOS boots straight into the chosen session
	write("var/lib/clover/loader.cfg", textutils.serialize({
		timeout = 5,
		entry = "CloverOS",
		session = plan.session,
		quiet = false,
	}))
	-- the graphical session is the default one after installation
	write("var/lib/clover/settings.cfg", textutils.serialize({
		gui = plan.session ~= "text",
		session = plan.session,
	}))

	-- the first account, when one was given on the command line
	if plan.user and plan.password then
		local userOk, usersModule = pcall(dofile, fs.combine(target, "runtime/users.lua"))
		local pathsOk, pathsModule = pcall(dofile, fs.combine(target, "runtime/paths.lua"))
		if userOk and pathsOk and type(usersModule) == "table" then
			local users = usersModule.new(pathsModule.new(target))
			users:load()
			if not users:exists(plan.user) then
				users:createUser(plan.user, plan.password)
			else
				users:setPassword(plan.user, plan.password)
			end
			users:save()
			log("account " .. plan.user)
			written = written + 1
		else
			warn("could not create '" .. plan.user .. "'; first-run setup will ask")
		end
	end
	return written
end

-- ---------- file copy + verification ----------
local function copyAndVerify(target, rel, data)
	local dst = fs.combine(target, rel)
	fs.makeDir(fs.getDir(dst))
	local h = fs.open(dst, "w")
	if not h then
		return false, "cannot write " .. rel
	end
	h.write(data)
	h.close()
	local back = readAll(dst)
	if back ~= data then
		return false, "verification failed for " .. rel
	end
	return true
end

local function installFiles(plan, results)
	local root = sourceRoot()
	if plan.mode == "local" and not root then
		return 0, { "no local repository found" }
	end

	local total = #FILES
	for i, rel in ipairs(FILES) do
		step(i, total, rel .. " ... ")
		local data, err = sourceBytes(rel)
		if not data then
			bad("FAIL (" .. tostring(err) .. ")")
			results.failed[#results.failed + 1] = rel
		else
			local okWrite, writeErr = copyAndVerify(plan.target, rel, data)
			if okWrite then
				pass()
				results.installed = results.installed + 1
				results.verified = results.verified + 1
				results.manifest[#results.manifest + 1] = rel
			else
				bad("FAIL (" .. tostring(writeErr) .. ")")
				results.failed[#results.failed + 1] = rel
			end
		end
	end

	-- man pages: local mode copies the whole source directory so new pages
	-- cannot drift out of a file list; net mode uses the explicit list.
	if plan.mode == "local" and root then
		local manSrc = fs.combine(root, "etc/man")
		if fs.isDir(manSrc) then
			for _, name in ipairs(fs.list(manSrc)) do
				local rel = "etc/man/" .. name
				local data = readAll(fs.combine(manSrc, name))
				if data and copyAndVerify(plan.target, rel, data) then
					results.installed = results.installed + 1
					results.verified = results.verified + 1
					results.manifest[#results.manifest + 1] = rel
				end
			end
		end
	else
		for _, name in ipairs(NET_MAN_PAGES) do
			local rel = "etc/man/" .. name
			local data = fetch(rel)
			if data and copyAndVerify(plan.target, rel, data) then
				results.installed = results.installed + 1
				results.verified = results.verified + 1
				results.manifest[#results.manifest + 1] = rel
			else
				results.failed[#results.failed + 1] = rel
			end
		end
	end

	-- desktop applications: a missing one only costs a grid entry
	for _, rel in ipairs(OPTIONAL_FILES) do
		local data = sourceBytes(rel)
		if data and copyAndVerify(plan.target, rel, data) then
			results.installed = results.installed + 1
			results.verified = results.verified + 1
			results.apps = results.apps + 1
			results.manifest[#results.manifest + 1] = rel
		end
	end
	return results.installed
end

-- ---------- sha256 manifest ----------
-- runtime/hash.lua is loaded once per run, not once per file: on a host
-- without the native `hash` API the portable digest is the expensive part.
local manifestHash

local function loadManifestHash(root)
	if manifestHash ~= nil then
		return manifestHash or nil
	end
	local ok, hash = pcall(dofile, fs.combine(root, "runtime/hash.lua"))
	manifestHash = (ok and type(hash) == "table" and type(hash.sha256hex) == "function") and hash or false
	return manifestHash or nil
end

local function sha256OfFile(root, path)
	local hash = loadManifestHash(root)
	if not hash then
		return nil
	end
	local data = readAll(path)
	if not data then
		return nil
	end
	return hash.sha256hex(data)
end

local function writeManifest(plan, results)
	local lines = { "# CloverOS installation manifest (sha256  path)" }
	local hashed = 0
	for _, rel in ipairs(results.manifest) do
		local digest = sha256OfFile(plan.target, fs.combine(plan.target, rel))
		if digest then
			lines[#lines + 1] = digest .. "  " .. rel
			hashed = hashed + 1
		end
	end
	if hashed == 0 then
		return 0
	end
	writeAll(fs.combine(plan.target, "var/lib/install-manifest.sha256"), table.concat(lines, "\n") .. "\n")
	return hashed
end

-- ---------- task packages ----------
local function installTaskPackages(plan, results)
	if not plan.packages or #plan.packages == 0 then
		return 0
	end
	local pathsOk, pathsModule = pcall(dofile, fs.combine(plan.target, "runtime/paths.lua"))
	local pkgOk, pkgModule = pcall(dofile, fs.combine(plan.target, "runtime/packages.lua"))
	if not (pathsOk and pkgOk) then
		warn("package manager unavailable; skipping " .. table.concat(plan.packages, ", "))
		return 0
	end
	local installed = 0
	local packages = pkgModule.new(pathsModule.new(plan.target))
	for _, name in ipairs(plan.packages) do
		local ok, err = pcall(packages.install, packages, name)
		if ok and err then
			installed = installed + 1
			log("package installed " .. name)
			say("  package " .. name .. " installed")
		else
			warn("package " .. name .. " was not installed: " .. tostring(err))
			log("package failed " .. name .. ": " .. tostring(err))
		end
	end
	return installed
end

-- ---------- status ----------
local function writeStatus(plan, results)
	local lines = {}
	if #results.failed == 0 then
		lines[#lines + 1] = "OK"
	else
		lines[#lines + 1] = "INCOMPLETE " .. #results.failed
		for _, path in ipairs(results.failed) do
			lines[#lines + 1] = "FAILED " .. path
		end
	end
	lines[#lines + 1] = "version " .. tostring(plan.version or "2.1.0")
	lines[#lines + 1] = "target " .. tostring(plan.target)
	lines[#lines + 1] = "type " .. tostring(plan.type)
	lines[#lines + 1] = "session " .. tostring(plan.session)
	lines[#lines + 1] = "hostname " .. tostring(plan.hostname)
	lines[#lines + 1] = "files " .. tostring(results.installed)
	lines[#lines + 1] = "verified " .. tostring(results.verified)
	lines[#lines + 1] = "apps " .. tostring(results.apps)
	lines[#lines + 1] = "packages " .. tostring(results.packages or 0)
	lines[#lines + 1] = "installed " .. tostring(os.epoch("utc"))
	writeAll(fs.combine(plan.target, "var/lib/install-status.txt"), table.concat(lines, "\n") .. "\n")
end

-- ---------- installer utilities ----------
local function actionDisks()
	say("installation targets:")
	for _, disk in ipairs(listDisks()) do
		say(string.format("  %-16s %-10s %s bytes free", disk.name, disk.path, tostring(disk.free)))
	end
end

local function actionTasks()
	say("task sets:")
	for _, name in ipairs(TASK_NAMES) do
		local definition = TASKS[name]
		local packages = table.concat(definition.packages, ", ")
		say(string.format("  %-12s %-42s %s", name, definition.description,
			packages ~= "" and packages or "(no extra packages)"))
	end
end

local function actionStatus(target)
	local data = readAll(fs.combine(target, "var/lib/install-status.txt"))
	if not data then
		bad("no CloverOS installation found on " .. tostring(target))
		return 1
	end
	say(data)
	return 0
end

local function actionVerify(target)
	local data = readAll(fs.combine(target, "var/lib/install-manifest.sha256"))
	if not data then
		bad("no manifest; run the installer again to create one")
		return 1
	end
	local checked, broken = 0, 0
	for row in data:gmatch("[^\n]+") do
		local digest, rel = row:match("^(%x+)%s+(.+)$")
		if digest and rel then
			local actual = sha256OfFile(target, fs.combine(target, rel))
			checked = checked + 1
			if actual ~= digest then
				bad("FAILED " .. rel)
				broken = broken + 1
			end
		end
	end
	if broken == 0 then
		good("verified " .. checked .. " files; no problems found")
		return 0
	end
	bad("verified " .. checked .. " files; " .. broken .. " FAILED")
	return 1
end

-- ---------- main ----------
local argv = { ... }
local opts, parseErr = parseArgs(argv)

if opts and opts.showHelp then
	usage()
	return
elseif opts and opts.showVersion then
	local okVersion, version = pcall(dofile, "etc/version.lua")
	if okVersion and type(version) == "table" and version.version then
		say("CloverOS installer for " .. version.name .. " " .. version.version())
	else
		say("CloverOS installer")
	end
	return
elseif parseErr then
	bad(parseErr)
	usage()
	return
end

if opts.mode == "net" and not http then
	bad("HTTP is disabled on this computer.")
	bad("Enable http in the CraftOS config, or run: install --local")
	return
end

if opts.action == "disks" then
	actionDisks()
	return
elseif opts.action == "tasks" then
	actionTasks()
	return
elseif opts.action == "status" then
	actionStatus(opts.target or "/")
	return
elseif opts.action == "verify" then
	if actionVerify(opts.target or "/") == 1 then
		bad("installation verification failed")
	end
	return
end

term.clear()
term.setCursorPos(1, 1)
say("CloverOS Installer")
say("This program installs CloverOS onto this computer.")
say("")

log("installer started (mode=" .. opts.mode .. ")")
local plan, planErr = buildPlan()
if not plan then
	bad(planErr or "cannot build an installation plan")
	return
end

-- version string for the status file
pcall(function()
	local version = dofile(fs.combine(sourceRoot() or ".", "etc/version.lua"))
	if type(version) == "table" and version.version then
		plan.version = version.version()
	end
end)

say("Installation plan:")
for _, row in ipairs(planSummary(plan)) do
	say("  " .. row)
end
say("")

if not confirm("Write the changes above?") then
	say("Installation cancelled; nothing was changed.")
	log("cancelled by the operator")
	return
end

if plan.dryRun then
	good("Dry run: no files were written.")
	log("dry run complete")
	return
end

for _, dir in ipairs(DIRS) do
	fs.makeDir(fs.combine(plan.target, dir))
end

if plan.erase and plan.type == "erase" then
	-- only reachable with --erase-data (guarded in buildPlan)
	local victim = fs.combine(plan.target, "home")
	if fs.isDir(victim) then
		for _, entry in ipairs(fs.list(victim)) do
			local path = fs.combine(victim, entry)
			if fs.isDir(path) then
				fs.delete(path)
			else
				fs.delete(path)
			end
		end
		log("erased " .. victim)
		say("Erased existing data in " .. victim)
	end
end

local results = { installed = 0, verified = 0, apps = 0, failed = {}, manifest = {} }
log("target=" .. plan.target .. " type=" .. plan.type)
installFiles(plan, results)

local configWritten = writeSystemConfig(plan, results)
local hashed = writeManifest(plan, results)
local packages = installTaskPackages(plan, results)
results.packages = packages
writeStatus(plan, results)
log("installed " .. results.installed .. " files, " .. results.verified .. " verified")
flushLog(plan.target)

say("")
if #results.failed == 0 then
	good("Installed and verified " .. results.installed .. " files.")
	say("  configuration files: " .. configWritten)
	say("  sha256 manifest:    " .. hashed .. " files")
	say("  desktop apps:       " .. results.apps)
	say("  packages:           " .. packages)
	if not fs.exists(fs.combine(plan.target, "startup.lua")) then
		bad("startup.lua missing after install; the installation is incomplete.")
		return
	end
	good("CloverOS will start automatically on the next boot.")
	log("installation complete")
	if not options.noPrompt and confirm("Reboot now?") then
		os.reboot()
	end
else
	bad("Installed " .. results.installed .. " files; " .. #results.failed .. " FAILED:")
	for _, path in ipairs(results.failed) do
		bad("  - " .. path)
	end
	bad("The installation is INCOMPLETE. Fix the errors above and run install again.")
	log("installation incomplete")
end
