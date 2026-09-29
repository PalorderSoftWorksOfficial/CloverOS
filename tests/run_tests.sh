#!/bin/bash
# CloverOS test runner: drives CraftOS-PC headless.
# Every suite runs in a fresh CraftOS-PC computer with the repository mounted
# read-only at /src and installs CloverOS into /testroot before testing it,
# so no suite depends on artifacts from a previous suite.
# Usage: tests/run_tests.sh [path-to-CraftOS-PC_console.exe]
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CRAFTOS="${1:-/c/Program Files/CraftOS-PC/CraftOS-PC_console.exe}"
WINREPO=$(cygpath -m "$REPO")
WORK="${TMPDIR:-/tmp}/cloveros-tests"
PASS=0
FAIL=0

mkdir -p "$WORK"

# computer 0 state lives under CraftOS-PC config regardless of --directory
COMP="$USERPROFILE/AppData/Roaming/CraftOS-PC/computer/0"
mkdir -p "$COMP"

run_headless() {
	local script="$1"
	local timeout="$2"
	local log="$3"
	rm -f "$COMP/test_report.txt"
	timeout "$timeout" "$CRAFTOS" --headless --script "$script" > "$log" 2>&1
	local rc=$?
	if [ $rc -eq 124 ]; then
		echo "TIMEOUT after ${timeout}s"
		taskkill //IM CraftOS-PC_console.exe //F > /dev/null 2>&1
		return 1
	fi
	return 0
}

# The harness mounts the repo, installs into /testroot, then runs the suite.
cat > "$WORK/harness.lua" <<EOF
-- test harness: mount repo, fresh-install CloverOS into /testroot, run suite
local ok, err = pcall(function()
	mounter.mount("/src", "$WINREPO")
end)
if not ok then
	local r = fs.open("/test_report.txt", "w")
	r.write("FAIL=1\\nFAILLINE harness mount failed: " .. tostring(err))
	r.close()
	os.shutdown()
end

_G.CLOVER_ROOT = "/testroot"

if fs.isDir("/testroot") then
	fs.delete("/testroot")
end
fs.makeDir("/testroot")

local suite = nil
local f = fs.open("/suite_name", "r")
if f then
	suite = f.readLine()
	f.close()
end

local function failFast(message)
	local r = fs.open("/test_report.txt", "w")
	r.write("FAIL=1\\nFAILLINE " .. tostring(message))
	r.close()
	os.shutdown()
end

-- every suite starts from a fresh local install of the mounted repo
-- (except boot2/boot_text, which reuse the boot suite's persisted root)
if suite ~= "boot2" and suite ~= "boot_text" then
	local installOk, installErr = pcall(function()
		shell.run("/src/install.lua", "/testroot", "--local", "--no-prompt")
	end)
	if not installOk then
		failFast("harness install crashed: " .. tostring(installErr))
	end
	if not fs.exists("/testroot/startup.lua") or not fs.exists("/testroot/runtime/shell.lua") then
		failFast("harness install incomplete")
	end
end

if suite == "install" then
	local report = { "PASS=1", "FAIL=0" }
	local required = {
		"startup.lua", "CloverOS_OS.lua", "boot/loader.lua", "boot/kernel.lua",
		"runtime/shell.lua", "runtime/gui.lua", "libs/mc-imgui.lua", "etc/version.lua",
		"runtime/paths.lua", "runtime/users.lua", "runtime/packages.lua",
		"runtime/textui.lua", "runtime/desktop.lua",
		"bin/ls.lua", "bin/cat.lua", "etc/motd.txt", "etc/man/man.man",
	}
	local missing = {}
	for _, f2 in ipairs(required) do
		if not fs.exists(fs.combine("/testroot", f2)) then
			missing[#missing + 1] = f2
		end
	end
	if #missing > 0 then
		report = { "PASS=0", "FAIL=" .. #missing }
		for _, f2 in ipairs(missing) do
			report[#report + 1] = "FAILLINE missing after install: " .. f2
		end
	end
	local r = fs.open("/test_report.txt", "w")
	r.write(table.concat(report, "\\n"))
	r.close()
	os.shutdown()
elseif suite == "syntax" then
	dofile("/src/tests/syntax_check.lua")
elseif suite == "module" then
	dofile("/src/tests/module_test.lua")
elseif suite == "boot" then
	dofile("/src/tests/boot_test.lua")
elseif suite == "boot2" then
	dofile("/src/tests/boot2_test.lua")
elseif suite == "boot_text" then
	dofile("/src/tests/boot_text_test.lua")
elseif suite == "gui" then
	dofile("/src/tests/gui_test.lua")
else
	failFast("unknown suite: " .. tostring(suite))
end
EOF

read_report() {
	local label="$1"
	local report="$COMP/test_report.txt"
	if [ ! -f "$report" ]; then
		echo "NO REPORT (suite crashed before writing results)"
		FAIL=$((FAIL+1))
		return 1
	fi
	cat "$report"
	if grep -q "^FAIL=[1-9]" "$report"; then
		FAIL=$((FAIL+1))
		return 1
	fi
	PASS=$((PASS+1))
	return 0
}

run_suite() {
	local suite="$1"
	local timeout="$2"
	local log="$3"
	echo "$suite" > "$COMP/suite_name"
	run_headless "$WORK/harness.lua" "$timeout" "$WORK/$log"
	read_report "$suite"
}

echo "=== CloverOS test suite ==="

echo "--- clean install (installer must not report success with missing files) ---"
run_suite install 150 install.log

echo "--- syntax check (entire boot-path dependency tree) ---"
run_suite syntax 150 syntax.log

echo "--- module tests (paths/users/packages/shell) ---"
run_suite module 150 module.log

echo "--- boot test (real startup path from a clean root, scripted setup+login) ---"
run_suite boot 240 boot.log

echo "--- boot2 (reboot persistence: new process, state retained, login again) ---"
run_suite boot2 120 boot2.log

echo "--- boot_text (text-mode shell when GUI disabled) ---"
run_suite boot_text 120 boot_text.log

echo "--- GUI smoke test (window manager, focus, events, apps) ---"
run_suite gui 150 gui.log

echo
echo "=== suites passed: $PASS, failed: $FAIL ==="
[ "$FAIL" -eq 0 ]
