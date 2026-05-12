local pullEvent = os.pullEvent
os.pullEvent = os.pullEventRaw
settings.clear()
--[[
    BIOS Utility Script by Peekofwar, Modified by CloverOS Team.
    
    This program allows you to easily
    change the settings of the computer
    through a graphical interface, 
    mainly using the settings API. 
    
    Type "help" after the program name
    to display a list of switches that
    tweak the behavior of the program.
    
    v1.1.0 (Oct 30, 2019)
    + BIOS password now fully supported
    + Added some more info on main screen
    + Option to permenantly enable mono-
    chrome "dark theme"
    + Option to change boot delay
    + Option to change computer label
    + Controls hints now change when in
    adjusting some settings
    
    v1.1.1 (Dec 17, 2019)
    * Fixed nil value error when the
    boot delay setting had not yet
    been created.
    
    v1.2.0 (Dec 20, 2019)
    * Replaced old password screen...
    You are no longer kicked from the
    password screen if incorrect
    * Password setup now requires new
    password to be entered twice to
    mitigate typos
    
    v1.2.1 (Dec 27, 2019)
    * Fixed default password value
    being '""' instead of 'false'.
    
    v1.2.2 (Dec 28, 2019)
    * Fixed boot delay setting being
    set before settings file was
    loaded
    
    v1.2.3 (Jan 24, 2020)
    + Added version to help screen
    
    v1.2.4 (Jul 6, 2020)
    * Fixed typo on a line in textSetting()
    v1.2.5
    * Computer label is no longer saved upon
    entering, but instead when saving and
    exiting the program
    v1.2.6
    * Password screen no longer flickers;
    it no longer draws every 0.01 seconds
    
    Known bugs & issues
    (none at the moment)
    
]]

version = "ACI SETUP UTILITY v1.2.6"
versiondate = "(Tuesday, May 12, 2026)"

function setUIColors()
	col = {}
	if term.isColor() and arg[1] ~= "/m" and arg[2] ~= "/m" and not settings.get("bios.forceMono") then
		col.tabT = 256 -- Tab text fore
		col.tabB = 2048 -- Tab text back
		col.tabF = 2048 -- Tab line
		col.headT = 32768 -- Header text
		col.headB = 512 -- Header fill
		col.fill = 256 -- Background fill
		col.item = 32768 -- Item header
		col.itemS = 1 -- Selected item
		col.itemE = 2048 -- Selectable (enabled) item
		col.itemD = 128 -- Not-selectable (disabled) item
		col.msg = 16 -- Message text
		col.err = 16384 -- Error text

		col.dialogT = 32768 -- Dialog box text
		col.dialogB = 1 -- Dialog box fill

		col.w = 1
		col.b = 32768
	else -- Monochrome compatible color set:
		col.tabT = 256 -- Tab text fore
		col.tabB = 128 -- Tab text back
		col.tabF = 128 -- Tab line
		col.headT = 32768 -- Header text
		col.headB = 256 -- Header fill
		col.fill = 32768 -- Background fill
		col.item = 256 -- Item header
		col.itemS = 1 -- Selected item
		col.itemE = 256 -- Selectable (enabled) item
		col.itemD = 128 -- Not-selectable (disabled) item
		col.msg = 1 -- Message text
		col.err = 1 -- Error text

		col.dialogT = 1 -- Dialog box text
		col.dialogB = 128 -- Dialog box fill

		col.w = 1
		col.b = 32768
	end
end

local arg = { ... }

local tX, tY = term.getSize()
listenBreak = false
timer = 0.25
function listen()
	while not listenBreak do
		event, key = os.pullEvent("key")
	end
end
function pTimer()
	if settings.get("bios.bootDelay") then
		timer = settings.get("bios.bootDelay")
	else
		timer = 0.25
	end
	biosBootDelayValue = timer
	while timer > 0 do
		sleep(biosBootDelayValue)
		timer = timer - biosBootDelayValue
	end
end

function pauseStart()
	sCol("b", col.b)
	sCol("t", col.w)
	sPos(1, 1)
	term.clear()
	term.setCursorBlink(true)

	sPos(1, tY)
	write("Press F1 for options")
	sPos(1, 1)

	while timer > 0 do
		if key == keys.f1 then
			sPos(1, tY)
			term.clearLine()
			write("Startup paused.")
			sPos(1, 1)
			sleep(1)
			term.setCursorBlink(false)
			biosPasswordScreen()
			core()
			break
		end
		sleep(0.01)
	end

	listenBreak = true
	term.setCursorBlink(false)
	sPos(1, tY)
	write("Startup paused. Press any key to resume.")
	sPos(1, 1)

	listenBreak = true

	quit(true)
