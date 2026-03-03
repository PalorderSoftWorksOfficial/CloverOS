local function safeFindKernel(fileName)
    local ok, path = pcall(function()
        for i = 0, 99 do
            local d = "/disk" .. (i == 0 and "" or i)
            local p = d .. "/" .. fileName
            if fs.exists(p) then return p end
        end
        if fs.exists("/" .. fileName) then return "/" .. fileName end
        return nil
    end)
    if ok then
        return path or "/boot/kernel.lua"
    else
        printError("Error finding kernel: " .. tostring(path))
        return "/boot/kernel.lua"
    end
end

-- Precompute kernel path
local cloverKernel = safeFindKernel("boot/kernel.lua")

defaultentry = "CloverOS"
timeout = 5
backgroundcolor = colors.black
selectcolor = colors.orange
titlecolor = colors.lightGray

menuentry "CloverOS" {
    description "Boot CloverOS normally.";
    kernel(cloverKernel);
    args "";
}

menuentry "CraftOS" {
    description "Boot into CraftOS.";
    craftos;
}

-- include "config.lua.d/*"