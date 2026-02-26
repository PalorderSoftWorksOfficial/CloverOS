local function findKernel(fileName)
    for i = 0, 99 do
        local d = "/disk" .. (i == 0 and "" or i)
        local p = d .. "/" .. fileName
        if fs.exists(p) then return p end
    end
    if fs.exists("/" .. fileName) then return "/" .. fileName end
    return nil
end

defaultentry = "CloverOS"
timeout = 5
backgroundcolor = colors.black
selectcolor = colors.orange
titlecolor = colors.lightGray

menuentry "CloverOS" {
    description "Boot CloverOS normally.";
    kernel(findKernel("CloverOS_OS.lua") or "/root/boot/kernel.lua");
    args "";
}

menuentry "CraftOS" {
    description "Boot into CraftOS.";
    craftos;
}

-- include "config.lua.d/*"