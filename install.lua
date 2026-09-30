local BASE = "https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/"
local CDN_BASE = "https://endpoint.palorderhosting.net/"
local MANIFEST_NAME = "files.manifest"
local MAX_CONCURRENT = 16
local VERSION_FALLBACK = "3.0.0"

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
	"runtime/access.lua",
	"runtime/cloverd.lua",
	"runtime/init.lua",
	"runtime/cron.lua",
	"runtime/ssh.lua",
	"runtime/theme.lua",
	"runtime/notifications.lua",
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
	"etc/apt/sources.list",
	"etc/clover/crontab",
	"etc/clover/wallpapers/ubuntu.nfp",
	"etc/clover/wallpapers/aubergine.nfp",
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
	"bin/ssh.lua",
	"bin/aptserver.lua",
	"bin/monitor.lua",
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

local OPTIONAL_FILES = {
	"apps/desktop.lua",
	"apps/terminal.lua",
	"apps/files.lua",
	"apps/texteditor.lua",
	"apps/software.lua",
	"apps/settings.lua",
	"apps/sysinfo.lua",
	"apps/imageviewer.lua",
	"apps/clocks.lua",
	"apps/media.lua",
	"apps/calculator.lua",
	"apps/sysmon.lua",
	"apps/notes.lua",
	"apps/help.lua",
}

local NET_MAN_PAGES = {
	"ae2.man", "alias.man", "apt.man", "aptserver.man", "cat.man", "cd.man",
	"chmod.man", "clear.man", "cloveros.man", "cls.man", "copy.man",
	"cp.man", "date.man", "df.man", "del.man", "dmesg.man", "echo.man",
	"export.man", "gps.man", "grep.man", "groups.man", "head.man",
	"history.man", "hostname.man", "install.man", "journalctl.man", "ls.man",
	"man.man", "mkdir.man", "mv.man", "neofetch.man", "net.man", "ping.man",
	"pwd.man", "reboot.man", "rednet.man", "ren.man", "rm.man",
	"rmdir.man", "run.man", "sleep.man", "ssh.man", "stat.man", "sudo.man",
	"systemctl.man", "tail.man", "time.man", "touch.man", "type.man",
	"unalias.man", "wget.man", "which.man", "whoami.man",
}