end

function sCol(back, color)
	if back == "t" then
		term.setTextColor(color)
		return true, "Fore"
	else
		term.setBackgroundColor(color)
		return true, "Back"
	end
end
local function cWrite(text)
	local w, h = term.getSize()
	local cX, cY = term.getCursorPos()
	term.setCursorPos(math.floor(w / 2 - text:len() / 2 + 0.5), cY)
	io.write(text)
end

function sPos(x, y, relative, r2)
	if relative then
		x1, y1 = term.getCursorPos()
		if not r2 then
			x = x1 + x
		end -- Allows X to remain absolute
		y = y1 + y
	end
	return term.setCursorPos(x, y)
end
function drawScreen(rrst)
	local tX, tY = term.getSize()

	if tab == 1 and row == 2 then
		setUIColors()
	end

	sCol("b", col.fill)
	sPos(1, 1)
	term.clear()

	sPos(1, 1)
	sCol("b", col.headB)
	term.clearLine()
	sCol("t", col.headT)
	sPos(5, 1)
	cWrite(version)

	sPos(1, 2)
	sCol("b", col.tabF)
	term.clearLine()
	if tab == 1 then
		sCol("b", col.tabT)
		sCol("t", col.tabB)
	else
		sCol("t", col.tabT)
		sCol("b", col.tabB)
	end
	sPos(2, 2)
	write(" Main ")
	if tab == 2 then
		sCol("b", col.tabT)
		sCol("t", col.tabB)
	else
		sCol("t", col.tabT)
		sCol("b", col.tabB)
	end
	sPos(8, 2)
	write(" Shell ")
	if tab == 3 then
		sCol("b", col.tabT)
		sCol("t", col.tabB)
	else
		sCol("t", col.tabT)
		sCol("b", col.tabB)
	end
	sPos(15, 2)
	write(" Other ")
	if tab == 4 then
		sCol("b", col.tabT)
		sCol("t", col.tabB)
	else
		sCol("t", col.tabT)
		sCol("b", col.tabB)
	end
	sPos(22, 2)
	write(" Exit ")

	if rrst then
		row = 1
		dispRS = nil
	end

	sCol("t", col.headT)
	sPos(1, tY - 1)
	sCol("b", col.headB)
	term.clearLine()
	if scrollOption then
		sPos(1, tY)
		sCol("b", col.headB)
		term.clearLine()
		sPos(2, tY)
		write("<- -> Change Value")
		sPos(16, tY)
		cWrite("")
		sPos(39, tY)
		write("ENTER Submit")
	elseif isTextOption then
		sPos(1, tY)
		sCol("b", col.headB)
		term.clearLine()
		sPos(2, tY)
		write("Type text or directory")
		sPos(16, tY)
		cWrite("")
		sPos(39, tY)
		write("ENTER Submit")
	else
		sPos(1, tY)
		sCol("b", col.headB)
		term.clearLine()
		sPos(2, tY)
		write("/\\/ Navigate")
		sPos(16, tY)
		cWrite("<- -> Change Tab")
		sPos(39, tY)
		write("ENTER Change")
	end

	if tab == 1 then
		menuMain(rrst)
	elseif tab == 2 then
		menuShell(rrst)
	elseif tab == 3 then
		menuOther(rrst)
	elseif tab == 4 then
		menuExit(rrst)
	end
	if settings.get("bios.password") then
		dispBP = "[ Enabled ]"
	else
		dispBP = "[ Disabled ]"
	end

	if temp_setting_PCLabel ~= nil then
		dispOSL = temp_setting_PCLabel
	else
		dispOSL = "[ Not Set ]"
	end

	if settings.get("bios.forceMono") then
		dispFM = "[ Enabled ]"
	else
		dispFM = "[ Disabled ]"
	end
end

row = 1
rowMn = 1
rowMx = 1
tab = 1
tabMn = 1
tabMx = 4

