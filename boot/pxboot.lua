if not (fs or term or os.pullEvent) then error("This program must be run from CraftOS.") end

local expect = require "cc.expect"
if not getmetatable(expect) then
    setmetatable(expect, { __call = function(self, ...) return self.expect(...) end })
elseif not getmetatable(expect).__call then
    getmetatable(expect).__call = function(self, ...) return self.expect(...) end
end

local entries = {}
local entry_names = {}
local bootcfg = {}
local cmds = {}
local userGlobals = {}
local monitor
local config
local runningDir

local function unbios(path, ...)
    local old_dofile = _G.dofile
    local kernelArgs = table.pack(...)
    local keptAPIs = { bit32 = true, bit = true, ccemux = true, config = true, coroutine = true, debug = true, ffi = true, fs = true, http = true, io = true, jit = true, mounter = true, os = true, periphemu = true, peripheral = true, redstone = true, rs = true, term = true, utf8 = true, _HOST = true, _CC_DEFAULT_SETTINGS = true, _CC_DISABLE_LUA51_FEATURES = true, _VERSION = true, assert = true, collectgarbage = true, error = true, gcinfo = true, getfenv = true, getmetatable = true, ipairs = true, load = true, loadstring = true, math = true, newproxy = true, next = true, pairs = true, pcall = true, rawequal = true, rawget = true, rawlen = true, rawset = true, select = true, setfenv = true, setmetatable = true, string = true, table = true, tonumber = true, tostring = true, type = true, unpack = true, xpcall = true, turtle = true, pocket = true, commands = true, _G = true, sound = true }
    local t = {}
    for k in pairs(_G) do
        if not keptAPIs[k] and not userGlobals[k] then t[#t + 1] = k end
    end
    for _, k in ipairs(t) do _G[k] = nil end

    local native = monitor or _G.term.native()
    for _, method in ipairs({ "nativePaletteColor", "nativePaletteColour", "screenshot" }) do
        native[method] = _G.term[method]
    end
    _G.term = native

    if _G.http then
        _G.http.checkURL = _G.http.checkURLAsync
        _G.http.websocket = _G.http.websocketAsync
    end
    if _G.commands then _G.commands = _G.commands.native end
    if _G.turtle then _G.turtle.native, _G.turtle.craft = nil end

    local delete = {
        os = { "version", "pullEventRaw", "pullEvent", "run", "loadAPI", "unloadAPI", "sleep" },
        http = _G.http and
        { "get", "post", "put", "delete", "patch", "options", "head", "trace", "listen", "checkURLAsync",
            "websocketAsync" },
        fs = { "complete", "isDriveRoot" }
    }
    for k, v in pairs(delete) do
        for _, a in ipairs(v) do _G[k][a] = nil end
    end

    local olderror = error
    _G.error = function() end
    _G.term.redirect = function() end

    function _G.term.native()
        _G.term.native = nil
        _G.term.redirect = nil
        _G.error = olderror
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.setCursorPos(1, 1)
        term.setCursorBlink(true)
        term.clear()

        local fn
        if type(path) == "function" then
            fn = path
        else
            local file = fs.open(path, "r")
            if file == nil then
                term.setCursorBlink(false)
                term.setTextColor(colors.red)
                term.write("Could not find kernel. pxboot cannot continue.")
                term.setCursorPos(1, 2)
                term.write("Press any key to continue")
                coroutine.yield("key")
                os.shutdown()
            end
            local err
            fn, err = loadstring(file.readAll(), "=kernel")
            file.close()
            if fn == nil then
                term.setCursorBlink(false)
                term.setTextColor(colors.red)
                term.write("Could not load kernel. pxboot cannot continue.")
                term.setCursorPos(1, 2)
                term.write(err)
                term.setCursorPos(1, 3)
                term.write("Press any key to continue")
                coroutine.yield("key")
                os.shutdown()
            end
        end

        setfenv(fn, _G)
        local oldshutdown = os.shutdown
        os.shutdown = function()
            os.shutdown = oldshutdown
            return fn(table.unpack(kernelArgs, 1, kernelArgs.n))
        end
    end

    if debug then
        local function restoreValue(tab, idx, name, hint)
            local i, key, value = 1, debug.getupvalue(tab[idx], hint)
            while key ~= name and not (key == nil and i > 1) do
                key, value = debug.getupvalue(tab[idx], i)
                i = i + 1
            end
            tab[idx] = value or tab[idx]
        end
        restoreValue(_G, "loadstring", "nativeloadstring", 1)
        restoreValue(_G, "load", "nativeload", 5)
        if http then restoreValue(http, "request", "nativeHTTPRequest", 3) end
        restoreValue(os, "shutdown", "nativeShutdown", 1)
        restoreValue(os, "reboot", "nativeReboot", 1)
        if turtle then
            restoreValue(turtle, "equipLeft", "v", 1)
            restoreValue(turtle, "equipRight", "v", 1)
        end
        do
            local i, key, value = 1, debug.getupvalue(peripheral.isPresent, 2)
            while key ~= "native" and key ~= nil do
                key, value = debug.getupvalue(peripheral.isPresent, i)
                i = i + 1
            end
            _G.peripheral = value or peripheral
        end
        if debug.getupvalue(old_dofile, 2) == "status" then
            local _, status = debug.getupvalue(old_dofile, 2)
            _, _G.discord = debug.getupvalue(status, 4)
        end
    end

    coroutine.yield()
end

function cmds.kernel(t)
    bootcfg.fn = unbios
    bootcfg.args = { t.path }
end

function cmds.chainloader(t)
    bootcfg.fn = shell and shell.run or function(path, ...) os.run({}, path, ...) end
    bootcfg.args = { t.path }
end

function cmds.craftos(t)
    bootcfg.fn = function()
        term.setTextColor(colors.yellow)
        print(os.version())
        term.setTextColor(colors.white)
        if settings and settings.get and settings.get("motd.enable") then
            if shell then shell.run("motd") else os.run({}, "/rom/programs/motd.lua") end
        end
    end
    bootcfg.args = {}
end

function cmds.args(t)
    if not bootcfg.args then error("config.lua:" .. t.line .. ": args command must come after boot type", 0) end
    for i = 1, #t.args do bootcfg.args[#bootcfg.args + 1] = t.args[i] end
end

function cmds.global(t)
    _G[t.key] = t.value
    userGlobals[t.key] = true
end

function cmds.monitor(t)
    if peripheral.hasType then
        assert(peripheral.hasType(t.name, "monitor"), "peripheral '" .. t.name .. "' does not exist or is not a monitor")
    else
        assert(peripheral.getType(t.name) == "monitor",
            "peripheral '" .. t.name .. "' does not exist or is not a monitor")
    end
    monitor = peripheral.wrap(t.name)
    term.redirect(monitor)
end

function cmds.insmod(t)
    local path
    if t.name:match "^/" then
        path = t.name
    elseif t.name:find "[/%.]" then
        path = fs.combine(shell and fs.getDir(shell.getRunningProgram()) or "pxboot", t.name)
    else
        path = fs.combine(shell and fs.getDir(shell.getRunningProgram()) or "pxboot", "modules/" .. t.name .. ".lua")
    end
    assert(loadfile(path, nil, setmetatable({
        entries = entries,
        bootcfg = bootcfg,
        cmds = cmds,
        userGlobals = userGlobals,
        unbios = unbios,
        config = config
    }, { __index = _ENV })))(t.args, path)
end

local function boot(entry)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    local nativePalette = term.nativePaletteColor or term.nativePaletteColour
    if nativePalette then
        for i = 0, 15 do term.setPaletteColor(2 ^ i, nativePalette(2 ^ i)) end
    end

    for _, v in ipairs(entry.commands) do
        local ok, err
        if type(v) == "function" then
            ok, err = pcall(v)
        else
            ok, err = pcall(cmds[v.cmd], v)
        end
        if not ok then
            bootcfg = {}
            printError("Could not run boot script: " .. err)
            print("Press any key to continue.")
            os.pullEventRaw("key")
            return false
        end
    end

    if not bootcfg.fn then
        bootcfg = {}
        printError("Could not run boot script: missing boot type command")
        print("Press any key to continue.")
        os.pullEventRaw("key")
        return false
    end

    bootcfg.fn(table.unpack(bootcfg.args))
    return true
end

config = setmetatable({
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.lightGray,
    titlecolor = colors.white,
    boxcolor = colors.gray,
    boxbackground = colors.black,
    selectcolor = colors.blue,
    selecttext = colors.white,
    background = nil,
    defaultentry = "CloverOS",
    timeout = 5,
    style = "phoenix"
}, {
    __index = _ENV,
    __newindex = function(t, k, v)
        rawset(t, k, v)
    end
})

function config.menuentry(name)
    expect(1, name, "string")
    return function(entry)
        expect(2, entry, "table")
        local n = 1
        for i, v in pairs(entry) do
            if type(i) == "number" then n = math.max(i, n) end
        end
        local retval = { name = name, commands = {} }
        for i = 1, n do
            local c = entry[i]
            if (type(c) ~= "table" and type(c) ~= "function") or not c.cmd then
                error("bad command entry #" .. i .. (c == nil and " (unknown command)" or " (missing arguments)"), 2)
            end
            if type(c) == "function" then
                retval.commands[#retval.commands + 1] = c
            elseif c.cmd == "description" then
                retval.description = c.text
            elseif cmds[c.cmd] then
                retval.commands[#retval.commands + 1] = c
            else
                error("bad command entry #" .. i .. " (unknown command " .. c.cmd .. ")", 2)
            end
        end
        entries[#entries + 1] = retval
        entry_names[name] = retval
    end
end

function config.include(path)
    expect(1, path, "string")
    if not path:match "^/" then path = fs.combine(runningDir, path) end
    for _, v in ipairs(fs.find(path)) do
        repeat
            local fn, err = loadfile(v, "t", getfenv(2))
            if not fn then
                printError("Could not load config file: " .. err)
                print("Press any key to continue...")
                os.pullEvent("key")
                break
            end
            local old = runningDir
            runningDir = fs.getDir(v)
            local ok, err = pcall(fn)
            runningDir = old
            if not ok then
                printError("Failed to execute config file: " .. err)
                print("Press any key to continue...")
                os.pullEvent("key")
                break
            end
        until true
    end
end

function config.loadmod(path, args)
    expect(1, path, "string")
    expect(2, args, "table", "nil")
    cmds.insmod({ name = path, args = args, line = debug.getinfo(2, "l").currentline })
end

function config.description(text)
    expect(1, text, "string")
    return { cmd = "description", text = text, line = debug.getinfo(2, "l").currentline }
end

function config.kernel(path)
    expect(1, path, "string")
    return { cmd = "kernel", path = path, line = debug.getinfo(2, "l").currentline }
end

function config.chainloader(path)
    expect(1, path, "string")
    return { cmd = "chainloader", path = path, line = debug.getinfo(2, "l").currentline }
end

function config.args(args)
    expect(1, args, "string", "table")
    if type(args) == "table" then
        return { cmd = "args", args = args, line = debug.getinfo(2, "l").currentline }
    end
    local t = { "" }
    local q
    for c in args:gmatch "." do
        if q then
            if c == q then q = nil else t[#t] = t[#t] .. c end
        elseif c == '"' or c == "'" then
            q = c
        elseif c == ' ' then
            t[#t + 1] = ""
        else
            t[#t] = t[#t] .. c
        end
    end
    local n = 2
    return setmetatable({ cmd = "args", args = t, line = debug.getinfo(2, "l").currentline }, {
        __call = function(self, arg)
            expect(n, arg, "string")
            n = n + 1
            local t2 = self.args
            local q2
            t2[#t2 + 1] = ""
            for c in arg:gmatch "." do
                if q2 then
                    if c == q2 then q2 = nil else t2[#t2] = t2[#t2] .. c end
                elseif c == '"' or c == "'" then
                    q2 = c
                elseif c == ' ' then
                    t2[#t2 + 1] = ""
                else
                    t2[#t2] = t2[#t2] .. c
                end
            end
            return self
        end
    })
end

config.craftos = { cmd = "craftos" }

function config.global(key)
    return function(value)
        return { cmd = "global", key = key, value = value }
    end
end

function config.monitor(name)
    return { cmd = "monitor", name = name }
end

function config.insmod(name)
    expect(1, name, "string")
    return setmetatable({ cmd = "insmod", name = name, line = debug.getinfo(2, "l").currentline }, {
        __call = function(self, args)
            expect(2, args, "table")
            self.args = args
            setmetatable(self, nil)
            return self
        end
    })
end

term.clear()
term.setCursorPos(1, 1)

repeat
    local fn, err = loadfile(
    shell and fs.combine(fs.getDir(shell.getRunningProgram()), "config.lua") or "pxboot/config.lua", "t", config)
    if not fn then
        printError("Could not load config file: " .. err)
        print("Press any key to continue...")
        os.pullEvent("key")
        break
    end
    runningDir = shell and fs.getDir(shell.getRunningProgram()) or "pxboot"
    local ok, err = pcall(fn)
    runningDir = nil
    if not ok then
        printError("Failed to execute config file: " .. err)
        print("Press any key to continue...")
        os.pullEvent("key")
        break
    end
until true

local function runShell()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    if shell then
        shell.run("shell")
    else
        os.run({}, "/rom/programs/shell.lua")
    end
end

if #entries == 0 then return runShell() end

local function hex(n)
    return ("0123456789abcdef"):sub(n, n)
end

local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            merge(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

local styles = {}

local function registerStyle(name, style)
    styles[name] = style
end

registerStyle("phoenix", {
    title = "Phoenix pxboot",
    backgroundcolor = colors.black,
    textcolor = colors.lightGray,
    boxcolor = colors.orange,
    boxbackground = colors.black,
    selectcolor = colors.orange,
    selecttext = colors.black,
    titlecolor = colors.orange,
    helpcolor = colors.lightGray,
    descriptioncolor = colors.white
})

registerStyle("dark", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.white,
    boxcolor = colors.gray,
    boxbackground = colors.black,
    selectcolor = colors.blue,
    selecttext = colors.white,
    titlecolor = colors.white,
    helpcolor = colors.lightGray,
    descriptioncolor = colors.lightGray
})

registerStyle("light", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.white,
    textcolor = colors.black,
    boxcolor = colors.black,
    boxbackground = colors.white,
    selectcolor = colors.blue,
    selecttext = colors.white,
    titlecolor = colors.black,
    helpcolor = colors.gray,
    descriptioncolor = colors.black
})

registerStyle("blue", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.lightBlue,
    boxcolor = colors.blue,
    boxbackground = colors.black,
    selectcolor = colors.blue,
    selecttext = colors.white,
    titlecolor = colors.lightBlue,
    helpcolor = colors.lightBlue,
    descriptioncolor = colors.white
})

registerStyle("red", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.white,
    boxcolor = colors.red,
    boxbackground = colors.black,
    selectcolor = colors.red,
    selecttext = colors.white,
    titlecolor = colors.red,
    helpcolor = colors.lightGray,
    descriptioncolor = colors.white
})

registerStyle("green", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.white,
    boxcolor = colors.green,
    boxbackground = colors.black,
    selectcolor = colors.green,
    selecttext = colors.black,
    titlecolor = colors.green,
    helpcolor = colors.lightGray,
    descriptioncolor = colors.white
})

registerStyle("purple", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.white,
    boxcolor = colors.purple,
    boxbackground = colors.black,
    selectcolor = colors.purple,
    selecttext = colors.white,
    titlecolor = colors.purple,
    helpcolor = colors.lightGray,
    descriptioncolor = colors.white
})

registerStyle("amber", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.lightGray,
    boxcolor = colors.orange,
    boxbackground = colors.black,
    selectcolor = colors.orange,
    selecttext = colors.black,
    titlecolor = colors.orange,
    helpcolor = colors.lightGray,
    descriptioncolor = colors.white
})

registerStyle("graphite", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.gray,
    textcolor = colors.black,
    boxcolor = colors.black,
    boxbackground = colors.lightGray,
    selectcolor = colors.black,
    selecttext = colors.white,
    titlecolor = colors.black,
    helpcolor = colors.gray,
    descriptioncolor = colors.black
})

registerStyle("terminal", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.green,
    boxcolor = colors.green,
    boxbackground = colors.black,
    selectcolor = colors.green,
    selecttext = colors.black,
    titlecolor = colors.green,
    helpcolor = colors.green,
    descriptioncolor = colors.green
})

registerStyle("mono", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.white,
    boxcolor = colors.white,
    boxbackground = colors.black,
    selectcolor = colors.white,
    selecttext = colors.black,
    titlecolor = colors.white,
    helpcolor = colors.lightGray,
    descriptioncolor = colors.white
})

registerStyle("sky", {
    title = "CloverOS Bootloader",
    backgroundcolor = colors.black,
    textcolor = colors.white,
    boxcolor = colors.lightBlue,
    boxbackground = colors.black,
    selectcolor = colors.lightBlue,
    selecttext = colors.black,
    titlecolor = colors.lightBlue,
    helpcolor = colors.lightBlue,
    descriptioncolor = colors.white
})

local function resolveStyle(spec)
    local theme = merge({}, styles.dark)
    if type(spec) == "string" and styles[spec] then
        merge(theme, styles[spec])
    elseif type(spec) == "table" then
        merge(theme, spec)
    end
    theme.title = theme.title or "CloverOS Bootloader"
    theme.backgroundcolor = theme.backgroundcolor or colors.black
    theme.textcolor = theme.textcolor or colors.white
    theme.boxbackground = theme.boxbackground or theme.backgroundcolor
    theme.boxcolor = theme.boxcolor or theme.textcolor
    theme.selectcolor = theme.selectcolor or colors.blue
    theme.selecttext = theme.selecttext or colors.white
    theme.titlecolor = theme.titlecolor or theme.textcolor
    theme.helpcolor = theme.helpcolor or theme.textcolor
    theme.descriptioncolor = theme.descriptioncolor or theme.textcolor
    return theme
end

local currentW, currentH, enth, boxwin, entrywin

local function rebuildLayout()
    local w, h = term.getSize()
    if w ~= currentW or h ~= currentH or not boxwin or not entrywin then
        currentW, currentH = w, h
        enth = math.max(1, h - 11)
        boxwin = window.create(term.current(), 2, 4, math.max(1, w - 2), math.max(1, h - 9))
        entrywin = window.create(boxwin, 2, 2, math.max(1, w - 4), enth)
    end
    return currentW, currentH
end

local function fitText(text, width)
    text = tostring(text or "")
    if width <= 0 then return "" end
    if #text <= width then return text end
    if width <= 3 then return text:sub(1, width) end
    return text:sub(1, width - 3) .. "..."
end

local function centerX(text, w)
    return math.max(1, math.floor((w - #text) / 2) + 1)
end

local styleNames = {}
for n in pairs(styles) do styleNames[#styleNames + 1] = n end
table.sort(styleNames)

local currentStyleName = config.style or config.gui or config.layout or "phoenix"
if not styles[currentStyleName] then currentStyleName = "phoenix" end

local theme = resolveStyle(currentStyleName)
local mode = "boot"
local selection, scroll = 1, 1
local styleSelection, styleScroll = 1, 1

rebuildLayout()

if config.defaultentry then
    for i = 1, #entries do
        if entries[i].name == config.defaultentry then
            selection = i
            break
        end
    end
    if selection > enth then scroll = selection - enth + 1 end
    if config.timeout == 0 and selection <= #entries then
        if boot(entries[selection]) then return end
    end
end

for i, name in ipairs(styleNames) do
    if name == currentStyleName then
        styleSelection = i
        break
    end
end
if styleSelection > enth then styleScroll = styleSelection - enth + 1 end

local function applyStyle(name)
    if styles[name] then
        currentStyleName = name
        config.style = name
        theme = resolveStyle(name)
    end
end

local function bootCount()
    return #entries + 1
end

local function entryName(i)
    if i <= #entries then
        return entries[i].name, entries[i].description
    end
    return "GUI Styles", "Choose the boot menu theme."
end

local function drawBootEntries()
    local w, h = rebuildLayout()
    entrywin.setVisible(false)
    entrywin.setBackgroundColor(theme.boxbackground)
    entrywin.setTextColor(theme.textcolor)
    entrywin.clear()

    local total = bootCount()
    for i = scroll, scroll + enth - 1 do
        if i > total then break end
        local name = entryName(i)
        local y = i - scroll + 1
        entrywin.setCursorPos(2, y)
        if i == selection then
            entrywin.setBackgroundColor(theme.selectcolor)
            entrywin.setTextColor(theme.selecttext)
        else
            entrywin.setBackgroundColor(theme.boxbackground)
            entrywin.setTextColor(theme.textcolor)
        end
        entrywin.clearLine()
        entrywin.write(fitText(name, w - 6))
        if i == selection and config.timeout and selection <= #entries then
            local s = tostring(config.timeout)
            entrywin.setCursorPos(w - 4 - #s, y)
            entrywin.write(s)
            entrywin.setCursorPos(2, y)
        end
    end

    entrywin.setVisible(true)
    term.setBackgroundColor(theme.backgroundcolor)
    term.setTextColor(theme.descriptioncolor)
    term.setCursorPos(5, h - 5)
    term.clearLine()
    local _, desc = entryName(selection)
    term.write(fitText(desc, w - 8))
    term.setTextColor(theme.helpcolor)
    term.setCursorPos(5, h - 3)
    term.clearLine()
    term.write(fitText("Use the arrow keys to select. Enter boots the highlighted entry.", w - 8))
    term.setCursorPos(5, h - 2)
    term.clearLine()
    term.write(fitText("'c' shell, 'e' edit, " .. selection .. "/" .. total, w - 8))
end

local function drawStyleEntries()
    local w, h = rebuildLayout()
    entrywin.setVisible(false)
    entrywin.setBackgroundColor(theme.boxbackground)
    entrywin.setTextColor(theme.textcolor)
    entrywin.clear()

    for i = styleScroll, styleScroll + enth - 1 do
        local name = styleNames[i]
        if not name then break end
        local y = i - styleScroll + 1
        entrywin.setCursorPos(2, y)
        if i == styleSelection then
            entrywin.setBackgroundColor(theme.selectcolor)
            entrywin.setTextColor(theme.selecttext)
        else
            entrywin.setBackgroundColor(theme.boxbackground)
            entrywin.setTextColor(theme.textcolor)
        end
        entrywin.clearLine()
        entrywin.write(fitText(name, w - 6))
    end

    entrywin.setVisible(true)
    term.setBackgroundColor(theme.backgroundcolor)
    term.setTextColor(theme.descriptioncolor)
    term.setCursorPos(5, h - 5)
    term.clearLine()
    term.write(fitText("Apply a GUI layout. Current: " .. currentStyleName, w - 8))
    term.setTextColor(theme.helpcolor)
    term.setCursorPos(5, h - 3)
    term.clearLine()
    term.write(fitText("Enter applies the selected style. Esc returns to boot entries.", w - 8))
    term.setCursorPos(5, h - 2)
    term.clearLine()
    term.write(fitText("Styles: " .. #styleNames .. " available", w - 8))
end

local function drawScreen()
    local w, h = rebuildLayout()
    local inner = math.max(0, w - 4)
    local bbg = hex(select(2, math.frexp(theme.boxbackground)))
    local bfg = hex(select(2, math.frexp(theme.boxcolor)))

    term.setBackgroundColor(theme.backgroundcolor)
    term.clear()

    boxwin.setBackgroundColor(theme.boxbackground)
    boxwin.setTextColor(theme.boxcolor)
    boxwin.clear()

    entrywin.setBackgroundColor(theme.boxbackground)
    entrywin.setTextColor(theme.textcolor)
    entrywin.clear()

    boxwin.setCursorPos(1, 1)
    boxwin.write("\x9C" .. ("\x8C"):rep(inner))
    boxwin.blit("\x93", bbg, bfg)

    for y = 2, h - 10 do
        boxwin.setCursorPos(1, y)
        boxwin.blit("\x95", bfg, bbg)
        boxwin.setCursorPos(w - 2, y)
        boxwin.blit("\x95", bbg, bfg)
    end

    boxwin.setCursorPos(1, h - 9)
    boxwin.write("\x8D" .. ("\x8C"):rep(inner) .. "\x8E")

    term.setCursorPos(centerX(theme.title, w), 2)
    term.setTextColor(theme.titlecolor)
    term.write(fitText(theme.title, w - 2))

    if mode == "boot" then
        drawBootEntries()
    else
        drawStyleEntries()
    end
end

drawScreen()

local tm = config.defaultentry and config.timeout and os.startTimer(1)

while true do
    local ev = { coroutine.yield() }

    if ev[1] == "timer" and ev[2] == tm and mode == "boot" then
        config.timeout = config.timeout - 1
        if config.timeout == 0 and selection <= #entries then
            if boot(entries[selection]) then return end
        end
        drawBootEntries()
        tm = os.startTimer(1)
    elseif ev[1] == "key" then
        if mode == "boot" then
            if tm then
                os.cancelTimer(tm)
                config.timeout, tm = nil
                drawBootEntries()
            end

            local total = bootCount()
            if (ev[2] == keys.down or ev[2] == keys.numPad2) and selection < total then
                selection = selection + 1
                if selection > scroll + enth - 1 then scroll = scroll + 1 end
                drawBootEntries()
            elseif (ev[2] == keys.up or ev[2] == keys.numPad8) and selection > 1 then
                selection = selection - 1
                if selection < scroll then scroll = scroll - 1 end
                drawBootEntries()
            elseif ev[2] == keys.enter then
                if selection == total then
                    mode = "style"
                    drawScreen()
                else
                    if boot(entries[selection]) then return end
                    term.clear()
                    drawScreen()
                end
            elseif ev[2] == keys.c then
                runShell()
                drawScreen()
            elseif ev[2] == keys.e then
                if shell then
                    shell.run("/rom/programs/edit.lua", fs.combine(fs.getDir(shell.getRunningProgram()), "config.lua"))
                else
                    os.run({}, "/rom/programs/edit.lua", "pxboot/config.lua")
                end
                drawScreen()
            end
        else
            if (ev[2] == keys.down or ev[2] == keys.numPad2) and styleSelection < #styleNames then
                styleSelection = styleSelection + 1
                if styleSelection > styleScroll + enth - 1 then styleScroll = styleScroll + 1 end
                drawStyleEntries()
            elseif (ev[2] == keys.up or ev[2] == keys.numPad8) and styleSelection > 1 then
                styleSelection = styleSelection - 1
                if styleSelection < styleScroll then styleScroll = styleScroll - 1 end
                drawStyleEntries()
            elseif ev[2] == keys.enter then
                applyStyle(styleNames[styleSelection])
                mode = "boot"
                drawScreen()
            elseif ev[2] == keys.backspace or ev[2] == keys.escape then
                mode = "boot"
                drawScreen()
            end
        end
    elseif ev[1] == "term_resize" then
        rebuildLayout()
        drawScreen()
    elseif ev[1] == "terminate" then
        break
    end
end
