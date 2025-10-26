-- Setup
local monitor = peripheral.find("monitor")
local modem = peripheral.find("modem")
if modem then modem.open(123) end
if monitor then monitor.setTextScale(0.5) end

-- Mirrored terminal + monitor functions
local function mirroredPrint(text)
    print(text)
    if monitor then
        local x, y = monitor.getCursorPos()
        monitor.write(text)
        monitor.setCursorPos(1, y + 1)
    end
end

local function mirroredWrite(text)
    write(text)
    if monitor then
        local x, y = monitor.getCursorPos()
        monitor.write(text)
        monitor.setCursorPos(x + #text, y)
    end
end

local function mirroredClear()
    term.clear()
    term.setCursorPos(1, 1)
    if monitor then
        monitor.clear()
        monitor.setCursorPos(1, 1)
    end
end

local function mirroredSetCursor(x, y)
    term.setCursorPos(x, y)
    if monitor then monitor.setCursorPos(x, y) end
end

local function mirroredRead(hidden)
    if hidden then return read("*") else return read() end
end

-- GDI-like drawing API
local GDI = {}

function GDI.setColor(color)
    term.setTextColor(color)
    if monitor then monitor.setTextColor(color) end
end

function GDI.setBGColor(color)
    term.setBackgroundColor(color)
    if monitor then monitor.setBackgroundColor(color) end
end

function GDI.setCursor(x, y)
    term.setCursorPos(x, y)
    if monitor then monitor.setCursorPos(x, y) end
end

function GDI.clear(bg)
    if bg then GDI.setBGColor(bg) end
    term.clear()
    term.setCursorPos(1, 1)
    if monitor then
        monitor.clear()
        monitor.setCursorPos(1, 1)
    end
end

function GDI.text(x, y, str, fg, bg)
    if fg then GDI.setColor(fg) end
    if bg then GDI.setBGColor(bg) end
    GDI.setCursor(x, y)
    write(str)
    if monitor then
        monitor.setCursorPos(x, y)
        monitor.write(str)
    end
end

function GDI.rect(x, y, w, h, fg, bg)
    for i = 0, h - 1 do
        GDI.text(x, y + i, string.rep(" ", w), fg, bg)
    end
end

function GDI.box(x, y, w, h, title, fg, bg)
    GDI.rect(x, y, w, h, fg, bg)
    GDI.text(x, y, "+" .. string.rep("-", w - 2) .. "+", fg, bg)
    for i = 1, h - 2 do
        GDI.text(x, y + i, "|" .. string.rep(" ", w - 2) .. "|", fg, bg)
    end
    GDI.text(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", fg, bg)
    if title then GDI.text(x + 2, y, title, colors.cyan, bg) end
end

-- Stream display (send monitor contents to modem)
local function streamDisplay()
    if not monitor or not modem then return end
    while true do
        local x, y = monitor.getCursorPos()
        local screenData = monitor.getTextColor() .. monitor.getCursorPos() .. monitor.getTextScale()
        modem.transmit(123, 123, screenData)
        os.sleep(0.1)
    end
end

-- Login screen
local function login()
    mirroredClear()
    mirroredSetCursor(1, 1)
    mirroredPrint("Welcome to the system")
    mirroredPrint("Please enter your username:")
    local username = mirroredRead()
    mirroredPrint("Please enter your password:")
    local password = mirroredRead(true)

    if username == "user" and password == "pass" then
        mirroredPrint("Login successful!")
    else
        mirroredPrint("Invalid credentials. Try again.")
        os.sleep(2)
        login()
    end
end

-- Loading screen
local function simulateLoading()
    local function glitchyType(text, delay)
        delay = delay or 0.02
        for i = 1, #text do
            mirroredWrite(text:sub(i, i))
            os.sleep(delay + math.random() * 0.01)
        end
        mirroredPrint("")
    end

    local function splash()
        mirroredClear()
        mirroredSetCursor(1, 1)
        term.setTextColor(colors.green)
        mirroredPrint([[ 
   _____   _____   _____   ____   ____   _____ 
  |  __ \ |  __ \ |  __ \ |  _ \ / __ \ / ____|
  | |__) || |__) || |__) || |_) | |  | | (___  
  |  ___/ |  ___/ |  ___/ |  _ <| |  | |\___ \ 
  | |     | |     | |     | |_) | |__| |____) |
  |_|     |_|     |_|     |____/ \____/|_____/ 
                Clover OS v1.3
        ]])
        term.setTextColor(colors.white)
        os.sleep(2)
    end

    local function loadingMessages()
        local logs = {
            "[BOOT] Initializing kernel modules...",
            "[ OK ] Mounted virtual filesystem.",
            "[INFO] Loading CloverOS system services...",
            "[ OK ] System clock synced.",
            "[FAIL] Bluetooth service not found. Skipping.",
            "[ OK ] Network interface initialized.",
            "[ OK ] CloverOS Secure Shell enabled.",
            "[ OK ] Environment variables set.",
            "[WARN] Thermal sensor driver outdated.",
            "[ OK ] All critical systems operational.",
        }

        for _, msg in ipairs(logs) do
            mirroredSetCursor(1, 10)
            term.setTextColor(colors.gray)
            mirroredClear()
            term.setTextColor(
                msg:find("%[FAIL%]") and colors.red or
                msg:find("%[WARN%]") and colors.orange or
                msg:find("%[OK%]") and colors.lime or
                colors.white
            )
            glitchyType(msg, 0.01 + math.random() * 0.02)
            os.sleep(0.3)
        end
        term.setTextColor(colors.white)
    end

    local function loadingBar()
        mirroredSetCursor(1, 17)
        term.setTextColor(colors.lightGray)
        mirroredPrint("Loading Clover OS modules:")
        mirroredSetCursor(1, 18)
        term.setTextColor(colors.green)
        local barLength = 35
        for i = 1, barLength do
            mirroredWrite("=")
            os.sleep(0.05 + math.random() * 0.03)
        end
        mirroredWrite(" [")
        term.setTextColor(colors.lime)
        mirroredWrite("✔")
        term.setTextColor(colors.green)
        mirroredWrite("]")
        mirroredPrint("")
        term.setTextColor(colors.white)
    end

    local function finished()
        mirroredSetCursor(1, 20)
        term.setTextColor(colors.white)
        mirroredPrint("Welcome to Clover OS. All systems are nominal.")
        os.sleep(1)
    end

    splash()
    mirroredClear()
    mirroredSetCursor(1, 1)
    glitchyType(">> Booting Clover OS...", 0.05)
    os.sleep(0.5)
    loadingMessages()
    loadingBar()
    finished()