local DIRS = {
	"boot",
	"runtime",
	"libs",
	"bin",
	"apps",
	"etc",
	"etc/clover",
	"etc/clover/wallpapers",
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

local TURTLE_PACKAGE_FILES = {
	"etc/apt/packages/rturtle/package.json",
	"etc/apt/packages/rturtle/rturtle.exe",
	"etc/apt/packages/rturtle/turtlelib.exe",
	"etc/apt/packages/rturtle/d1.lua",
	"etc/apt/packages/autominer/package.json",
	"etc/apt/packages/autominer/autominer.exe",
}

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

local ogTerm = term.current()
local termX, termY = 51, 19
if ogTerm and type(ogTerm.getSize) == "function" then
	local ok, w, h = pcall(ogTerm.getSize)
	if ok and type(w) == "number" and type(h) == "number" then
		termX, termY = w, h
	end
end
local bufferWindow
if window and type(window.create) == "function" and ogTerm then
	bufferWindow = window.create(ogTerm, 1, 1, termX, termY)
end

local function truncate(text, width)
	text = tostring(text or "")
	width = tonumber(width) or termX
	if width < 1 then
		width = 1
	end
	return text:sub(1, width)
end

local menuMode = false

local function menuSetup()
	if not bufferWindow then
		return
	end
	if type(bufferWindow.setVisible) == "function" then
		bufferWindow.setVisible(false)
	end
	term.redirect(bufferWindow)
	term.clear()
	term.setCursorPos(1, 1)
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
end

local function menuRedraw()
	if menuMode and bufferWindow then
		if type(bufferWindow.setVisible) == "function" then
			bufferWindow.setVisible(true)
		end
		term.redirect(ogTerm)
	end
end

local function wrapLine(text, width)
	local words = {}
	for word in tostring(text or ""):gmatch("%S+") do
		words[#words + 1] = word
	end
	local lines, current = {}, ""
	for _, word in ipairs(words) do
		if current == "" then
			current = word
		elseif #current + 1 + #word <= width then
			current = current .. " " .. word
		else
			lines[#lines + 1] = current
			current = word
		end
	end
	if current ~= "" or #lines == 0 then
		lines[#lines + 1] = current
	end
	return lines
end

local function say(text)
	if bufferWindow then
		menuRedraw()
	end
	for _, row in ipairs(wrapLine(text, termX)) do
		print(truncate(row, termX))
	end
end

local function good(text)
	if bufferWindow then
		menuRedraw()
	end
	term.setTextColor(colors.lime)
	for _, row in ipairs(wrapLine(text, termX)) do
		print(truncate(row, termX))
	end
	term.setTextColor(colors.white)
end

local function bad(text)
	if bufferWindow then
		menuRedraw()
	end
	term.setTextColor(colors.red)
	for _, row in ipairs(wrapLine(text, termX)) do
		print(truncate(row, termX))
	end
	term.setTextColor(colors.white)
end

local function warn(text)
	if bufferWindow then
		menuRedraw()
	end
	term.setTextColor(colors.orange)
	for _, row in ipairs(wrapLine("warning: " .. tostring(text), termX)) do
		print(truncate(row, termX))
	end
	term.setTextColor(colors.white)
end

local function step(number, total, text)
	if bufferWindow then
		menuRedraw()
	end
	local prefix = "[" .. tostring(number) .. "/" .. tostring(total) .. "] "
	term.write(prefix .. truncate(text, termX - #prefix))
end

local function pass()
	if bufferWindow then
		menuRedraw()
	end
	print("OK")
end

local function menuOptions(title, choices, actions)
	local check = true
	local nSelection = 1
	menuMode = true
	repeat
		if bufferWindow then
			menuSetup()
		else
			term.clear()
			term.setCursorPos(1, 1)
			term.setBackgroundColor(colors.black)
			term.setTextColor(colors.white)
		end
		local w, height = termX, termY
		if bufferWindow and type(term.getSize) == "function" then
			local okSize, sw, sh = pcall(term.getSize)
			if okSize and type(sw) == "number" and type(sh) == "number" then
				w, height = sw, sh
			end
		end
		if paintutils and type(paintutils.drawLine) == "function" then
			paintutils.drawLine(1, 1, w, 1, colors.gray)
		else
			term.setBackgroundColor(colors.gray)
			term.setCursorPos(1, 1)
			term.write(string.rep(" ", w))
		end
		term.setCursorPos(1, 1)
		term.setBackgroundColor(colors.gray)
		term.setTextColor(colors.white)
		term.write(truncate(title, w))
		term.setBackgroundColor(colors.black)
		for nLine = 1, #choices do
			local row = (nLine == nSelection and "> " or "  ") .. tostring(choices[nLine])
			term.setCursorPos(1, 2 + nLine)
			if nLine == nSelection then
				term.setTextColor(colors.lightGray)
			else
				term.setTextColor(colors.white)
			end
			term.write(truncate(row, w))
		end
		if height >= 4 then
			term.setTextColor(colors.gray)
			term.setCursorPos(1, height)
			term.write(truncate("[arrows] select   [Enter] confirm", w))
		end
		menuRedraw()
		local _, nKey = os.pullEvent("key")
		if nKey == keys.up or nKey == keys.w then
			if choices[nSelection - 1] then
				nSelection = nSelection - 1
			end
		elseif nKey == keys.down or nKey == keys.s then
			if choices[nSelection + 1] then
				nSelection = nSelection + 1
			end
		elseif nKey == keys.enter then
			if actions and actions[nSelection] then
				actions[nSelection]()
				check = false
			end
		end
	until check == false
	menuMode = false
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

local logLines = {}

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
	say("CloverOS installer")
	say("")
	say("usage: install [options] [target]")
	say("")
	say("actions:")
	say("  (default)        guided installation")
	say("  verify           check installed files against the sha256 manifest")
	say("  status           print what is installed")
	say("  disks            list installation targets")
	say("  tasks            list available task sets")
	say("")
	say("options:")
	say("  --local          install from repository files on this computer")
	say("  --net            install from GitHub (requires HTTP)")
	say("  --local-source <root>   install from an explicit repository root")
	say("  --target <path>  install target (default: /)")
	say("  --type erase|alongside|manual")
	say("  --root <path>    manual layout: root mount point")
	say("  --home <path>    manual layout: home mount point")
	say("  --boot <path>    manual layout: boot mount point")
	say("  --erase-data     allow the installer to erase existing data")
	say("  --taskset <list> comma separated task sets")
	say("  --user <name>    initial account")
	say("  --password <pw>  initial account password (unattended only)")
	say("  --hostname <name> system hostname")
	say("  --lang <code>    locale, e.g. en-US")
	say("  --session <name> gnome (default) or text")
	say("  --dry-run        show the plan without writing anything")
	say("  --no-prompt      never ask; use defaults")
	say("  --force          do not ask for confirmation")
	say("  --quiet          less output")
end

local function localSource()
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

local function fetch(relPath, baseURL)
	local url = (baseURL or BASE) .. relPath
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

local function sizeOf(path)
	local ok, value = pcall(fs.getSize, path)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

local function listDisks()
	local disks = { { name = "root filesystem", path = "/", free = sizeOf("/") } }
	local ok, names = pcall(fs.list, "/")
	if ok and type(names) == "table" then
		for _, name in ipairs(names) do
			if name:sub(1, 4) == "disk" then
				local path = "/" .. name
				disks[#disks + 1] = {
					name = name,
					path = path,
					free = sizeOf(path),
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

local function ask(label, default)
	if options.noPrompt then
		return default
	end
	if bufferWindow then
		menuRedraw()
	end
	term.write(truncate(label, termX - 8))
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

local function askSecret(label)
	if options.noPrompt then
		return nil
	end
	if bufferWindow then
		menuRedraw()
	end
	term.write(truncate(label, termX - 2))
	return read("*")
end

local function askMenu(label, choices, values, defaultIndex)
	local index = defaultIndex or 1
	if options.noPrompt then
		return values[index]
	end
	local picked = nil
	menuOptions(label, choices, {
		function()
			picked = values[index]
		end,
	})
	if picked == nil then
		picked = values[index]
	end
	return picked
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

local function chooseType(plan)
	if options.type and options.type ~= "erase" and options.type ~= "alongside" and options.type ~= "manual" then
		return nil, "unknown installation type: " .. tostring(options.type)
	end
	local chosen = options.type
	if not chosen then
		if options.noPrompt then
			chosen = "alongside"
		else
			chosen = askMenu("How should CloverOS use this drive?", {
				"Alongside existing data",
				"Erase the target",
				"Manual layout",
			}, { "alongside", "erase", "manual" }, 1)
		end
	end
	if chosen == "erase" and not options.eraseData then
		if options.noPrompt then
			chosen = "alongside"
			warn("erase requires --erase-data; keeping existing data instead")
		elseif not confirm("Erase all data on " .. tostring(plan.target) .. "?") then
			chosen = "alongside"
		end
	end
	plan.type = chosen
	return plan
end

local function chooseTarget(plan)
	if not options.target and not options.noPrompt then
		local disks = listDisks()
		if #disks > 1 then
			local labels, paths = {}, {}
			for i, disk in ipairs(disks) do
				labels[i] = disk.name .. " (" .. tostring(disk.free) .. " bytes)"
				paths[i] = disk.path
			end
			local picked = askMenu("Select target disk", labels, paths, 1)
			if picked then
				plan.target = picked
			end
		end
	end
	plan.target = plan.target or "/"
	return plan
end

local function buildPlan()
	local plan = {
		target = options.target or "/",
		mode = options.mode,
		type = nil,
		tasks = {},
		mounts = {},
		hostname = options.hostname,
		lang = options.lang or "en-US",
		session = options.session or "gnome",
		user = options.user,
		password = options.password,
		erase = options.eraseData,
		dryRun = options.dryRun,
		edition = "default",
	}

	local okType, typeErr = chooseType(plan)
	if not okType then
		return nil, typeErr
	end
	chooseTarget(plan)

	if plan.type == "manual" then
		plan.mounts["/"] = options.rootMount or ask("Root mount point", "/")
		plan.mounts["/home"] = options.homeMount or ask("Home mount point (blank to share)", "/home")
		plan.mounts["/boot"] = options.bootMount or ask("Boot mount point (blank for none)", "/boot")
	else
		plan.mounts["/"] = plan.target
		plan.mounts["/home"] = fs.combine(plan.target, "home")
		plan.mounts["/boot"] = fs.combine(plan.target, "boot")
	end

	local taskset = options.taskset
	if not taskset then
		if options.noPrompt then
			taskset = "terminal,utilities"
		else
			taskset = ask("Tasks to install (comma separated)", "terminal")
		end
	end
	local tasks, taskErr = parseTaskList(taskset)
	if not tasks then
		return nil, taskErr
	end
	plan.tasks = tasks

	plan.hostname = plan.hostname or ask("Hostname", defaultHostname())
	if not plan.user and not options.noPrompt then
		plan.user = ask("Username for the first account", os.getComputerLabel() or "clover")
	end
	if plan.user and not plan.password and not options.noPrompt then
		plan.password = askSecret("Password: ")
		local again = askSecret("Confirm:  ")
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
		"edition:       " .. plan.edition,
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

	write("etc/fstab", table.concat({
		"# CloverOS filesystem table",
		"# device        mountpoint  type   options        dump  pass",
		string.format("%-14s %-12s %-6s %-14s %-5d %d", plan.mounts["/"] or plan.target, "/", "cloverfs", "defaults", 0, 1),
		string.format("%-14s %-12s %-6s %-14s %-5d %d", plan.mounts["/home"], "/home", "cloverfs", "defaults", 0, 2),
		string.format("%-14s %-12s %-6s %-14s %-5d %d", plan.mounts["/boot"], "/boot", "cloverfs", "defaults", 0, 3),
		string.format("%-14s %-12s %-6s %-14s %-5d %d", "none", "none", "swap", "sw", 0, 0),
	}, "\n") .. "\n")

	write("etc/clover/mounts.cfg", textutils.serialize({
		root = plan.mounts["/"] or plan.target,
		home = plan.mounts["/home"],
		boot = plan.mounts["/boot"],
		type = plan.type,
		erase = plan.erase and true or false,
	}))

	write("etc/clover/install.cfg", textutils.serialize({
		version = plan.version or VERSION_FALLBACK,
		installed = os.epoch("utc"),
		type = plan.type,
		tasks = plan.tasks,
		source = plan.mode,
		edition = plan.edition,
		envType = plan.envType,
		hostname = plan.hostname,
		lang = plan.lang,
		user = plan.user,
	}))

	write("var/lib/clover/loader.cfg", textutils.serialize({
		timeout = 5,
		entry = "CloverOS",
		session = plan.session,
		quiet = false,
	}))

	write("var/lib/clover/settings.cfg", textutils.serialize({
		gui = plan.session ~= "text",
		session = plan.session,
		autoLogin = plan.autoLogin == true or nil,
		envType = plan.envType,
		edition = plan.edition,
	}))

	if plan.autoLogin == true then
		write("etc/clover/autologin", plan.user and (plan.user .. "\n") or "\n")
	end

	if plan.user then
		fs.makeDir(fs.combine(target, fs.combine("home", plan.user)))
	end

	if plan.user and plan.password then
		local userOk, usersModule = pcall(dofile, fs.combine(target, "runtime/users.lua"))
		local pathsOk, pathsModule = pcall(dofile, fs.combine(target, "runtime/paths.lua"))
		if userOk and pathsOk and type(usersModule) == "table" and type(pathsModule) == "table" then
			local okPaths, paths = pcall(function()
				return pathsModule.new(target)
			end)
			if okPaths and paths then
				local okUsers, users = pcall(function()
					local u = usersModule.new(paths)
					u:load()
					return u
				end)
				if okUsers and users then
					if not users:exists(plan.user) then
						users:createUser(plan.user, plan.password)
					else
						users:setPassword(plan.user, plan.password)
					end
					users:save()
					log("account " .. plan.user)
					written = written + 1
				end
			end
		else
			warn("could not create '" .. plan.user .. "'; first-run setup will ask")
		end
	end
	return written
end

local function writeDesktopConfig(plan)
	local okTheme, theme = pcall(dofile, fs.combine(plan.target, "runtime/theme.lua"))
	local okPaths, pathsModule = pcall(dofile, fs.combine(plan.target, "runtime/paths.lua"))
	if not (okTheme and type(theme) == "table" and type(theme.save) == "function") then
		return false
	end
	if not (okPaths and type(pathsModule) == "table") then
		return false
	end
	local okNew, paths = pcall(function()
		return pathsModule.new(plan.target)
	end)
	if not okNew then
		return false
	end
	local cfg = {
		mode = plan.theme or "dark",
		accent = plan.accent or "orange",
		wallpaper = plan.wallpaper or "aubergine",
	}
	if plan.user then
		local userHome = fs.combine(plan.target, fs.combine("home", plan.user))
		fs.makeDir(userHome)
		return theme.save(paths, plan.user, cfg) and true or false
	end
	return theme.save(paths, nil, cfg) and true or false
end

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
	lines[#lines + 1] = "version " .. tostring(plan.version or VERSION_FALLBACK)
	lines[#lines + 1] = "target " .. tostring(plan.target)
	lines[#lines + 1] = "type " .. tostring(plan.type)
	lines[#lines + 1] = "session " .. tostring(plan.session)
	lines[#lines + 1] = "edition " .. tostring(plan.edition)
	lines[#lines + 1] = "hostname " .. tostring(plan.hostname)
	lines[#lines + 1] = "files " .. tostring(results.installed)
	lines[#lines + 1] = "verified " .. tostring(results.verified)
	lines[#lines + 1] = "apps " .. tostring(results.apps)
	lines[#lines + 1] = "packages " .. tostring(results.packages or 0)
	lines[#lines + 1] = "installed " .. tostring(os.epoch("utc"))
	writeAll(fs.combine(plan.target, "var/lib/install-status.txt"), table.concat(lines, "\n") .. "\n")
end

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

local function runLocalInstall(plan, results)
	installFiles(plan, results)
end

local function readManifestLines(baseURL)
	local text = nil
	if options.mode == "local" then
		local root = sourceRoot()
		if root then
			text = readAll(fs.combine(root, MANIFEST_NAME))
		end
	else
		text = fetch(MANIFEST_NAME, baseURL)
	end
	if not text then
		return nil
	end
	local list, seen = {}, {}
	for row in text:gmatch("[^\r\n]+") do
		local entry = row:gsub("^%s+", ""):gsub("%s+$", "")
		if entry ~= "" and not entry:match("^#") and not seen[entry] then
			if entry ~= "netinstall.lua" and entry ~= "files.manifest" and entry ~= "install.lua" then
				seen[entry] = true
				list[#list + 1] = entry
			end
		end
	end
	return list
end

local function slimList(fileList, edition)
	local keep = {
		"startup.lua", "CloverOS_OS.lua", "boot/loader.lua", "boot/kernel.lua",
		"runtime/paths.lua", "runtime/hash.lua", "runtime/users.lua",
		"runtime/textui.lua", "runtime/packages.lua", "runtime/shell.lua",
		"etc/version.lua", "etc/motd.txt", "etc/apt/sources.list",
		"bin/clear.lua", "bin/ls.lua", "bin/cat.lua", "bin/copy.lua",
		"bin/move.lua", "bin/delete.lua", "bin/mkdir.lua", "bin/which.lua",
		"bin/sleep.lua", "bin/stat.lua", "bin/wget.lua", "bin/grep.lua",
		"bin/head.lua", "bin/tail.lua", "bin/net.lua", "bin/ping.lua",
		"bin/wget.lua", "bin/aptserver.lua",
	}
	local set = {}
	for _, rel in ipairs(keep) do
		set[rel] = true
	end
	local out = {}
	for _, rel in ipairs(fileList) do
		if set[rel] then
			out[#out + 1] = rel
		end
	end
	if edition == "turtle" then
		for _, rel in ipairs(TURTLE_PACKAGE_FILES) do
			out[#out + 1] = rel
		end
	end
	return out
end

local function filterExisting(target, list, installMode)
	local queue, skipped = {}, 0
	for _, file in ipairs(list) do
		local destination = fs.combine(target, file)
		if installMode == "reinstall" or not fs.exists(destination) then
			queue[#queue + 1] = file
		else
			skipped = skipped + 1
		end
	end
	return queue, skipped
end

local function netDownload(baseURL, target, queue)
	local createdDirs = {}
	local function ensureDir(file)
		local dir = file:match("(.*/)")
		if dir and not createdDirs[dir] then
			fs.makeDir(fs.combine(target, dir))
			createdDirs[dir] = true
		end
	end

	local total = #queue
	local done, failed = 0, {}
	local active = {}
	local running = 0
	local queueIndex = 0

	local function startNext()
		if queueIndex >= #queue or running >= MAX_CONCURRENT then
			return
		end
		queueIndex = queueIndex + 1
		local file = queue[queueIndex]
		local url = baseURL .. file
		http.request(url)
		active[url] = file
		running = running + 1
	end

	for _ = 1, math.min(MAX_CONCURRENT, #queue) do
		startNext()
	end

	while running > 0 do
		local event, url, data = os.pullEvent()
		if event == "http_success" and active[url] then
			local file = active[url]
			ensureDir(file)
			local content = data.readAll()
			data.close()
			local okWrite, writeErr = copyAndVerify(target, file, content)
			if okWrite then
				done = done + 1
				step(done, total, file .. " ... ")
				pass()
			else
				failed[#failed + 1] = file .. " (" .. tostring(writeErr) .. ")"
				bad("FAILED " .. file .. " (" .. tostring(writeErr) .. ")")
			end
			active[url] = nil
			running = running - 1
			startNext()
		elseif event == "http_failure" and active[url] then
			local file = active[url]
			failed[#failed + 1] = file .. " (" .. tostring(data or "unknown error") .. ")"
			bad("Failed: " .. file .. " (" .. tostring(data or "unknown error") .. ")")
			active[url] = nil
			running = running - 1
			startNext()
		end
	end

	if #failed == 0 then
		return true, done
	end
	bad(#failed .. " downloads failed:")
	for _, row in ipairs(failed) do
		bad("  - " .. row)
	end
	return false, done
end

local function finishInstall(plan, results)
	local configWritten = writeSystemConfig(plan, results)
	local desktopOk = writeDesktopConfig(plan)
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
		if desktopOk and plan.theme then
			say("  desktop theme:      " .. tostring(plan.theme) .. " / " .. tostring(plan.accent))
		end
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
end

local function runInteractive()
	local envType = "cct"
	local craftosSetup = false
	menuOptions("Select your OS environment", { "CC:Tweaked", "CraftOS" }, {
		function()
			envType = "cct"
		end,
		function()
			envType = "craftos"
			craftosSetup = true
		end,
	})

	if craftosSetup then
		say("Setting up CraftOS environment...")
		pcall(function()
			if shell and shell.run then
				shell.run("attach left drive")
				shell.run("attach right speaker")
				shell.run("attach back monitor")
			end
			if mounter and type(mounter) == "table" and mounter.mount then
				mounter.mount("/CloverOS_Disks/0", "C:\\CloverOS_Disks\\0")
			end
			if disk and type(disk) == "table" and disk.insertDisk then
				disk.insertDisk("left", "C:\\CloverOS_Disks\\0")
			end
		end)
		say("Environment setup complete.")
		if type(sleep) == "function" then
			sleep(1)
		end
	end

	local disks = listDisks()
	if #disks == 0 then
		bad("No disks detected! Insert one and reboot.")
		return
	end

	local plan = {
		target = "/",
		mode = options.mode,
		type = "alongside",
		tasks = {},
		mounts = {},
		edition = "default",
	}
	plan.envType = envType

	if #disks > 1 then
		local labels, paths = {}, {}
		for i, disk in ipairs(disks) do
			labels[i] = disk.name .. " (" .. tostring(disk.free) .. " bytes)"
			paths[i] = disk.path
		end
		plan.target = askMenu("Select target disk", labels, paths, 1) or "/"
	end
	log("target=" .. plan.target .. " env=" .. envType)

	local sourceChoice = options.mode == "net" and "raw" or nil
	if not sourceChoice then
		sourceChoice = askMenu("Select source server", { "Local files", "CDN (recommended)", "Raw GitHub" },
			{ "local", "pages", "raw" }, 1)
	end

	local baseURL, manifestURL
	if sourceChoice == "pages" then
		baseURL = CDN_BASE
		manifestURL = CDN_BASE .. MANIFEST_NAME
		plan.mode = "net"
	elseif sourceChoice == "raw" then
		baseURL = BASE
		manifestURL = BASE .. MANIFEST_NAME
		plan.mode = "net"
	else
		plan.mode = "local"
	end
	options.mode = plan.mode

	if plan.mode == "net" and not http then
		bad("HTTP is disabled on this computer.")
		bad("Enable http in the CraftOS config, or run: install --local")
		return
	end

	local edition = askMenu("Select CloverOS edition", {
		"Full (recommended)",
		"Soft (lightweight)",
		"Turtle (adds rturtle and autominer)",
		"Emulator",
	}, { "default", "soft", "turtle", "emulator" }, 1)

	local installMode = askMenu("Installation mode", { "Install", "Reinstall" }, { "install", "reinstall" }, 1)

	plan.edition = edition
	plan.session = "gnome"
	plan.lang = "en-US"
	plan.hostname = defaultHostname()
	plan.tasks = { "terminal", "utilities" }
	plan.packages = taskPackages(plan.tasks)
	plan.mounts["/"] = plan.target
	plan.mounts["/home"] = fs.combine(plan.target, "home")
	plan.mounts["/boot"] = fs.combine(plan.target, "boot")

	plan.theme = askMenu("Select theme", {
		"Dark (default)",
		"Light",
	}, { "dark", "light" }, 1)
	plan.accent = askMenu("Select accent color", {
		"Orange",
		"Purple",
		"Blue",
		"Green",
		"Red",
		"Lime",
	}, { "orange", "purple", "blue", "green", "red", "lime" }, 1)
	plan.wallpaper = askMenu("Select wallpaper", {
		"Aubergine wave",
		"Solid accent",
		"Dark grid",
	}, { "aubergine", "solid", "grid" }, 1)
	plan.autoLogin = askMenu("Enable auto-login?", { "No", "Yes" }, { false, true }, 1)
	if plan.autoLogin == true then
		plan.user = ask("Username for auto-login", os.getComputerLabel() or "clover")
	end

	say("Installation plan:")
	for _, row in ipairs(planSummary(plan)) do
		say("  " .. row)
	end
	say("")

	if not confirm("Write the changes above?", true) then
		say("Installation cancelled; nothing was changed.")
		log("cancelled by the operator")
		return
	end

	for _, dir in ipairs(DIRS) do
		fs.makeDir(fs.combine(plan.target, dir))
	end

	local results = { installed = 0, verified = 0, apps = 0, failed = {}, manifest = {} }

	if plan.mode == "net" then
		local fileList = readManifestLines(manifestURL)
		if not fileList or #fileList == 0 then
			warn("could not load " .. MANIFEST_NAME .. "; using the built-in file list")
			fileList = {}
			for _, rel in ipairs(FILES) do
				fileList[#fileList + 1] = rel
			end
			for _, rel in ipairs(OPTIONAL_FILES) do
				fileList[#fileList + 1] = rel
			end
		end
		if edition == "soft" or edition == "turtle" then
			fileList = slimList(fileList, edition)
		end
		local queue, skipped = filterExisting(plan.target, fileList, installMode)
		if skipped > 0 then
			say("Skipping " .. skipped .. " existing files.")
		end
		if #queue == 0 then
			say("Nothing to download; the installation is already present.")
			results.manifest = fileList
			results.installed = #fileList
		else
			local ok, done = netDownload(baseURL, plan.target, queue)
			if not ok then
				bad("The installation is INCOMPLETE. Fix the errors above and run install again.")
				log("download failures")
				flushLog(plan.target)
				return
			end
			results.manifest = queue
			results.installed = done
			results.verified = done
		end
	else
		runLocalInstall(plan, results)
	end

	finishInstall(plan, results)
end

local function runUnattended()
	say("CloverOS Installer")
	say("This program installs CloverOS onto this computer.")
	say("")
	log("installer started (mode=" .. options.mode .. ")")
	local plan, planErr = buildPlan()
	if not plan then
		bad(planErr or "cannot build an installation plan")
		return
	end

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

	local results = { installed = 0, verified = 0, apps = 0, failed = {}, manifest = {} }
	log("target=" .. plan.target .. " type=" .. plan.type)
	runLocalInstall(plan, results)
	finishInstall(plan, results)
end

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

if opts.noPrompt or not bufferWindow then
	runUnattended()
else
	log("installer started (mode=" .. opts.mode .. ")")
	runInteractive()
end
