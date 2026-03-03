local function safeFindOS(fileName)
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
        return path or "/CloverOS_OS.lua"
    else
        printError("Error finding OS: " .. tostring(path))
        return "/CloverOS_OS.lua"
    end
end

-- Precompute kernel path
local cloverOS = safeFindOS("CloverOS_OS.lua")

local oldG = _G
local _G = {}
_G._G = _G

local rom = oldG._ROM or {}

local function restoreAPI(name)
    if not _G[name] then
        local val = oldG[name] or rom[name]
        if type(val) == "table" then
            local t = {}
            for k,v in pairs(val) do t[k]=v end
            _G[name] = t
        else
            _G[name] = val
        end
    end
end

for _,v in ipairs{"term","fs","os","colors","shell","io","bit","textutils","pocket"} do
    restoreAPI(v)
end

if not _G.term.native then _G.term.native=_G.term end
shell.run(cloverOS)