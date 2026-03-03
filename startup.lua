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