-- GUI smoke test: exercises the window manager and app callback model with
-- synthetic events. The repo is mounted at /src; the system under test is the
-- fresh install at /testroot.
local pass, fail = 0, {}

local function check(name, ok, detail)
	if ok then
		pass = pass + 1
	else
		fail[#fail + 1] = name .. " | " .. tostring(detail)
	end
end

_G.CLOVER_ROOT = "/testroot"

local ok, guiErr = pcall(function()
	local guiModule = dofile("/testroot/runtime/gui.lua")
	local gui = guiModule.new({})

	local winA = gui:createWindow({ title = "A", x = 2, y = 2, w = 20, h = 8 })
	local winB = gui:createWindow({ title = "B", x = 25, y = 4, w = 20, h = 8 })
	check("two windows created", winA and winB and winA ~= winB)
	check("new window focused", gui.focused == winB, tostring(gui.focused))

	gui:focusWindow(winA)
	check("focus switch", gui.focused == winA)

	gui:pump({ "mouse_click", 1, 30, 8 })
	check("click focuses B", gui.focused == winB)

	local gotKey = nil
	winB.handlers.onKey = function(w, key)
		gotKey = key
	end
	gui:pump({ "key", keys.q, false })
	check("key routed to focused", gotKey == keys.q, tostring(gotKey))

	local gotKeyA = nil
	winA.handlers.onKey = function(w, key)
		gotKeyA = true
	end
	gui:pump({ "key", keys.q, false })
	check("key not routed to unfocused", gotKeyA == nil)

	local gotChar = nil
	winB.handlers.onChar = function(w, ch)
		gotChar = ch
	end
	gui:pump({ "char", "x" })
	check("char routed", gotChar == "x", tostring(gotChar))

	-- window dragging via title bar
	local startPos = { x = winA.frame.position.x, y = winA.frame.position.y }
	gui:pump({ "mouse_click", 1, startPos.x + 6, startPos.y })
	check("title click focuses A", gui.focused == winA, tostring(gui.focused and gui.focused.title))
	gui:pump({ "mouse_drag", 1, startPos.x + 16, startPos.y + 3 })
	check("drag moves window",
		winA.frame.position.x == startPos.x + 10 and winA.frame.position.y == startPos.y + 3,
		tostring(winA.frame.position.x) .. "," .. tostring(winA.frame.position.y))
	gui:pump({ "mouse_up", 1, startPos.x + 16, startPos.y + 3 })
	gui:pump({ "mouse_drag", 1, startPos.x + 40, startPos.y + 10 })
	check("drag ends on mouse_up",
		winA.frame.position.x == startPos.x + 10 and winA.frame.position.y == startPos.y + 3,
		tostring(winA.frame.position.x) .. "," .. tostring(winA.frame.position.y))

	local twSize, thSize = term.getSize()
	gui:pump({ "mouse_click", 1, winA.frame.position.x + 6, winA.frame.position.y })
	gui:pump({ "mouse_drag", 1, twSize + 20, thSize + 20 })
	check("drag clamps to screen",
		winA.frame.position.x >= 1 and winA.frame.position.x <= twSize - winA.frame.w + 1
			and winA.frame.position.y >= 1 and winA.frame.position.y <= thSize - winA.frame.h + 1,
		tostring(winA.frame.position.x) .. "," .. tostring(winA.frame.position.y))
	gui:pump({ "mouse_up", 1, twSize + 20, thSize + 20 })

	-- minimized windows must not swallow clicks meant for windows below;
	-- winD overlaps winB so the body-click has an unambiguous target
	local winD = gui:createWindow({ title = "D", x = 26, y = 5, w = 20, h = 8 })
	gui:pump({ "mouse_click", 1, winD.frame.position.x, winD.frame.position.y })
	check("minimize toggles", winD.frame.style.maximised == false)
	gui:pump({ "mouse_click", 1, winD.frame.position.x, winD.frame.position.y })
	check("restore from minimize", winD.frame.style.maximised == true)
	gui:pump({ "mouse_click", 1, winD.frame.position.x, winD.frame.position.y })
	check("minimize again", winD.frame.style.maximised == false)
	gui:pump({ "mouse_click", 1, 30, 7 })
	check("minimized window ignores body clicks", gui.focused == winB,
		tostring(gui.focused and gui.focused.title))
	winD:close()
	gui:pump({ "timer", 0 })
	check("minimize test window closed", not gui:isOpen(winD))

	local winC = gui:createWindow({ title = "C", x = 2, y = 2, w = 20, h = 8 })
	gui:pump({ "mouse_click", 1, winC.frame.position.x + winC.frame.w - 1, winC.frame.position.y })
	check("close button works", not gui:isOpen(winC))

	winB:close()
	gui:pump({ "timer", 0 })
	check("close removes window", not gui:isOpen(winB))

	local okRender = pcall(function()
		gui:render()
	end)
	check("render ok", okRender)

	-- desktop path: build a full runtime and open apps
	local pathsMod = dofile("/testroot/runtime/paths.lua")
	local usersMod = dofile("/testroot/runtime/users.lua")
	local pkgMod = dofile("/testroot/runtime/packages.lua")
	local shellMod = dofile("/testroot/runtime/shell.lua")
	local uiMod = dofile("/testroot/runtime/textui.lua")
	local desktopMod = dofile("/testroot/runtime/desktop.lua")

	local paths = pathsMod.new("/testroot")
	local users = usersMod.new(paths)
	users:load()
	users:createUser("guitest", "pw")
	users:login("guitest")
	local ui = uiMod.new(paths)
	local packages = pkgMod.new(paths)
	local session = shellMod.new({
		paths = paths,
		users = users,
		ui = ui,
		packages = packages,
	})
	local desktop = desktopMod.new({
		paths = paths,
		users = users,
		ui = ui,
		packages = packages,
		session = session,
		kernel = nil,
		gui = gui,
	})

	local opened = desktop:openApp("sysinfo")
	check("desktop opens sysinfo", opened ~= nil)

	local okDraw = pcall(function()
		gui:render()
	end)
	check("render with app ok", okDraw)

	local forked = session:forkWindowShell(winA)
	forked:execute("echo hello_from_fork")
	local lines = forked:drainOutput()
	check("fork shell executes", #lines >= 1 and lines[#lines] == "hello_from_fork", table.concat(lines, "/"))

	local setWin = desktop:openApp("settings")
	check("desktop opens settings", setWin ~= nil)
	local filesWin = desktop:openApp("files")
	check("desktop opens files", filesWin ~= nil)
	local termWin = desktop:openApp("terminal")
	check("desktop opens terminal", termWin ~= nil)

	-- winA (from the fork-shell section) plus the four app windows
	check("all windows tracked", #gui:listWindows() == 5, tostring(#gui:listWindows()))

	local okFinal = pcall(function()
		gui:render()
	end)
	check("final render ok", okFinal)
end)

if not ok then
	fail[#fail + 1] = "GUI test body crashed | " .. tostring(guiErr)
end

local out = { "PASS=" .. pass, "FAIL=" .. #fail }
for _, f in ipairs(fail) do
	out[#out + 1] = "FAILLINE " .. f
end
local report = fs.open("/test_report.txt", "w")
report.write(table.concat(out, "\n"))
report.close()
print("gui tests: " .. pass .. " passed, " .. #fail .. " failed")
os.shutdown()
