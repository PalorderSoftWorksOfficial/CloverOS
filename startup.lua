local path
for i = 0, 99 do
    local d = "/disk" .. (i == 0 and "" or i)
    if fs.exists(d .. "/CloverOS_API.lua") then
        path = d .. "/CloverOS_API.lua"
        break
    end
end

if not path then
    error("CloverOS_API.lua not found")
end

API = dofile(path)
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

local pxbootPath = (function()
    for i = 0, 99 do
        local d = "/disk" .. (i == 0 and "" or i)
        local path = d .. "/boot/pxboot.lua"
        if fs.exists(path) then
            return path
        end
    end

    if fs.exists("/boot/pxboot.lua") then
        return "/boot/pxboot.lua"
    end

    return nil
end)()

if not pxbootPath then
    error("Bootloader not found. Does pxboot.lua exist?")
end

shell.run(pxbootPath)