end

-- File Manager
local function fileManager()
    mirroredClear()
    mirroredSetCursor(1, 1)
    mirroredPrint("Welcome to the File Manager")

    local files = fs.list("/")
    for i, file in ipairs(files) do
        mirroredPrint(i .. ". " .. file)
    end

    mirroredPrint("Enter file number to view/edit/delete, or 'exit' to return.")
    local choice = mirroredRead()
    if choice == "exit" then return end

    local fileIndex = tonumber(choice)
    if fileIndex and files[fileIndex] then
        local fileName = files[fileIndex]
        mirroredPrint("Options for file: " .. fileName)
        mirroredPrint("1. View\n2. Edit\n3. Delete")
        local action = mirroredRead()
        if action == "1" then
            mirroredClear()
            mirroredPrint("Contents of " .. fileName .. ":")
            local file = fs.open(fileName, "r")
            mirroredPrint(file.readAll())
            file.close()
            mirroredPrint("Press Enter to return.")
            mirroredRead()
        elseif action == "2" then
            mirroredClear()
            mirroredPrint("Editing " .. fileName)
            mirroredPrint("Type new contents. End with a single 'exit' line.")
            local newText = ""
            while true do
                local line = read()
                if line == "exit" then break end
                newText = newText .. line .. "\n"
            end
            local file = fs.open(fileName, "w")
            file.write(newText)
            file.close()
            mirroredPrint("File updated.")
            os.sleep(1)
        elseif action == "3" then
            fs.delete(fileName)
            mirroredPrint("File deleted.")
            os.sleep(1)
        end
    end
