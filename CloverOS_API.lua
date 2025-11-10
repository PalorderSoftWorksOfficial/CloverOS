local module = {}

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

function mergeTables(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" and type(t1[k]) == "table" then
            mergeTables(t1[k], v)
        else
            t1[k] = v
        end
    end
    return t1
end

function module.example()
    print("This is an example function in CloverOS_API.lua")
end
function module.mirroredPrint(text)
    mirroredPrint(text)
end
function module.mirroredWrite(text)
    mirroredWrite(text)
end
function module.mirroredClear()
    mirroredClear()
end
function module.mirroredSetCursor(x, y)
    mirroredSetCursor(x, y)
end
function module.mirroredRead(hidden)
    return mirroredRead(hidden)
end


mergeTables(GDI, module)

return module