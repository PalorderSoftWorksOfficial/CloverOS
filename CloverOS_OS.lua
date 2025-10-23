-- Setup
local monitor = peripheral.find("monitor")
local modem = peripheral.find("modem")
if modem then
    modem.open(123)
end
if monitor then
    monitor.setTextScale(0.5)
end

local function mirroredPrint(text)
    print(text)
    if monitor then
        local x, y = monitor.getCursorPos()
        monitor.write(text)
        local mx, my = monitor.getCursorPos()
        monitor.setCursorPos(1, my + 1)
    end
end
local function mirroredWrite(text)
    write(text)
    if monitor then
        local x, y = monitor.getCursorPos()
        monitor.write(text)
        monitor.setCursorPos(x + #text, y) -- Move cursor forward by text length
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

local function streamDisplay()
    while true do
        local x, y = monitor.getCursorPos()
        local screenData = monitor.getTextColor() .. monitor.getCursorPos() .. monitor.getTextScale() -- Collecting text and colors for the stream
        modem.transmit(123, 123, screenData) -- Send the data to the ender pocket computer
        os.sleep(0.1)
    end
end

-- Input is only from terminal (not monitor)
local function mirroredRead(hidden)
    if hidden then
        return read("*")
    else
        return read()
    end
end

-- Save session state (for minimization of apps, etc.)
local minimizedApps = {}

local function saveAppState(appName, state)
    minimizedApps[appName] = state
end

local function restoreAppState(appName)
    return minimizedApps[appName]
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
            "[INFO] Loading TRGS system services...",
            "[ OK ] System clock synced.",
            "[FAIL] Bluetooth service not found. Skipping.",
            "[ OK ] Network interface initialized.",
            "[ OK ] TRGS Secure Shell enabled.",
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

-- Games (simple playable versions)
local function playTetris()
    mirroredClear()
    mirroredPrint("Tetris: Use A/D to move, Q to quit.")
    local width, height = 10, 10
    local board = {}
    for y = 1, height do
        board[y] = {}
        for x = 1, width do
            board[y][x] = " "
        end
    end
    local px = math.floor(width / 2)
    local py = 1
    local running = true
    while running do
        mirroredClear()
        for y = 1, height do
            local line = ""
            for x = 1, width do
                if x == px and y == py then
                    line = line .. "O"
                else
                    line = line .. board[y][x]
                end
            end
            mirroredPrint(line)
        end
        mirroredPrint("Controls: [A] Left  [D] Right  [S] Down  [Q] Quit")
        local event, key = os.pullEvent("char")
        if key == "a" and px > 1 then px = px - 1
        elseif key == "d" and px < width then px = px + 1
        elseif key == "s" and py < height then py = py + 1
        elseif key == "q" then running = false
        end
        if py == height then
            board[py][px] = "O"
            px = math.floor(width / 2)
            py = 1
        else
            py = py + 1
        end
    end
    mirroredPrint("Game Over! Press Enter to return.")
    mirroredRead()
end

local function playPong()
    mirroredClear()
    mirroredPrint("Pong: Use W/S to move, Q to quit.")
    local width, height = 20, 8
    local paddleY = math.floor(height / 2)
    local ballX, ballY = math.floor(width / 2), math.floor(height / 2)
    local ballDX, ballDY = 1, 1
    local running = true
    while running do
        mirroredClear()
        for y = 1, height do
            local line = ""
            for x = 1, width do
                if x == 2 and y == paddleY then
                    line = line .. "|"
                elseif x == ballX and y == ballY then
                    line = line .. "O"
                else
                    line = line .. " "
                end
            end
            mirroredPrint(line)
        end
        mirroredPrint("Controls: [W] Up  [S] Down  [Q] Quit")
        local event, key = os.pullEvent("char")
        if key == "w" and paddleY > 1 then paddleY = paddleY - 1
        elseif key == "s" and paddleY < height then paddleY = paddleY + 1
        elseif key == "q" then running = false
        end
        -- Ball movement
        ballX = ballX + ballDX
        ballY = ballY + ballDY
        if ballY <= 1 or ballY >= height then ballDY = -ballDY end
        if ballX <= 2 then
            if ballY == paddleY then
                ballDX = -ballDX
            else
                mirroredPrint("Missed! Game Over. Press Enter to return.")
                mirroredRead()
                running = false
            end
        elseif ballX >= width then
            ballDX = -ballDX
        end
    end
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
    if title then
        GDI.text(x + 2, y, title, colors.cyan, bg)
    end
end

-- Example usage: draw a window
-- GDI.box(2, 2, 36, 10, "My Window", colors.lightGray, colors.black)
-- GDI.text(4, 4, "Hello World!", colors.white, colors.black)

-- Scan for custom apps and icons
local function getCustomApps()
    local appList = {}
    local appDirs = {"apps", "disk/apps"}

    for _, dir in ipairs(appDirs) do
        if fs.exists(dir) then
            for _, file in ipairs(fs.list(dir)) do
                if file:match("%.lua$") or file:match("%.exe$") then
                    local appName = file:gsub("%.lua$", "")
                    local iconPath = dir .. "/" .. appName .. ".ico"
                    local icon = nil
                    if fs.exists(iconPath) then
                        local f = fs.open(iconPath, "r")
                        icon = f.readAll()
                        f.close()
                    end
                    table.insert(appList, {
                        name = appName,
                        icon = icon,
                        run = function()
                            shell.run(dir .. "/" .. file)
                        end
                    })
                end
            end
        end
    end

    return appList
end
-- App Definitions (including games)
local icons = {
    {name = "Clock", run = function()
        while true do
            mirroredClear()
            mirroredPrint("Clock: " .. textutils.formatTime(os.time(), true))
            os.sleep(1)
        end
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
    {name = "Shutdown", run = function()
        mirroredPrint("Shutting down...")
        os.sleep(1)
        os.shutdown()
    end},
{name = "Music Player 🎵", run = function()
    mirroredClear()
    local speaker = peripheral.find("speaker")
    if not speaker then
        mirroredPrint("Error: No speaker attached!")
        mirroredPrint("Press Enter to return.")
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
	{name = "RUINOUS INTNT (corru.observer)", file = "m4.dfpwm"}
    }

    mirroredPrint("🎵 Music Player 🎵")
    mirroredPrint("Select a track to play:")
    for i, track in ipairs(tracks) do
        mirroredPrint(i .. ". " .. track.name)
    end
    mirroredPrint("Type number to play, or 'exit' to return.")
    local choice = mirroredRead()
    if choice == "exit" then return end

    local index = tonumber(choice)
    if index and tracks[index] then
        local filePath = "disk/" .. tracks[index].file  -- Corrected file path
        mirroredPrint("Now playing: " .. tracks[index].name)
        shell.run("speaker", "play", filePath)
        mirroredPrint("Playback finished. Press Enter to return.")
        mirroredRead()
    else
        mirroredPrint("Invalid choice.")
        os.sleep(1.5)
    end
end}
}

-- Add custom apps dynamically
for _, app in ipairs(getCustomApps()) do
    table.insert(icons, app)
end

-- Desktop & Apps
local function drawDesktop()
    mirroredClear()
    mirroredPrint("== Desktop ==")
    for i, icon in ipairs(icons) do
        if icon.icon then
            mirroredPrint(i .. ". " .. icon.name .. " " .. icon.icon)
        else
            mirroredPrint(i .. ". " .. icon.name)
        end
    end
    mirroredPrint("Type number or name:")
end

-- Launcher
local function desktop()
    while true do
        drawDesktop()
        local input = mirroredRead()
        for i, icon in ipairs(icons) do
            if input == tostring(i) or input:lower() == icon.name:lower() then
                icon.run()
                break
            end
        end
    end
end
-- Bootup
login()
simulateLoading()
desktop()
parallel.waitForAny(function() streamDisplay() end)