function reloadSettings()
	-- Set default settings (Settings loading code was copied from main BIOS file)
	settings.set("shell.allow_startup", true)
	settings.set("shell.allow_disk_startup", (commands == nil))
	settings.set("shell.autocomplete", true)
	settings.set("edit.autocomplete", true)
	settings.set("edit.default_extension", "lua")
	settings.set("paint.default_extension", "nfp")
	settings.set("lua.autocomplete", true)
	settings.set("list.show_hidden", false)
	settings.set("motd.enable", false)
	settings.set("motd.path", "/rom/motd.txt:/motd.txt")
	settings.set("bios.password", false)
	settings.set("bios.forceMono", false)
	settings.set("bios.bootDelay", 0.25)
	if term.isColour() then
		settings.set("bios.use_multishell", true)
	end
	if _CC_DEFAULT_SETTINGS then
		for sPair in string.gmatch(_CC_DEFAULT_SETTINGS, "[^,]+") do
			local sName, sValue = string.match(sPair, "([^=]*)=(.*)")
			if sName and sValue then
				local value
				if sValue == "true" then
					value = true
				elseif sValue == "false" then
					value = false
				elseif sValue == "nil" then
					value = nil
				elseif tonumber(sValue) then
					value = tonumber(sValue)
				else
					value = sValue
				end
				if value ~= nil then
					settings.set(sName, value)
				else
					settings.unset(sName)
				end
			end
		end
	end

	-- Load user settings
	if fs.exists("/.settings") then
		settings.load("/.settings")
	end

	if rsBTN then
		dispRS = "Defaults restored"
		setUIColors()
		drawScreen()
		sleep(1)
		dispRS = nil
		rsBTN = nil
		drawScreen()
	end
	if oldBIOSPassword then
		settings.set("bios.password", oldBIOSPassword)
		oldBIOSPassword = nil
		if arg[1] ~= "/r" then
			drawScreen()
		end
	end
end

function core()
	reloadSettings()
	temp_setting_PCLabel = os.getComputerLabel()
	drawScreen(true)
	while true do
		dispS = {}
		dispM = {}
		dispL = {}
		dispB = {}
		dispLt = {}
		dispE = {}
		dispP = {}

		getDisplayValues()

		local event, key = os.pullEvent("key")

		if key == keys.up and row > rowMn then
			row = row - 1
		elseif key == keys.down and row < rowMx then
			row = row + 1
		end

		if key == keys.left and tab > tabMn then
			tab = tab - 1
			drawScreen(true)
		elseif key == keys.right and tab < tabMx then
			tab = tab + 1
			drawScreen(true)
		end

		if key == keys.enter then
			settingsMod()
		end

		drawScreen()

		--if event == "terminate" then error("Program Terminated") end
	end
end
function menuMain(rrst)
	rowMn = 1
	rowMx = 3
	if rrst then
		row = 1
		drawScreen()
	end
	sCol("b", col.fill)
	sCol("t", col.item)
	sPos(2, 4)
	write("System")
	sCol("t", col.item)
	sPos(4, 5)
	write("Operating System")
	sPos(25, 0, true, true)
	print(os.version())
	sCol("t", col.item)
	sPos(4, 6)
	write("System date")
	sPos(25, 0, true, true)
	print(os.date())
	sCol("t", col.item)
	sPos(4, 7)
	write("System ID")
	sPos(25, 0, true, true)
	print(os.getComputerID())
	sCol("t", col.item)
	if row == 1 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 8)
	write("Computer Name")
	sPos(25, 0, true, true)
	print(dispOSL)

	sCol("t", col.item)
	sPos(2, 10)
	write("Setup Utility")
	if row == 2 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 11)
	write("Force Monochrome")
	sPos(25, 0, true, true)
	print(dispFM)
	if row == 3 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 12)
	write("Boot Delay")
	sPos(25, 0, true, true)
	print("[ " .. settings.get("bios.bootDelay") .. " ]")
end
function menuShell(rrst)
	rowMn = 1
	rowMx = 3
	if rrst then
		row = 1
	end

	sCol("b", col.fill)
	if row == 1 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 4)
	write("Diskette Boot")
	sPos(25, 0, true, true)
	print(dispS.allow_disk_startup)
	if row == 2 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 5)
	write("Startup File")
	sPos(25, 0, true, true)
	print(dispS.allow_startup)
	if row == 3 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 6)
	write("Shell Autocomplete")
	sPos(25, 0, true, true)
	print(dispS.autocomplete)
