local repoFiles = ...

local envMod = assert(load(repoFiles["tests/host/craftos_env.lua"], "@craftos_env"))()
local shim = envMod.install(repoFiles)

local failures = 0
local function pass(msg)
	print("  ok  " .. msg)
end
local function fail(msg)
	failures = failures + 1
	print("  FAIL " .. msg)
end

local keys = _G.keys
local nativeTerm = term.native()

for _ = 1, 14 do
	os.queueEvent("key", keys.enter)
end

local redirects = {}
local realRedirect = term.redirect
term.redirect = function(target)
	redirects[#redirects + 1] = target
	return realRedirect(target)
end

local function installer()
	local fn = assert(load(repoFiles["install.lua"], "@install.lua", "t", setmetatable({}, { __index = _G })))
	fn()
end

local function feeder()
	sleep(100000)
end

local outcome
local okRun, runErr = pcall(parallel.waitForAll, installer, feeder)
if not okRun and runErr == "Terminated" then
	outcome = "reboot"
elseif okRun then
	outcome = "returned"
else
	outcome = runErr
end

if outcome == "reboot" or outcome == "returned" then
	pass("interactive install ran through every menu (" .. tostring(outcome) .. ")")
else
	fail("interactive install crashed: " .. tostring(outcome))
end

local menuBuffers = {}
for _, target in ipairs(redirects) do
	if target ~= nativeTerm and type(target) == "table" and type(target.getLine) == "function" then
		menuBuffers[#menuBuffers + 1] = target
	end
end
if #menuBuffers > 0 then
	pass("menus rendered through the buffered window (" .. #menuBuffers .. " buffers)")
else
	fail("no buffered-window redirect happened")
end

local titles = {}
for _, target in ipairs(menuBuffers) do
	titles[#titles + 1] = target.getLine(1) or ""
end
local lastTitle = titles[#titles] or ""
if lastTitle:find("auto%-login") or lastTitle:find("Installation mode") then
	pass("menu title bar drew: " .. lastTitle)
else
	fail("menu title not found in buffer; last title: [" .. lastTitle .. "]")
end

local selectionSeen = false
for _, target in ipairs(menuBuffers) do
	for y = 2, 6 do
		local row = target.getLine(y) or ""
		if row:sub(1, 2) == "> " then
			selectionSeen = true
		end
	end
end
if selectionSeen then
	pass("selection marker rendered")
else
	fail("selection marker never rendered")
end

if fs.exists("/startup.lua") then
	pass("startup.lua installed via the interactive path")
else
	fail("startup.lua missing after interactive install")
end

local status = fs.open("/var/lib/install-status.txt", "r")
local line = status and status.readLine() or "MISSING"
if status then
	status.close()
end
if line == "OK" then
	pass("interactive install status OK")
else
	fail("interactive install status: " .. tostring(line))
end

local cfg = fs.open("/home/.config/clover/desktop.cfg", "r")
local cfgBody = cfg and cfg.readAll() or ""
if cfg then
	cfg.close()
end
if cfgBody:find('"dark"', 1, true) and cfgBody:find('"orange"', 1, true) then
	pass("theme menu values persisted to desktop.cfg")
else
	fail("desktop.cfg did not carry the menu choices: " .. cfgBody)
end

local inst = fs.open("/etc/clover/install.cfg", "r")
local instBody = inst and inst.readAll() or ""
if inst then
	inst.close()
end
if instBody:find('"default"', 1, true) then
	pass("edition recorded in install.cfg")
else
	fail("install.cfg missing edition")
end

local screen = {}
for y = 1, 19 do
	screen[#screen + 1] = term.getLine(y) or ""
end
local screenText = table.concat(screen, "\n")
if screenText:find("start automatically", 1, true) then
	pass("final installer output visible on the real screen")
else
	fail("final summary not visible on the native screen")
end

if failures > 0 then
	error("HOST TESTS FAILED: install_menu probe", 0)
end
print("  probe complete: interactive installer menu works end to end")
