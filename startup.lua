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
    error("CloverOS root not found.")
end

local emulator    = settings.get("emulator") == "true"
local turtle      = settings.get("turtle") == "true"
local softinstall = settings.get("softinstall") == "true"
local defaultMode = settings.get("default") == "true"

local aptPath = DISK_ROOT .. "/bin/apt"
if (emulator or turtle or softinstall or defaultMode) then
    if emulator then
        print("Emulator detected.")
    elseif turtle then
        print("Turtle detected.")
    elseif softinstall then
        print("Soft install detected.")
    end

    if fs.exists(aptPath) then
        shell.run(aptPath, "install", "all")
    else
        error("apt not found at " .. aptPath)
    end
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

local CloverOS_API = DISK_ROOT .. "/CloverOS_API.lua"
if fs.exists(CloverOS_API) then
    shell.run(CloverOS_API)
else
    error("CloverOS_API.lua missing.")
end

local filesystem = DISK_ROOT .. "/etc/filesystem/main.lua"
if fs.exists(filesystem) then
    shell.run(filesystem)
else
    error("Filesystem module missing.")
end

if not pxbootPath then
    error("Bootloader not found.")
end

shell.run(pxbootPath)