end
function menuOther(rrst)
	rowMn = 1
	rowMx = 8
	if rrst then
		row = 1
		offset1 = 0
	end

	if row >= 5 and row < 7 then
		offset1 = 3
	elseif row >= 7 then
		offset1 = 6
	else
		offset1 = 0
	end

	sCol("b", col.fill)
	if offset1 < 3 then
		sCol("t", col.item)
		sPos(2, 4)
		write("BIOS")
		if row == 1 then
			sCol("t", col.itemS)
		else
			sCol("t", col.itemE)
		end
		sPos(4, 5 - offset1)
		write("Use Multishell")
		sPos(25, 0, true, true)
		print(dispB.use_multishell)
	end

	if offset1 < 6 then
		sCol("t", col.item)
		sPos(2, 7 - offset1)
		write("MOTD")

		if row == 2 then
			sCol("t", col.itemS)
		else
			sCol("t", col.itemE)
		end
		sPos(4, 8 - offset1)
		write("MOTD Enable")
		sPos(25, 0, true, true)
		print(dispM.enable)
	end
	if row == 3 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 9 - offset1)
	write("MOTD Path")
	sPos(25, 0, true, true)
	print(dispM.path)

	sCol("t", col.item)
	sPos(2, 11 - offset1)
	write("Lua")

	if row == 4 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 12 - offset1)
	write("Autocomplete")
	sPos(25, 0, true, true)
	print(dispL.autocomplete)

	sCol("t", col.item)
	sPos(2, 14 - offset1)
	write("Edit")

	if row == 5 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 15 - offset1)
	write("Default Extension")
	sPos(25, 0, true, true)
	print("." .. dispE.default_extension)
	if row == 6 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 16 - offset1)
	write("Autocomplete")
	sPos(25, 0, true, true)
	print(dispE.autocomplete)

	if offset1 >= 3 then
		sCol("t", col.item)
		sPos(2, 18 - offset1)
		write("List")
		if row == 7 then
			sCol("t", col.itemS)
		else
			sCol("t", col.itemE)
		end

		sPos(4, 19 - offset1)
		write("Show Hidden")
		sPos(25, 0, true, true)
		print(dispLt.show_hidden)
	end
	if offset1 >= 6 then
		sCol("t", col.item)
		sPos(2, 21 - offset1)
		write("Paint")
		if row == 8 then
			sCol("t", col.itemS)
		else
			sCol("t", col.itemE)
		end
		sPos(4, 22 - offset1)
		write("Default Extension")
		sPos(25, 0, true, true)
		print("." .. dispP.default_extension)
		if row == 6 then
			sCol("t", col.itemS)
		else
			sCol("t", col.itemE)
		end
	end
end
function menuExit(rrst)
	rowMn = 1
	rowMx = 4
	if rrst then
		row = 1
	end

	sCol("b", col.fill)

	if row == 1 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 4)
	write("Save and exit")
	sPos(25, 0, true, true)
	if row == 2 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 5)
	write("Exit without saving")
	sPos(25, 0, true, true)
	if row == 3 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 7)
	write("Reset settings")
	sPos(25, 0, true, true)
	if dispRS then
		sCol("t", col.msg)
		print(dispRS)
	end
	if row == 4 then
		sCol("t", col.itemS)
	else
		sCol("t", col.itemE)
	end
	sPos(4, 9)
	write("BIOS Password")
	sPos(25, 0, true, true)
	print(dispBP)
end

