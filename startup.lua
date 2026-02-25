local filePath = (function()
    for i = 0, 99 do
        local d = "/disk" .. (i == 0 and "" or i)
        local p = d .. "/instructions.txt"
        if fs.exists(p) then return p end
    end
    if fs.exists("/instructions.txt") then return "/instructions.txt" end
    if fs.exists("/etc/instructions.txt") then return "/etc/instructions.txt" end
    return nil
end)()

local DISK_ROOT = (function()
    for i = 0, 99 do
        local d = "/disk" .. (i == 0 and "" or i)
        if fs.exists(d .. "/CloverOS_API.lua") then
            return d
        end
    end
    if fs.exists("/CloverOS_API.lua") then
        return "/"
    end
    return nil
end)()

if not DISK_ROOT then
    print("Error: CloverOS root not found.")
    return
end

local apiPath = fs.combine(DISK_ROOT, "CloverOS_API.lua")
local f = fs.open(apiPath, "r")
if not f then
    print("Failed to open: " .. apiPath)
    return
end

local content = f.readAll()
f.close()

local chunk, err = load(content, "CloverOS_API.lua", "t")
if not chunk then
    print("API load error: " .. err)
    return
end

local ok, API = pcall(chunk)
if not ok or type(API) ~= "table" then
    print("API runtime error:", API)
    return
end

local osAPIFunc = {
    version = function() return "CloverOS v1.0.0" end,
    author = function() return "CloverOS Team" end,
    runInstaller = function()
        shell.run("wget", "https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua", "netinstall.lua")
        shell.run("netinstall.lua")
    end
}

for k,v in pairs(osAPIFunc) do
    API[k] = v
end

osAPI = API

local emulator = settings.get("emulator") == "true"
local turtle = settings.get("turtle") == "true"
local softinstall = settings.get("softinstall") == "true"
local defaultMode = settings.get("default") == "true"

if emulator then
    print("Emulator detected.")
    shell.run(DISK_ROOT.."/bin/apt", "install", "all")
elseif turtle then
    print("Turtle detected.")
    shell.run(DISK_ROOT.."/bin/apt", "install", "all")
elseif softinstall then
    print("Soft install detected.")
    shell.run(DISK_ROOT.."/bin/apt", "install", "all")
elseif defaultMode then
    shell.run(DISK_ROOT.."/bin/apt", "install", "all")
end

if filePath and fs.exists(filePath) and settings.get("manualshown") ~= "true" then
    local file = fs.open(filePath, "r")
    if file then
        local content = file.readAll()
        file.close()
        term.clear()
        term.setCursorPos(1,1)
        print(content)
        settings.set("manualshown", "true")
        settings.save()
        print("\nAuto booting in 3 seconds...")
        os.sleep(3)
    end
end

local osPath = (function()
    for i = 0, 99 do
        local p = "/disk" .. (i == 0 and "" or i) .. "/CloverOS_OS.lua"
        if fs.exists(p) then return p end
    end
    if fs.exists("/CloverOS_OS.lua") then return "/CloverOS_OS.lua" end
    return nil
end)()

if osPath then
    shell.run(osPath)
else
    print("CloverOS_OS.lua not found.")
end
