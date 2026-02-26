local DISK_ROOT = (function()
    for i = 0, 99 do
        local d = "/disk" .. (i == 0 and "" or i)
        if fs.exists(d .. "/pxboot.lua") then
            return d
        end
    end
    if fs.exists("/pxboot.lua") then
        return "/"
    end
    return nil
end)()

if not DISK_ROOT then
    print("Error: bootloader isn't found, Does pxboot.lua exist?")
    return
end

local pxbootPath = fs.combine(DISK_ROOT, "pxboot.lua")

if not fs.exists(pxbootPath) then
    print("Error: bootloader not found at " .. pxbootPath)
    return
end

shell.run(pxbootPath)