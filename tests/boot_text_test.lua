-- Boot_text test: with gui=false in the persisted settings, boot must go
-- straight to the text shell and it must actually execute commands.
-- Output verification happens host-side by grepping the console log for
-- "text_shell_ok" and the whoami output.
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
	lines[#lines + 1] = "BOOT_TEXT=" .. status
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
	failNow("users.db did not persist for text-mode boot")
end

-- force text mode via the persisted settings config
fs.makeDir("/var/lib/clover")
local cfg = fs.open("/var/lib/clover/settings.cfg", "w")
cfg.write(textutils.serialize({ gui = false }))
cfg.close()

local D = dofile("/src/tests/boot_driver.lua")

local driver
driver = function()
	if not D.waitForMarker(D.M.LOGIN, 60) then
		failNow("login prompt never appeared in text mode")
	end
	D.typeLine("bootuser")
	D.typeLine("bootpw")
	-- exercise the text shell; output is verified host-side from the log
	D.typeLine("whoami")
	D.typeLine("echo text_shell_ok")
	D.typeLine("ls /")
	D.typeLine("exit")
	writeReport("PASS")
	sleep(0.5)
	os.shutdown()
end

local watchdog
watchdog = function()
	sleep(60)
	failNow("boot_text watchdog fired (text shell flow never completed)")
end

parallel.waitForAny(driver, watchdog, function()
	local okBoot, bootErr = pcall(dofile, "/startup.lua")
	if not okBoot and bootErr ~= "Terminated" then
		failNow("text-mode boot crashed: " .. tostring(bootErr))
	end
	while true do
		sleep(1)
	end
end)
