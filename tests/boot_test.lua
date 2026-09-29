-- Boot test: full clean-computer flow inside one CraftOS process.
-- Stage 1 wipes the computer root, installs CloverOS to / from the mounted
-- repository, and verifies the installer's status file.
-- Stage 2 runs the REAL startup path while a parallel driver types scripted
-- input as genuine char/key events, synchronized through kernel journal
-- markers (first-run setup, login, GUI desktop, logout, second login).
-- The desktop writes /var/log/desktop-booted; the driver polls its stamp.
local pass, fail = 0, {}
local reportWritten = false

local function writeReport(status, detail)
	if reportWritten then
		return
	end
	reportWritten = true
	local lines = { "PASS=" .. (status == "PASS" and 1 or 0), "FAIL=" .. (status == "PASS" and 0 or 1) }
	if status ~= "PASS" then
		lines[#lines + 1] = "FAILLINE " .. tostring(detail)
	end
	lines[#lines + 1] = "BOOT=" .. status
	local report = fs.open("/test_report.txt", "w")
	report.write(table.concat(lines, "\n"))
	report.close()
end

local function failNow(detail)
	writeReport("FAIL", detail)
	os.shutdown()
end

-- ---------- stage 1: clean root + install ----------
for _, path in ipairs({ "/startup.lua", "/CloverOS_OS.lua", "/boot", "/runtime", "/libs", "/etc", "/bin", "/apps", "/home", "/var", "/tmp" }) do
	if fs.exists(path) then
		fs.delete(path)
	end
end

local installEnv = setmetatable({}, { __index = _G })
local okInstall, installErr = pcall(os.run, installEnv, "/src/install.lua", "/", "--local-source", "/src", "--no-prompt")
if not okInstall then
	failNow("root install crashed: " .. tostring(installErr))
end
if not fs.exists("/startup.lua") then
	failNow("root install did not produce /startup.lua")
end
local statusHandle = fs.open("/var/lib/install-status.txt", "r")
local status = statusHandle and statusHandle.readLine() or "MISSING"
if statusHandle then
	statusHandle.close()
end
if status ~= "OK" then
	failNow("installer reported status: " .. status)
end

-- ---------- stage 2: scripted boot ----------
local D = dofile("/src/tests/boot_driver.lua")

local function readMarker()
	local h = fs.open("/var/log/desktop-booted", "r")
	if not h then
		return nil
	end
	local data = h.readAll()
	h.close()
	return data
end

local function waitFor(cond, seconds, what)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if cond() then
			return true
		end
		sleep(0.5)
	end
	return false, what
end

local driver
driver = function()
	-- first-run setup prompt is up when its marker appears
	if not D.waitForMarker(D.M.SETUP, 60) then
		failNow("first-run setup never reached its prompt")
	end
	D.typeLine("bootuser")
	D.typeLine("bootpw")
	D.typeLine("bootpw")
	D.typeLine("n")
	if not D.waitForMarker(D.M.LOGIN, 30) then
		failNow("login prompt never appeared after setup")
	end
	D.typeLine("bootuser")
	D.typeLine("bootpw")
	-- the GUI desktop must render and write its marker
	local okDesktop = waitFor(function()
		return fs.exists("/var/log/desktop-booted")
	end, 40, "desktop did not render after first login")
	if not okDesktop then
		failNow("desktop did not render after first login")
	end
	local firstStamp = readMarker()
	-- logout back to the login screen
	os.queueEvent("key", keys.f10)
	sleep(2)
	if not D.waitForMarker(D.M.LOGIN, 30) then
		failNow("login prompt never reappeared after logout")
	end
	-- second login on the same running system
	D.typeLine("bootuser")
	D.typeLine("bootpw")
	local okSecond, secondWhat = waitFor(function()
		return readMarker() ~= firstStamp
	end, 40, "second desktop session did not start")
	if not okSecond then
		failNow("second desktop session did not start (" .. tostring(secondWhat) .. ")")
	end
	if not fs.exists("/etc/clover/users.db") then
		failNow("users.db missing after setup")
	end
	writeReport("PASS")
	sleep(0.5)
	os.shutdown()
end

local watchdog
watchdog = function()
	sleep(120)
	failNow("boot watchdog fired (system never finished the scripted flow)")
end

parallel.waitForAny(driver, watchdog, function()
	local okBoot, bootErr = pcall(dofile, "/startup.lua")
	if not okBoot and bootErr ~= "Terminated" then
		failNow("boot crashed: " .. tostring(bootErr))
	end
	-- boot returning early without shutdown is a failure; wait for the
	-- driver/watchdog to report
	while true do
		sleep(1)
	end
end)
