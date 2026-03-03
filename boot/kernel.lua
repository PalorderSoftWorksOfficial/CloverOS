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

local path2
for i = 0, 99 do
    local d = "/disk" .. (i == 0 and "" or i)
    if fs.exists(d .. "/CloverOS_API.lua") then
        path2 = d .. "/CloverOS_API.lua"
        break
    end
end

if not path2 then
    error("CloverOS_API.lua not found")
end

API = dofile(path)
API2 = dofile(path2)
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
mergeTables(API2, API)
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

_G.CloverOS = API

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

shell.run(cloverOS)