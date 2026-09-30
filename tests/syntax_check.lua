-- Syntax validation: every Lua file the boot path or shell can load must parse.
-- Runs inside CraftOS-PC. The repository is mounted at /src via mounter.mount
-- by the test runner before this script runs.
local results = { "PASS=0", "FAIL=0" }
local pass, fail = 0, {}

local candidates = {
	"startup.lua",
	"install.lua",
	"netinstall.lua",
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
	"runtime/packages.lua",
	"runtime/shell.lua",
	"runtime/gui.lua",
	"runtime/panel.lua",
	"runtime/overview.lua",
	"runtime/launcher.lua",
	"runtime/desktop.lua",
	"libs/mc-imgui.lua",
	"etc/version.lua",
	"tests/syntax_check.lua",
	"tests/module_test.lua",
}

local function addDirFiles(dir)
	if not fs.isDir(dir) then
		return
	end
	for _, name in ipairs(fs.list(dir)) do
		local full = fs.combine(dir, name)
		if not fs.isDir(full) and name:match("%.lua$") then
			candidates[#candidates + 1] = full
		end
	end
end

addDirFiles("bin")
addDirFiles("apps")

for _, rel in ipairs(candidates) do
	local full = fs.combine("/src", rel)
	if fs.exists(full) then
		local h = fs.open(full, "r")
		local data = h.readAll()
		h.close()
		local fn, err = load(data, "=" .. rel, "t", {})
		if fn then
			pass = pass + 1
		else
			fail[#fail + 1] = rel .. ": " .. tostring(err)
		end
	else
		fail[#fail + 1] = rel .. ": FILE MISSING"
	end
end

local out = { "PASS=" .. pass, "FAIL=" .. #fail }
for _, f in ipairs(fail) do
	out[#out + 1] = "FAILLINE " .. f
end
local report = fs.open("/test_report.txt", "w")
report.write(table.concat(out, "\n"))
report.close()
print("syntax check: " .. pass .. " passed, " .. #fail .. " failed")
os.shutdown()
