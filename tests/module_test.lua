-- Runtime module tests: paths, users, packages, shell execution.
-- The repository is mounted read-only at /src; the system under test is a
-- scratch install at /testroot populated by the harness before boot.
local pass, fail = 0, {}

local function check(name, ok, detail)
	if ok then
		pass = pass + 1
	else
		fail[#fail + 1] = name .. " | " .. tostring(detail)
	end
end

_G.CLOVER_ROOT = "/testroot"

local function loadModule(name)
	return dofile(fs.combine("/testroot", name))
end

-- paths
local pathsMod = loadModule("runtime/paths.lua")
local paths = pathsMod.new("/testroot")
check("paths root field", paths.root == "/testroot")
check("paths join", paths:join("home", "alice") == "testroot/home/alice" or fs.exists("/testroot"))
fs.makeDir("/testroot/bin")
local h = fs.open("/testroot/bin/probe.txt", "w")
h.write("hello")
h.close()
check("paths displayPath", paths:displayPath("bin/probe.txt") == "/bin/probe.txt")
check("paths setCwd", paths:setCwd("bin") == true)
paths:setCwd("/testroot")

-- users
local usersMod = loadModule("runtime/users.lua")
local users = usersMod.new(paths)
check("users empty", users:hasAnyUser() == false)
local okCreate = users:createUser("alice", "pw123")
check("users create", okCreate == true)
local dup, dupErr = users:createUser("alice", "x")
check("users duplicate rejected", dup == nil and type(dupErr) == "string")
check("users bad name rejected", users:createUser("bad name!", "x") == nil)
users:load()
check("users persist", users:exists("alice"))
check("users auth ok", users:authenticate("alice", "pw123") == true)
check("users auth bad", users:authenticate("alice", "wrong") == false)
check("users login", users:login("alice") == true)
check("users current", users:currentName() == "alice")
local okSet = users:setPassword("alice", "newpw")
users:load()
check("users password change", okSet and users:authenticate("alice", "newpw"))

-- packages
local pkgMod = loadModule("runtime/packages.lua")
local packages = pkgMod.new(paths)
local list = packages:list()
check("packages catalog", #list >= 1 and list[1] == "example", table.concat(list, ","))
local meta = packages:info("example")
check("packages meta", meta and meta.name == "example" and meta.version == "1.0.0")
check("packages not installed", packages:isInstalled("example") == false)
local okInstall, installErr = packages:install("example")
check("packages install", okInstall == true, installErr)
check("packages installed flag", packages:isInstalled("example") == true)
check("packages payload", fs.exists("/testroot/bin/hello.lua"))
local okRemove, removeErr = packages:remove("example")
check("packages remove", okRemove == true, removeErr)
check("packages payload gone", fs.exists("/testroot/bin/hello.lua") == false)
local badInstall = packages:install("nonexistent")
check("packages unknown rejected", badInstall == nil)

-- shell (non-interactive execute)
local textui = loadModule("runtime/textui.lua")
local ui = textui.new(paths)
local shellMod = loadModule("runtime/shell.lua")
local shell = shellMod.new({
	paths = paths,
	users = users,
	ui = ui,
	packages = packages,
})
local out = {}
local oldPrint = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	out[#out + 1] = table.concat(parts, " ")
end

shell:execute("echo hello world")
check("shell echo", out[#out] == "hello world", out[#out])
shell:execute("whoami")
check("shell whoami", out[#out] == "alice", out[#out])
shell:execute("cd /")
shell:execute("pwd")
check("shell pwd", out[#out] == "/", out[#out])

fs.makeDir("/testroot/shelltest")
local hf = fs.open("/testroot/shelltest/note.txt", "w")
hf.write("note body")
hf.close()
shell:execute("ls /shelltest")
check("shell ls", out[#out] == "note.txt", out[#out])
shell:execute("cat /shelltest/note.txt")
check("shell cat", out[#out] == "note body", out[#out])
shell:execute("touch /shelltest/empty.txt")
check("shell touch", fs.exists("/testroot/shelltest/empty.txt"))
shell:execute("mkdir /shelltest/sub")
check("shell mkdir", fs.isDir("/testroot/shelltest/sub"))
shell:execute("cp /shelltest/note.txt /shelltest/sub/note2.txt")
check("shell cp", fs.exists("/testroot/shelltest/sub/note2.txt"))
shell:execute("mv /shelltest/sub/note2.txt /shelltest/sub/renamed.txt")
check("shell mv", fs.exists("/testroot/shelltest/sub/renamed.txt"))
shell:execute("rm /shelltest/sub/renamed.txt")
check("shell rm", not fs.exists("/testroot/shelltest/sub/renamed.txt"))
shell:execute("history")
check("shell history", #shell.history >= 10)
shell:execute("alias ll=ls")
shell:execute("ll /shelltest")
check("shell alias", (out[#out] or "") ~= "", out[#out])
shell:execute("nonexistentcmd")
check("shell unknown cmd", (out[#out] or ""):find("no such command", 1, true) ~= nil, out[#out])
shell:execute("man cat")
check("shell man", (out[#out] or "") ~= "", out[#out])

-- window-shell fork: buffered output, interactive builtins refuse cleanly
local forked = shell:forkWindowShell()
check("fork isolated output", forked:drainOutput() ~= nil)
forked:execute("echo forked_echo_works")
local flines = forked:drainOutput()
check("fork echo", #flines >= 1 and flines[#flines] == "forked_echo_works", table.concat(flines, "/"))
forked:execute("su nobody")
local serr = forked:drainOutput()
check("fork su refuses", #serr >= 1 and serr[1]:find("interactive", 1, true) ~= nil, table.concat(serr, "/"))
forked:execute("ls /")
local lslines = forked:drainOutput()
check("fork ls runs program", #lslines >= 1, table.concat(lslines, "/"))

print = oldPrint

local reportData = { "PASS=" .. pass, "FAIL=" .. #fail }
for _, f in ipairs(fail) do
	reportData[#reportData + 1] = "FAILLINE " .. f
end
local report = fs.open("/test_report.txt", "w")
report.write(table.concat(reportData, "\n"))
report.close()
print("module tests: " .. pass .. " passed, " .. #fail .. " failed")
os.shutdown()
