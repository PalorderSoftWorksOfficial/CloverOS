-- Shared driver helpers for the boot suites: event-synced scripted input.
-- CraftOS sleep() filters events, so blind timed typing is unreliable; the
-- OS writes kernel journal markers at each prompt stage and the driver
-- waits for them via /var/log/kernel.log before typing each line.
local D = {}

local LOG = "/var/log/kernel.log"

function D.bootInfoLine()
	local h = fs.open(LOG, "r")
	if not h then
		return ""
	end
	local data = h.readAll()
	h.close()
	return data or ""
end

function D.waitForMarker(marker, seconds)
	local deadline = os.clock() + (seconds or 30)
	while os.clock() < deadline do
		if D.bootInfoLine():find(marker, 1, true) then
			return true
		end
		sleep(0.2)
	end
	return false
end

function D.typeLine(text)
	for i = 1, #text do
		os.queueEvent("char", text:sub(i, i))
		sleep(0.05)
	end
	os.queueEvent("key", keys.enter)
	sleep(0.3)
end

-- marker names written by the OS boot path (see CloverOS_OS.lua)
D.M = {
	SETUP = "first-run setup: awaiting user creation",
	LOGIN = "login prompt ready",
	SESSION = "session started for ",
}

return D
