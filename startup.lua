local filePath=(function()for i=0,99 do local d="disk"..(i==0 and""or i)if fs.exists(d.."/instructions.txt")then return d.."/instructions.txt"end end if fs.exists("/instructions.txt")then return"/instructions.txt"end return"/etc/instructions.txt"end)()

if fs.exists(filePath) then
    local file = fs.open(filePath, "r")
    local content = file.readAll()
    file.close()
    term.clear()
    term.setCursorPos(1, 1)
    print(content)
    
    print("\nAuto booting CloverOS in 10 seconds...")
    os.sleep(10)
    shell.run((function()
        for i=0,99 do
            local d = "disk"..(i==0 and "" or i)
            if fs.exists(d.."/CloverOS_OS.lua") then return d.."/CloverOS_OS.lua" end
        end
        if fs.exists("/CloverOS_OS.lua") then return "/CloverOS_OS.lua" end
    end)())
else
    print("Instructions file not found. Please ensure the disk is inserted correctly.")
end

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
osAPI = {
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
osAPI = osAPI