function settingsMod()
	if tab == 1 then
		if row == 1 then
			textSetting()
			drawScreen()
		elseif row == 2 then
			if settings.get("bios.forceMono") then
				settings.set("bios.forceMono", false)
			else
				settings.set("bios.forceMono", true)
			end
			drawScreen()
		elseif row == 3 then
			textSetting()
		else
			error("Row is outside of bounds!")
		end
	elseif tab == 2 then
		if row == 1 then
			if settings.get("shell.allow_disk_startup") then
				settings.set("shell.allow_disk_startup", false)
			else
				settings.set("shell.allow_disk_startup", true)
			end
		elseif row == 2 then
			if settings.get("shell.allow_startup") then
				settings.set("shell.allow_startup", false)
			else
				settings.set("shell.allow_startup", true)
			end
		elseif row == 3 then
			if settings.get("shell.autocomplete") then
				settings.set("shell.autocomplete", false)
			else
				settings.set("shell.autocomplete", true)
			end
		else
			error("Row is outside of bounds!")
		end
	elseif tab == 3 then
		if row == 1 then
			if settings.get("bios.use_multishell") then
				settings.set("bios.use_multishell", false)
			else
				settings.set("bios.use_multishell", true)
			end
		elseif row == 2 then
			if settings.get("motd.enable") then
				settings.set("motd.enable", false)
			else
				settings.set("motd.enable", true)
			end
		elseif row == 3 then
			textSetting()
		elseif row == 4 then
			if settings.get("lua.autocomplete") then
				settings.set("lua.autocomplete", false)
			else
				settings.set("lua.autocomplete", true)
			end
		elseif row == 5 then
			textSetting()
		elseif row == 6 then
			if settings.get("edit.autocomplete") then
				settings.set("edit.autocomplete", false)
			else
				settings.set("edit.autocomplete", true)
			end
		elseif row == 7 then
			if settings.get("list.show_hidden") then
				settings.set("list.show_hidden", false)
			else
				settings.set("list.show_hidden", true)
			end
		elseif row == 8 then
			textSetting()
		else
			error("Row is outside of bounds!")
		end
	elseif tab == 4 then
		if row == 1 then
			quit(false, "save")
		elseif row == 2 then
			quit(false, "exit")
		elseif row == 3 then
			if confirm("reset") then
				if fs.exists("/.settings") then
					fs.delete("/.settings")
				end
				oldBIOSPassword = settings.get("bios.password")
				os.setComputerLabel()
				temp_setting_PCLabel = nil
				rsBTN = true
				reloadSettings()
			end
		elseif row == 4 then
			changeBiosPassword()
			drawScreen()
		else
			error("Row is outside of bounds!")
		end
	else
		error("An error occured.")
	end
	getDisplayValues()
end
function textSetting()
	if tab == 1 and row == 1 then
		isTextOption = true
		drawScreen()
		sCol("t", col.itemS)
		sPos(4, 8)
		term.clearLine()
		write("Computer Name")
		sPos(25, 0, true, true)
		input = read()
		if input == "" then
			--os.setComputerLabel()
			temp_setting_PCLabel = nil
		else
			--os.setComputerLabel(input)
			temp_setting_PCLabel = input
		end
	elseif tab == 1 and row == 3 then
		scrollOption = true
		drawScreen()
		sCol("t", col.itemS)
		delayTimeSetting = settings.get("bios.bootDelay")
		if delayTimeSetting < 0.25 then
			delayTimeSetting = 0.25
		end
		scroll = delayTimeSetting / 0.25
		scrollMn = 1
		scrollMx = 20
		sPos(4, 12)
		term.clearLine()
		write("Boot Delay")
		sPos(25, 0, true, true)
		write("< " .. delayTimeSetting .. " >")
		key = 0
		while key ~= nil do
			key = nil
			sleep(0.01)
		end
		while true do
			if key == keys.left and scroll > scrollMn then
				scroll = scroll - 1 * scrollMltplyN
				key = nil
			elseif key == keys.right and scroll < scrollMx then
				scroll = scroll + 1 * scrollMltplyP
				key = nil
			elseif key == keys.enter then
				settings.set("bios.bootDelay", delayTimeSetting)
				key = nil
				break
			end
			delayTimeSetting = 0.25 * scroll
			sPos(4, 12)
			term.clearLine()
			write("Boot Delay")
			sPos(25, 0, true, true)
			write("< " .. delayTimeSetting .. " >")
			sleep(0.01)
			if delayTimeSetting == 1 then
				scrollMltplyN = 1
				scrollMltplyP = 4
			elseif delayTimeSetting >= 2 then
				scrollMltplyN = 4
				scrollMltplyP = 4
			else
				scrollMltplyN = 1
				scrollMltplyP = 1
			end
		end
		if delayTimeSetting < 0.25 then
			error("Boot delay cannot be lower than 0.25 seconds.")
		end
		scrollOption = nil
	elseif tab == 3 and row == 3 then
		isTextOption = true
		drawScreen()
		sCol("t", col.itemS)
		sPos(4, 9 - offset1)
		term.clearLine()
		write("MOTD Path")
		sPos(25, 0, true, true)
		input = read()
		settings.set("motd.path", input)
	elseif tab == 3 and row == 5 then
		isTextOption = true
		drawScreen()
		sCol("t", col.itemS)
		sPos(4, 15 - offset1)
		term.clearLine()
		write("Default Extension")
		sPos(25, 0, true, true)
		write(".")
		input = read()
		settings.set("edit.default_extension", input)
	elseif tab == 3 and row == 8 then
		isTextOption = true
		drawScreen()
		sCol("t", col.itemS)
		sPos(4, 22 - offset1)
		term.clearLine()
		write("Default Extension")
		sPos(25, 0, true, true)
		write(".")
		input = read()
		settings.set("paint.default_extension", input)
	end

	isTextOption = nil
