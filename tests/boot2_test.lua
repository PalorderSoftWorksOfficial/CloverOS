-- Boot2 test: reboot persistence. This suite runs in a NEW CraftOS process
-- after the boot suite; the computer disk (computer/0) still holds the root
-- install, the users database, and history from that process. It verifies
-- that a second boot finds them, that login works again, and that the GUI
-- desktop starts a fresh session (marker timestamp changes).
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
	lines[#lines + 1] = "BOOT2=" .. status
	local report = fs.open("/test_report.txt", "w")
	report.write(table.concat(lines, "\n"))
	report.close()
end

local function failNow(detail)
	writeReport("FAIL", detail)
	os.shutdown()
end

if not fs.exists("/startup.lua") then
	failNow("root install from boot suite is missing (suites out of order?)")
end
if not fs.exists("/etc/clover/users.db") then
	failNow("users.db did not persist across reboot")
end
if not fs.exists("/var/lib/install-status.txt") then
	failNow("install status did not persist across reboot")
end

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

local oldMarker = readMarker()

local driver
driver = function()
	if not D.waitForMarker(D.M.LOGIN, 60) then
		failNow("login prompt never appeared after reboot")
	end
	D.typeLine("bootuser")
	D.typeLine("bootpw")
	local okDesktop = waitFor(function()
		return readMarker() ~= oldMarker
	end, 30, "desktop did not render after reboot login")
	if not okDesktop then
		failNow("desktop did not render after reboot login")
	end
	writeReport("PASS")
	sleep(0.5)
	os.shutdown()
end

local watchdog
watchdog = function()
	sleep(60)
	failNow("boot2 watchdog fired (login after reboot never reached the desktop)")
end

parallel.waitForAny(driver, watchdog, function()
	local okBoot, bootErr = pcall(dofile, "/startup.lua")
	if not okBoot and bootErr ~= "Terminated" then
		failNow("boot after reboot crashed: " .. tostring(bootErr))
	end
	while true do
		sleep(1)
	end
end)
