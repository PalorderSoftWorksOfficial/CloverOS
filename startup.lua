local filePath=(function()for i=0,99 do local d="disk"..(i==0 and""or i)if fs.exists(d.."/instructions.txt")then return d.."/instructions.txt"end end if fs.exists("/instructions.txt")then return"/instructions.txt"end return"/etc/instructions.txt"end)()

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
local DISK_ROOT = (function()
    for i=0,99 do
        local d="disk"..(i==0 and "" or i)
        if fs.exists("/"..d) then return "/"..d end
    end
    if fs.exists("/") and fs.exists("/CloverOS_OS.lua") then return "/" end
    return nil
end)()
osAPIFunc = {
   version = function ()
    return "CloverOS v1.0.0"
   end,
    author = function ()
     return "CloverOS Team"
    end,
    runInstaller = function ()
    shell.run("wget run https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua")
    end,
    GDI = GDI,
}
osAPI = osAPIFunc
GDI = osAPI.GDI
os.sleep(1)
if not DISK_ROOT then
    print("Error: could not detect running disk or root installation")
    return
end
if settings.get("emulator") == true then
    GDI.clear(colors.black)
    GDI.box(10, 5, 60, 15, "CloverOS Emulator Detected", colors.white, colors.blue)
    GDI.text(12, 7, "CloverOS is running in an emulated environment.", colors.white, colors.blue)
    GDI.text(12, 9, "Some features may not work as expected, We will install emulator toolkits.", colors.white, colors.blue)
    GDI.text(12, 11, "Press any key to continue...", colors.yellow, colors.blue)
    os.pullEvent("key")
    local DISK_ROOT = (function()
    for i=0,99 do
        local d="disk"..(i==0 and "" or i)
        if fs.exists("/"..d) then return "/"..d end
    end
    if fs.exists("/") and fs.exists("/CloverOS_OS.lua") then return "/" end
    return nil
    end)()

    if not DISK_ROOT then
        print("Error: could not detect running disk or root installation, cannot proceed with installing emulator toolkits.")
        return
    end
    shell.run(DISK_ROOT.."/bin/apt fetch ccemux")
    shell.run(DISK_ROOT.."/bin/apt install ccemux")
    shell.run(DISK_ROOT.."/bin/apt fetch all")
    shell.run(DISK_ROOT.."/bin/apt install all")
elseif settings.get("turtle") == true then
    GDI.clear(colors.black)
    GDI.box(10, 5, 60, 15, "CloverOS Turtle Detected", colors.white, colors.green)
    GDI.text(12, 7, "CloverOS is running on a Turtle.", colors.white, colors.green)
    GDI.text(12, 9, "Some features may not work as expected, We will install turtle toolkits.", colors.white, colors.green)
    GDI.text(12, 11, "Press any key to continue...", colors.yellow, colors.green)
    os.pullEvent("key")
    shell.run(DISK_ROOT.."/bin/apt install all")
elseif settings.get("softinstall") == true then
    GDI.clear(colors.black)
    GDI.box(10, 5, 60, 15, "CloverOS Soft Installation Detected", colors.white, colors.magenta)
    GDI.text(12, 7, "CloverOS is running a soft installation.", colors.white, colors.magenta)
    GDI.text(12, 9, "Some features may not work as expected, We dont have any toolkit for softinstall's", colors.white, colors.magenta)
    GDI.text(12, 11, "Press any key to continue...", colors.yellow, colors.magenta)
    os.pullEvent("key")
    shell.run(DISK_ROOT.."/bin/apt fetch all")
    shell.run(DISK_ROOT.."/bin/apt install all")
elseif settings.get("default") == true then
    shell.run(DISK_ROOT.."/bin/apt install all")
end
if fs.exists(filePath) and settings.get("manualshown") == false then
    local file = fs.open(filePath, "r")
    local content = file.readAll()
    file.close()
    term.clear()
    term.setCursorPos(1, 1)
    settings.set("manualshown", true)
    shell.run("edit "..filePath)
    
    print("\nAuto booting CloverOS in 10 seconds...")
    os.sleep(10)
    shell.run((function()
        for i=0,99 do
            local d = "disk"..(i==0 and "" or i)
            if fs.exists(d.."/CloverOS_OS.lua") then return d.."/CloverOS_OS.lua" end
        end
        if fs.exists("/CloverOS_OS.lua") then return "/CloverOS_OS.lua" end
    end)())
elseif fs.exists(filePath) == false then
    print("Instructions file not found. Please ensure the disk is inserted correctly.")
end