end

function getDisplayValues()
	if settings.get("shell.allow_disk_startup") then
		dispS.allow_disk_startup = "[ Enabled ]"
	else
		dispS.allow_disk_startup = "[ Disabled ]"
	end
	if settings.get("motd.enable") then
		dispM.enable = "[ Enabled ]"
	else
		dispM.enable = "[ Disabled ]"
	end
	if settings.get("shell.allow_startup") then
		dispS.allow_startup = "[ Enabled ]"
	else
		dispS.allow_startup = "[ Disabled ]"
	end
	if settings.get("edit.default_extension") and settings.get("edit.default_extension") ~= "" then
		dispE.default_extension = settings.get("edit.default_extension")
	else
		dispE.default_extension = "[ Disabled ]"
	end
	if settings.get("shell.autocomplete") then
		dispS.autocomplete = "[ Enabled ]"
	else
		dispS.autocomplete = "[ Disabled ]"
	end
	if settings.get("lua.autocomplete") then
		dispL.autocomplete = "[ Enabled ]"
	else
		dispL.autocomplete = "[ Disabled ]"
	end
	if settings.get("bios.use_multishell") then
		dispB.use_multishell = "[ Enabled ]"
	else
		dispB.use_multishell = "[ Disabled ]"
	end
	if settings.get("paint.default_extension") then
		dispP.default_extension = settings.get("paint.default_extension")
	else
		dispP.default_extension = "[ Disabled ]"
	end
	if settings.get("motd.path") and settings.get("motd.path") ~= "" then
		dispM.path = settings.get("motd.path")
	else
		dispM.path = "[ nil ]"
	end
	if settings.get("edit.autocomplete") then
		dispE.autocomplete = "[ Enabled ]"
	else
		dispE.autocomplete = "[ Disabled ]"
	end
	if settings.get("list.show_hidden") then
		dispLt.show_hidden = "[ Enabled ]"
	else
		dispLt.show_hidden = "[ Disabled ]"
	end
end

function errorHandle()
	--[[
    while true do
        local ok1, err1 = pcall(pauseStart)
        local ok2, err2 = pcall(menuMain)
        if not ok1 and not ok2 then
            error()
        end
    end
    ]]
end
local function findCloverRoot()
	if fs.exists("/CloverOS_OS.lua") and fs.exists("/CloverOS_API.lua") then
		return "/"
	end

	for i = 0, 99 do
		local root = "/disk" .. (i == 0 and "" or i)
		if fs.exists(root .. "/CloverOS_OS.lua") and fs.exists(root .. "/CloverOS_API.lua") then
			return root
		end
	end

	return "/"
end

local function findPXBOOT(root)
	local candidates = {
		root .. "/boot/pxboot.lua",
		root .. "/pxboot.lua",
		"boot/pxboot.lua",
	}

	for _, path in ipairs(candidates) do
		if fs.exists(path) then
			return path
		end
	end

	return nil
end
local ROOT = findCloverRoot()
local PXBOOT = findPXBOOT(ROOT)
function quit(bypass, method)
	if bypass then
		listenBreak = true
		sCol("b", col.b)
		sCol("t", col.w)
		sPos(1, 1)
		term.clear()
		os.pullEvent = pullEvent
		wait(1.2)
		shell.run(PXBOOT)
		error()
	elseif method == "exit" then
		if confirm(method) then
			quit(true)
		end
	elseif method == "save" then
		if confirm(method) then
			os.setComputerLabel(temp_setting_PCLabel)
			settings.save("/.settings")
			quit(true)
		end
	end
end

