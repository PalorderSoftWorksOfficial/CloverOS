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
    mirroredWrite(str)
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
    local running = shell and shell.getRunningProgram and shell.getRunningProgram() or ""
    local dir = (running ~= "" and fs.getDir(running)) or ""
    local authPath = (dir == "" or dir == ".") and "auth" or (dir:sub(-1) == "/" and dir.."auth" or dir.."/auth")

    local function loadAuth()
        if not fs.exists(authPath) then return nil end
        local f = fs.open(authPath, "r")
        if not f then return nil end
        local ok, t = pcall(textutils.unserialize, f.readAll())
        f.close()
        if ok and type(t) == "table" and t.user and t.pass then return t end
        return nil
    end

    local function saveAuth(user, pass)
        local f = fs.open(authPath, "w")
        f.write(textutils.serialize({ user = tostring(user), pass = tostring(pass) }))
        f.close()
    end

    local auth = loadAuth()
    if not auth then
        GDI.clear(colors.black)
        local w,h = term.getSize()
        local bw,bh = 40,10
        local bx,by = math.floor((w-bw)/2)+1, math.floor((h-bh)/2)+1
        GDI.box(bx,by,bw,bh," Setup ",colors.white,colors.blue)
        GDI.text(bx+2,by+2,"New Username: ",colors.white,colors.blue)
        GDI.setCursor(bx+17,by+2)
        local newUser = mirroredRead(true) or ""
        GDI.text(bx+2,by+4,"New Password: ",colors.white,colors.blue)
        GDI.setCursor(bx+17,by+4)
        local newPass = mirroredRead(true) or ""
        saveAuth(newUser, newPass)
        GDI.text(bx+2,by+6,"Account created!",colors.white,colors.blue)
        os.sleep(1.5)
        auth = { user = newUser, pass = newPass }
    end

    while true do
        GDI.clear(colors.black)
        local termWidth, termHeight = term.getSize()
        local boxWidth, boxHeight = 40, 10
        local boxX = math.floor((termWidth - boxWidth) / 2) + 1
        local boxY = math.floor((termHeight - boxHeight) / 2) + 1

        GDI.box(boxX, boxY, boxWidth, boxHeight, " Login ", colors.white, colors.blue)

        GDI.text(boxX + 2, boxY + 2, "Username: ", colors.white, colors.blue)
        GDI.setCursor(boxX + 12, boxY + 2)
        local username = mirroredRead(true) or ""

        GDI.text(boxX + 2, boxY + 4, "Password: ", colors.white, colors.blue)
        GDI.setCursor(boxX + 12, boxY + 4)
        local password = mirroredRead(true) or ""

        if username == auth.user and password == auth.pass then
            GDI.text(boxX + 2, boxY + 6, "Login successful!", colors.white, colors.blue)
            GDI.setColor(colors.white)
            GDI.setBGColor(colors.black)
            os.sleep(2)
            return true
        else
            GDI.text(boxX + 2, boxY + 6, "Invalid credentials. Try again.", colors.red, colors.blue)
            os.sleep(2)
        end
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
        mirroredWrite([[ 
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
    while true do
        local w,h = term.getSize()
        local bw,bh = 50, 16
        local bx,by = math.floor((w-bw)/2)+1, math.floor((h-bh)/2)+1

        GDI.clear(colors.black)
        GDI.box(bx, by, bw, bh, " File Manager ", colors.white, colors.blue)

        local files = fs.list("/")
        for i, file in ipairs(files) do
            local label = fs.isDir(file) and (file.."/") or file
            GDI.text(bx+2, by+1+i, i..". "..label, colors.white, colors.blue)
        end

        GDI.text(bx+2, by+bh-3, "Enter number / 'exit': ", colors.white, colors.blue)
        GDI.setCursor(bx+26, by+bh-3)
        local choice = mirroredRead(true)
        if choice == "exit" then return end
        local index = tonumber(choice)

        if index and files[index] then
            local fileName = files[index]
            local fullPath = "/"..fileName
            if fs.isDir(fullPath) then
                GDI.clear(colors.black)
                local dw,dh = 46,14
                local dx,dy = math.floor((w-dw)/2)+1, math.floor((h-dh)/2)+1
                GDI.box(dx, dy, dw, dh, " Directory: "..fileName.." ", colors.white, colors.blue)
                local dirFiles = fs.list(fullPath)
                for i,f in ipairs(dirFiles) do
                    local label = fs.isDir(fs.combine(fullPath, f)) and (f.."/") or f
                    GDI.text(dx+2, dy+1+i, label, colors.white, colors.blue)
                end
                GDI.text(dx+2, dy+dh-2, "Press Enter to return.", colors.white, colors.blue)
                mirroredRead(true)

            else
                GDI.clear(colors.black)
                local fw,fh = 50,14
                local fx,fy = math.floor((w-fw)/2)+1, math.floor((h-fh)/2)+1
                GDI.box(fx, fy, fw, fh, " File: "..fileName.." ", colors.white, colors.blue)
                GDI.text(fx+2, fy+2, "1. View", colors.white, colors.blue)
                GDI.text(fx+2, fy+3, "2. Edit", colors.white, colors.blue)
                GDI.text(fx+2, fy+4, "3. Delete", colors.white, colors.blue)
                GDI.text(fx+2, fy+fh-2, "Select option: ", colors.white, colors.blue)
                GDI.setCursor(fx+17, fy+fh-2)
                local action = mirroredRead(true)

                if action == "1" then
                    GDI.clear(colors.black)
                    local f = fs.open(fullPath, "r")
                    local content = f.readAll()
                    f.close()
                    local vw,vh = 50,16
                    local vx,vy = math.floor((w-vw)/2)+1, math.floor((h-vh)/2)+1
                    GDI.box(vx, vy, vw, vh, " Viewing: "..fileName.." ", colors.white, colors.blue)
                    local lines = {}
                    for line in content:gmatch("[^\r\n]+") do table.insert(lines, line) end
                    for i=1,math.min(#lines,vh-4) do
                        GDI.text(vx+2, vy+1+i, lines[i], colors.white, colors.blue)
                    end
                    GDI.text(vx+2, vy+vh-2, "Press Enter to return.", colors.white, colors.blue)
                    mirroredRead(true)

                elseif action == "2" then
                    GDI.clear(colors.black)
                    local ew,eh = 50,14
                    local ex,ey = math.floor((w-ew)/2)+1, math.floor((h-eh)/2)+1
                    GDI.box(ex, ey, ew, eh, " Editing: "..fileName.." ", colors.white, colors.blue)
                    GDI.text(ex+2, ey+2, "Type new content (end with 'exit'):", colors.white, colors.blue)
                    local newText = ""
                    local yOffset = 3
                    while true do
                        GDI.setCursor(ex+2, ey+yOffset)
                        local line = read()
                        if line == "exit" then break end
                        newText = newText .. line .. "\n"
                        yOffset = yOffset + 1
                    end
                    local f = fs.open(fullPath, "w")
                    f.write(newText)
                    f.close()
                    GDI.text(ex+2, ey+eh-2, "File updated!", colors.white, colors.blue)
                    os.sleep(1)

                elseif action == "3" then
                    fs.delete(fullPath)
                    GDI.text(fx+2, fy+6, "File deleted.", colors.white, colors.blue)
                    os.sleep(1)
                end
            end
        end
    end
end
-- CMD terminal
local function cmd()
    local w,h=term.getSize()
    local function drawWindow()
        mirroredClear()
        mirroredSetCursor(1,1)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        local title=" Clover OS Command Prompt "
        mirroredSetCursor(math.floor((w-#title)/2),1)
        mirroredWrite(title)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        for i=2,h-1 do
            mirroredSetCursor(1,i)
            mirroredWrite(string.rep(" ",w))
        end
        mirroredSetCursor(1,h)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        mirroredWrite(" CloverOS v3.2 | User: root | "..textutils.formatTime(os.time(),true))
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end

    local function listCommands()
        local commands={}
        local paths={"disk/bin","disk2/bin","disk3/bin","disk4/bin","disk5/bin","/bin"}
        for _,path in ipairs(paths) do
            if fs.exists(path) then
                for _,file in ipairs(fs.list(path)) do
                    if file:match("%.lua$") or file:match("%.exe$") or file:match("%.dll$") then
                        commands[file:gsub("%..+$","")]=path.."/"..file
                    end
                end
            end
        end
        return commands
    end

    local running=true
    local builtin={
        help=function()
            local cmds=listCommands()
            for c,_ in pairs(cmds) do mirroredPrint(c) end
            mirroredPrint("exit")
            mirroredPrint("shutdown")
            mirroredPrint("help")
        end,
        exit=function() running=false end,
        shutdown=function() running=false end
    }

    drawWindow()
    mirroredSetCursor(3,3)
    mirroredPrint("Welcome to Clover OS Command Prompt")
    mirroredSetCursor(3,4)
    mirroredPrint("Type 'help' to list available commands")

    while running do
        mirroredWrite("\nroot@CloverOS:~$ ")
        local input=mirroredRead()
        if input=="" then goto continue end
        local parts={}
        for word in input:gmatch("%S+") do table.insert(parts,word) end
        local command=table.remove(parts,1)
        local commands=listCommands()
        if builtin[command] then
            builtin[command](table.unpack(parts))
        elseif commands[command] then
            local ok,err=pcall(function() shell.run(commands[command],table.unpack(parts)) end)
            if not ok then mirroredPrint("Error: "..tostring(err)) end
        else
            mirroredPrint("Command not found: "..tostring(command))
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
    {name="Clock", run=function() while true do mirroredClear() mirroredPrint("Clock: "..textutils.formatTime(os.time(),true)) os.sleep(1) end end},
    {name="CC-Tweaked Terminal", run=function()
        mirroredClear()
        mirroredPrint("CC-Tweaked Terminal")
        while true do
            mirroredWrite("> ")
            local cmd = mirroredRead()
            if cmd == "exit" then break end
            shell.run(cmd)
        end
    end},
    {name="Game: Tetris", run=playTetris},
    {name="Game: Pong", run=playPong},
    {name="File Manager", run=fileManager},
    {name="Shutdown", run=function() mirroredPrint("Shutting down...") os.sleep(1) os.shutdown() end},
    {name = "Music Player", run = function()
	local w,h = term.getSize()
	GDI.clear(colors.black)
	local bw,bh = 60,20
	local bx,by = math.floor((w-bw)/2)+1, math.floor((h-bh)/2)+1
	GDI.box(bx,by,bw,bh," Music Player ", colors.white, colors.blue)

	local speakers = {}
	for _,name in pairs(peripheral.getNames()) do
		if peripheral.getType(name)=="speaker" then table.insert(speakers, peripheral.wrap(name)) end
	end
	if #speakers==0 then
		GDI.text(bx+2,by+2,"Error: No speakers attached!", colors.red, colors.blue)
		GDI.text(bx+2,by+4,"Press Enter to return.", colors.white, colors.blue)
		mirroredRead()
		return
	end

	local tracks={
		{name="Hunt in the dark - Sapheria_xplicit",file="m1.dfpwm"},
		{name="BFDI OST - Lickie",file="BFDI_OST_Lickie.dfpwm"},
		{name="Joke",file="joke.dfpwm"},
		{name="Panic Track",file="Panic_Track.dfpwm"},
		{name="zero-project - Gothic (2020 version)",file="gothic.dfpwm"},
		{name="145 (Poodles) by Jake Chudnow [HD]",file="m2.dfpwm"},
		{name="Let There Be Chaos - (Chaos Insurgency Raid Theme)",file="m3.dfpwm"},
		{name="RUINOUS INTNT (corru.observer)",file="m4.dfpwm"},
		{name="PuzzlePark WOTFI 2024 by SMG4",file="m5.dfpwm"},
	}

	for i,track in ipairs(tracks) do
		GDI.text(bx+2,by+1+i,i..". "..track.name, colors.white, colors.blue)
	end
	GDI.text(bx+2,by+bh-3,"Type number to play, or 'exit' to return.", colors.white, colors.blue)
	GDI.setCursor(bx+2,by+bh-2)
	local choice = mirroredRead()
	if choice=="exit" then return end
	local index=tonumber(choice)
	if index and tracks[index] then
		local basePath=(fs.exists("/etc/music") and "/etc/music") or (function() for i=0,99 do local d=(i==0 and "disk" or "disk"..i).."/etc/music" if fs.exists(d) then return d end end end)()
		local filePath=fs.combine(basePath,tracks[index].file)
		if not fs.exists(filePath) then
			GDI.text(bx+2,by+2,"File not found: "..filePath, colors.red, colors.blue)
			os.sleep(1.5)
			return
		end
		GDI.text(bx+2,by+2,"Now playing: "..tracks[index].name, colors.green, colors.blue)
		local decoder=require("cc.audio.dfpwm").make_decoder()
		local file=fs.open(filePath,"rb")
		while true do
			local chunk=file.read(16*1024)
			if not chunk then break end
			local decoded=decoder(chunk)
			local allDone
			repeat
				allDone=true
				for _,speaker in ipairs(speakers) do
					if not speaker.playAudio(decoded) then allDone=false end
				end
				if not allDone then os.sleep(0) end
			until allDone
		end
		file.close()
		GDI.text(bx+2,by+4,"Playback finished. Press Enter to return.", colors.white, colors.blue)
		mirroredRead()
	else
		GDI.text(bx+2,by+2,"Invalid choice.", colors.red, colors.blue)
		os.sleep(1.5)
	end
end},
    {name="cmd", run=function() cmd() end}
}

local function getCustomApps()
    local appList={}
    local appDirs={"apps","disk/apps","disk2/apps","disk3/apps","disk4/apps","disk5/apps","disk6/apps"}
    for _,dir in ipairs(appDirs) do
        if fs.exists(dir) then
            for _,file in ipairs(fs.list(dir)) do
                if file:match("%.[lL][uU][aA]$") or file:match("%.[eE][xX][eE]$") then
                    local appName=file:gsub("%..+$","")
                    table.insert(appList,{name=appName,run=function() shell.run(dir.."/"..file) end})
                end
            end
        end
    end
    return appList
end

local function desktop()
    for _, app in ipairs(getCustomApps()) do table.insert(icons, app) end

    while true do
        mirroredClear()
        mirroredPrint("== Desktop ==")
        for i, icon in ipairs(icons) do
            mirroredPrint(i .. ". " .. icon.name)
        end
        mirroredPrint("Type number or app name, or click an icon:")

        local event, button, x, y = os.pullEvent()
        if event == "mouse_click" then
            local line = y - 1
            if line >= 1 and line <= #icons then
                icons[line].run()
            end
        elseif event == "key" then
            mirroredSetCursor(1, #icons + 4)
            local input = mirroredRead():lower()
            local matched = false
            for i, icon in ipairs(icons) do
                if input == tostring(i) or input:lower() == icon.name:lower() then
                    icon.run()
                    matched = true
                    break
                end
            end
            if not matched then
                mirroredPrint("No app found with that number or name.")
                os.sleep(1.5)
            end
        end
    end
end
-- Bootup
simulateLoading()
login()
desktop()
term.setCursorBlink(true)
parallel.waitForAny(function() streamDisplay() end)