end
-- CMD terminal
local function cmd()
    mirroredClear()
    mirroredPrint("Clover OS Command Prompt.")

    local function listCommands()
        local commands = {}
        local paths = {"disk/bin", "disk2/bin", "disk3/bin", "disk4/bin", "disk5/bin", "bin"}

        for _, path in ipairs(paths) do
            if fs.exists(path) then
                for _, file in ipairs(fs.list(path)) do
                    if file:match("%.lua$") or file:match("%.exe$") or file:match("%.dll$") then
                        local cmdName = file:gsub("%..+$", "") -- remove extension
                        commands[cmdName] = path .. "/" .. file
                    end
                end
            end
        end

        return commands
    end

    while true do
        mirroredWrite("> ")
        local input = mirroredRead()

        if input == "exit" then break end
        if input == "" then goto continue end

        local parts = {}
        for word in input:gmatch("%S+") do
            table.insert(parts, word)
        end

        local command = table.remove(parts, 1)
        local commands = listCommands()

        if commands[command] then
            local cmdPath = commands[command]
            shell.run(cmdPath, table.unpack(parts))
        else
            print("Command not found: " .. command)
        end

        ::continue::
    end
end
-- Simple games and apps
local function playTetris()
    mirroredClear()
    mirroredPrint("Tetris: Use A/D to move, Q to quit.")
    local width, height = 10, 10
    local board = {}
    for y = 1, height do
        board[y] = {}
        for x = 1, width do board[y][x] = " " end
    end
    local px, py = math.floor(width / 2), 1
    local running = true
    while running do
        mirroredClear()
        for y = 1, height do
            local line = ""
            for x = 1, width do
                line = line .. ((x == px and y == py) and "O" or board[y][x])
            end
            mirroredPrint(line)
        end
        mirroredPrint("Controls: [A] Left  [D] Right  [S] Down  [Q] Quit")
        local event, key = os.pullEvent("char")
        if key == "a" and px > 1 then px = px - 1
        elseif key == "d" and px < width then px = px + 1
        elseif key == "s" and py < height then py = py + 1
        elseif key == "q" then running = false end
        if py == height then
            board[py][px] = "O"
            px, py = math.floor(width / 2), 1
        else py = py + 1 end
    end
    mirroredPrint("Game Over! Press Enter to return.")
    mirroredRead()
end

local function playPong()
    local width, height = 20, 8
    local paddleY = math.floor(height / 2)
    local ballX, ballY = math.floor(width / 2), math.floor(height / 2)
    local ballDX, ballDY = 1, 1
    local running = true

    local function draw()
        GDI.clear(colors.black)
        GDI.text(2, paddleY, "|", colors.white, colors.black)
        GDI.text(ballX, ballY, "O", colors.red, colors.black)
        for x = 1, width do
            GDI.text(x, 1, "-", colors.gray, colors.black)
            GDI.text(x, height, "-", colors.gray, colors.black)
        end
        GDI.text(1, height + 1, "Controls: [W] Up  [S] Down  [Q] Quit", colors.white, colors.black)
    end

    draw()
    while running do
        local event, key = os.pullEvent("char")
        if key == "w" and paddleY > 2 then paddleY = paddleY - 1
        elseif key == "s" and paddleY < height - 1 then paddleY = paddleY + 1
        elseif key == "q" then running = false end

        ballX = ballX + ballDX
        ballY = ballY + ballDY

        if ballY <= 2 or ballY >= height - 1 then ballDY = -ballDY end
        if ballX <= 2 then
            if ballY == paddleY then ballDX = -ballDX
            else GDI.clear(colors.black) GDI.text(1,1,"Missed! Game Over. Press Enter to return.",colors.red,colors.black) read() running=false end
        end
        if ballX >= width then ballDX = -ballDX end
        draw()
    end
end