function confirm(method)
	key = nil
	sPos(1, 6)
	sCol("b", col.headB)
	sCol("t", col.headT)
	cWrite("                                  ")
	if method == "reset" then
		cWrite("Reset Confirmation")
	else
		cWrite("Quit Confirmation")
	end
	sPos(0, 1, true)
	sCol("b", col.dialogB)
	sCol("t", col.dialogT)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	cWrite("Are you sure that you wish")
	sPos(0, 1, true)
	cWrite("                                  ")
	if method == "exit" then
		cWrite("to discard the changed you've")
	elseif method == "save" then
		cWrite("to save the changes you've")
	elseif method == "reset" then
		cWrite("to reset settings to default?")
	else
		error('"' .. method .. '" is invalid.')
	end
	sPos(0, 1, true)
	cWrite("                                  ")
	if method ~= "reset" then
		cWrite("made?")
	end
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	cWrite("[Y]      [N]")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	while true do
		if key == keys.y then
			return true
		elseif key == keys.n then
			return false
		end
		sleep(0.01)
	end
end

reloadSettings()
setUIColors()

function dialog(lengthmode, headline)
	sPos(1, 6)
	if lengthmode == 1 then
		sPos(0, -1, true)
	end
	sCol("b", col.headB)
	sCol("t", col.headT)
	cWrite("                                  ")
	cWrite(headline)
	sPos(0, 1, true)
	sCol("b", col.dialogB)
	sCol("t", col.dialogT)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	cWrite("                                  ")
	sPos(0, 1, true)
	if lengthmode == 1 then
		cWrite("                                  ")
		sPos(0, 1, true)
		cWrite("                                  ")
		sPos(0, 1, true)
	end
end
function drawBiosPasswordScreen()
	sPos(1, 1)
	sCol("b", col.fill)
	term.clear()
	sCol("t", col.item)
	if failedPassAttempts > 0 then
		write(" " .. failedPassAttempts .. " failed attempts.")
	end
	sPos(2, tY)
	write("DELETE Resume startup")
	sPos(37, tY)
	write("ENTER Password")
	dialog(0, "BIOS Utility Password")
	sPos(0, -5, true, true)
	cWrite("< Enter password >")
	sPos(0, 6, true)
end
function biosPasswordScreen()
	if settings.get("bios.password") then
		failedPassAttempts = 0
		if arg[1] ~= "/b" then
			print("Enter BIOS Password")
			local input
			write("Password: ")
			input = read("*")
			if input == settings.get("bios.password") then
			else
				if term.isColor() then
					sCol("t", 16384)
				end
				print("Incorrect password.")
				error()
			end
			input = nil
		else
			drawBiosPasswordScreen()
			while true do
				input = nil
				if key == keys.enter then
					sPos(1, 1)
					sCol("b", col.fill)
					term.clear()
					dialog(0, "BIOS Utility Password")
					sPos(-33, -2, true)
					if failedPassAttempts > 0 and settings.get("bios.passwordHint") then
						write(settings.get("bios.passwordHint"))
					end
					sPos(10, -3, true, true)
					write("#")
					input = read("*")
					if input == settings.get("bios.password") then
						break
					else
						sPos(1, 1)
						sCol("b", col.fill)
						term.clear()
						dialog(0, "BIOS Utility Password")
						sPos(0, -5, true, true)
						sCol("t", col.err)
						cWrite("Incorrect password.")
						sCol("t", col.dialogT)
						sleep(1)
						failedPassAttempts = failedPassAttempts + 1
					end
					drawBiosPasswordScreen()
				elseif key == keys.delete then
					sPos(1, 1)
					sCol("b", col.fill)
					term.clear()
					dialog(0, "BIOS Utility Password")
					sPos(0, -5, true, true)
					cWrite("Resuming startup...")
					sleep(1)
					sPos(1, 1)
					sCol("b", col.b)
					term.clear()
					error()
				end
				key = nil
				sleep(0.01)
			end
		end
	end
end
if arg[1] ~= "/b" and arg[1] ~= "/?" and arg[1] ~= "help" then
	biosPasswordScreen()
end