-- Desktop & Apps
local icons = {
    {name = "Clock", run = function()
        while true do mirroredClear() mirroredPrint("Clock: " .. textutils.formatTime(os.time(), true)) os.sleep(1) end
    end},
    {name = "CC-Tweaked Terminal", run = function()
        mirroredClear()
        mirroredPrint("CC-Tweaked Terminal")
        while true do
            mirroredWrite("> ")
            local cmd = mirroredRead()
            if cmd == "exit" then break end
            shell.run(cmd)
        end
    end},
    {name = "Game: Tetris", run = playTetris},
    {name = "Game: Pong", run = playPong},
    {name = "File Manager", run = fileManager},
    {name = "Shutdown", run = function() mirroredPrint("Shutting down...") os.sleep(1) os.shutdown() end},
    {name = "Music Player", run = function()
	mirroredClear()
	local speakers = {}
	for _, name in pairs(peripheral.getNames()) do
		if peripheral.getType(name) == "speaker" then
			table.insert(speakers, peripheral.wrap(name))
		end
	end

	if #speakers == 0 then
		mirroredPrint("Error: No speakers attached! Press Enter to return.")
		mirroredRead()
		return
	end

	local tracks = {
		{name = "Hunt in the dark - Sapheria_xplicit", file = "m1.dfpwm"},
		{name = "BFDI OST - Lickie", file = "BFDI_OST_Lickie.dfpwm"},
		{name = "Joke", file = "joke.dfpwm"},
		{name = "Panic Track", file = "Panic_Track.dfpwm"},
		{name = "zero-project - Gothic (2020 version)", file = "gothic.dfpwm"},
		{name = "145 (Poodles) by Jake Chudnow [HD]", file = "m2.dfpwm"},
		{name = "Let There Be Chaos - (Chaos Insurgency Raid Theme)", file = "m3.dfpwm"},
		{name = "RUINOUS INTNT (corru.observer)", file = "m4.dfpwm"},
		{name = "PuzzlePark WOTFI 2024 by SMG4", file = "m5.dfpwm"},
	}

	mirroredPrint("Music Player")
	mirroredPrint("Select a track to play:")
	for i, track in ipairs(tracks) do
		mirroredPrint(i .. ". " .. track.name)
	end
	mirroredPrint("Type number to play, or 'exit' to return.")
	local choice = mirroredRead()
	if choice == "exit" then return end

	local index = tonumber(choice)
	if index and tracks[index] then
		local basePath=(fs.exists("/etc/music") and "/etc/music") or (function()for i=0,99 do local d=(i==0 and "disk" or "disk"..i).."/etc/music" if fs.exists(d) then return d end end end)()
		local filePath = fs.combine(basePath, tracks[index].file)

		if not fs.exists(filePath) then
			mirroredPrint("File not found: " .. filePath)
			os.sleep(1.5)
			return
		end

		mirroredPrint("Now playing: " .. tracks[index].name)
		local decoder = require("cc.audio.dfpwm").make_decoder()
		local file = fs.open(filePath, "rb")

		while true do
			local chunk = file.read(16 * 1024)
			if not chunk then break end
			local decoded = decoder(chunk)

			local allDone
			repeat
				allDone = true
				for _, speaker in ipairs(speakers) do
					if not speaker.playAudio(decoded) then
						allDone = false
					end
				end
				if not allDone then os.sleep(0) end
			until allDone
		end

		file.close()
		mirroredPrint("Playback finished. Press Enter to return.")
		mirroredRead()
	else
		mirroredPrint("Invalid choice.")
		os.sleep(1.5)
	end
end},
{name = "cmd", run = function() cmd() end}
}

-- Scan for custom apps
local function getCustomApps()
    local appList = {}
    local appDirs = {"apps","disk/apps","disk2/apps","disk3/apps","disk4/apps","disk5/apps","disk6/apps"}
    for _, dir in ipairs(appDirs) do
        if fs.exists(dir) then
            for _, file in ipairs(fs.list(dir)) do
                if file:match("%.[lL][uU][aA]$") or file:match("%.[eE][xX][eE]$") then
                    local appName = file:gsub("%..+$","")
                    table.insert(appList,{
                        name = appName,
                        run = function() shell.run(dir.."/"..file) end
                    })
                end
            end
        end
    end
    return appList
end

for _, app in ipairs(getCustomApps()) do table.insert(icons, app) end

-- Desktop launcher
local function drawDesktop()
    mirroredClear()
    mirroredPrint("== Desktop ==")
    for i, icon in ipairs(icons) do
        mirroredPrint(i .. ". " .. icon.name)
    end
    mirroredPrint("Type number, name, or click an icon:")
end

local function getClickedIcon(x, y)
    -- Icons start from line 2 (after "== Desktop ==")
    local line = y - 1
    if line >= 1 and line <= #icons then
        return icons[line]
    end
    return nil
end

local function desktop()
    while true do
        drawDesktop()
        local event, button, x, y = os.pullEvent()

        if event == "mouse_click" then
            local clickedIcon = getClickedIcon(x, y)
            if clickedIcon then
                clickedIcon.run()
            end
        elseif event == "key" then
            local input = mirroredRead()
            for i, icon in ipairs(icons) do
                if input == tostring(i) or input:lower() == icon.name:lower() then
                    icon.run()
                    break
                end
            end
        end
    end
end
-- Bootup
login()
simulateLoading()
desktop()
term.setCursorBlink(true)
parallel.waitForAny(function() streamDisplay() end)