function changeBiosPassword()
	local inputExisting = nil
	local inputNew = nil
	local inputNewConfirm = nil
	local isNewPass = nil
	if settings.get("bios.password") then
		dialog(1, "Password Setup")
		sPos(0, -9, true, true)
		cWrite("Enter old password:")
		sPos(10, 1, true, true)
		write("#")
		inputExisting = read("*")
		sPos(0, 1, true, true)
		cWrite("Enter new password:")
		sPos(10, 1, true, true)
		write("#")
		inputNew = read("*")
		sPos(0, 1, true, true)
		cWrite("Re-Enter new password:")
		if inputNew ~= "" then
			sPos(10, 1, true, true)
			write("#")
			inputNewConfirm = read("*")
		end
		drawScreen()
	else
		isNewPass = true
		dialog(0, "Password Setup")
		sPos(0, -7, true, true)
		cWrite("Enter new password:")
		sPos(10, 1, true, true)
		write("#")
		inputNew = read("*")
		sPos(0, 1, true, true)
		cWrite("Re-Enter new password:")
		if inputNew ~= "" then
			sPos(10, 1, true, true)
			write("#")
			inputNewConfirm = read("*")
		end
	end
	drawScreen()
	dialog(0, "Password Setup (Debug)")

	if inputNew == "" then
		inputNewConfirm = inputNew
	end

	failed1 = nil
	failed2 = nil
	sPos(0, -7, true, true)
	if settings.get("bios.password") then
		if inputExisting == settings.get("bios.password") then
			cWrite("Old password: Pass")
		else
			sCol("t", col.err)
			cWrite("Old password: Failed")
			sCol("t", col.dialogT)
			failed1 = true
		end
	end
	if inputNew == inputNewConfirm then
		cWrite("New password: Passed")
	else
		sCol("t", col.err)
		cWrite("New Password: Failed")
		sCol("t", col.dialogT)
		failed2 = true
	end
	if failed1 or failed2 then
		sPos(0, 2, true)
		sCol("t", col.err)
		cWrite("Password could not be updated.")
		sCol("t", col.dialogT)
	end

	drawScreen()
	dialog(0, "Password Setup")
	sPos(0, -5, true, true)
	if failed1 then
		sCol("t", col.err)
		cWrite("Old password was incorrect.")
		sCol("t", col.dialogT)
	elseif failed2 then
		sCol("t", col.err)
		cWrite("Confirmation didn't match.")
		sCol("t", col.dialogT)
	elseif not failed1 and not failed2 and inputNew == settings.get("bios.password") then
		cWrite("Password was not changed.")
	elseif not failed1 and not failed2 and inputNew == "" then
		settings.set("bios.password", false)
		cWrite("Password cleared.")
	elseif not failed1 and not failed2 and isNewPass then
		settings.set("bios.password", inputNew)
		cWrite("Password created.")
	elseif not failed1 and not failed2 then
		settings.set("bios.password", inputNew)
		cWrite("Password updated.")
	end
	sleep(3)
	isNewPass = nil
	getDisplayValues()
	drawScreen()
end

--[[
    ACI Setup Utility
    Copyright (c) 2019-2020 Bradley Johnson "Peekofwar"
    
    https://DomainOfPeekofwar.weebly.com    (old site)
    https://sites.google.com/view/peekofwar (new site)
    https://pastebin.com/u/Peekofwar
]]

--[[ if arg[1] == "/passtest" then changeBiosPassword() error("Aborting main program... This is just a test.") end ]]

if arg[1] == "/b" then
	parallel.waitForAll(pauseStart, listen, pTimer, errorHandle)
elseif arg[1] == "/r" then
	oldBIOSPassword = settings.get("bios.password")
	if fs.exists("/.settings") then
		fs.delete("/.settings")
	end
	reloadSettings()
	settings.save("/.settings")
	os.setComputerLabel()
	print("\nSettings reset.\n")
elseif arg[1] == "help" or arg[1] == "/?" then
	print(
		version
			.. " "
			.. versiondate
			.. '\n\n"/r" - Resets settings\n"/b" - Used by boot programs\n"/m" - Force monochrome / dark mode. Can be used as a second switch\n"/?" or "help" - Shows the help text\n\nRunning this program without arguments will imeadietly open the utility.\n'
	)
elseif arg[1] == "/test" then
	print("Testing total failure message...\n")
else
	parallel.waitForAll(core, listen, errorHandle)
end
if arg[1] ~= "help" and arg[1] ~= "/?" and arg[1] ~= "/r" then
	error(
		"\n\nAn unknown error has occured and the utility program ended abnormally.\n\nIf you continue to have this issue, please contact the author and provide details to reproduce this error.\n"
	)
end
