local function findOS()for i=0,99 do local d="/disk"..(i==0 and""or i).."/CloverOS_OS.lua" if fs.exists(d) then return d end end if fs.exists("/boot/CloverOS_OS.lua") then return "/boot/CloverOS_OS.lua" end error("CloverOS not found") end
local path=findOS()
local oldG=_G
local _G={}
_G._G=_G

local rom=oldG._ROM or {}
local function restoreAPI(name)
    if not _G[name] then
        _G[name]=oldG[name] or (rom[name] or require(name))
    end
end
for _,v in ipairs{"term","fs","os","colors","shell","io","bit","textutils","pocket"} do restoreAPI(v) end
if not _G.term.native then _G.term.native=_G.term end

local fn,err=loadfile(path,"bt",_G)
if not fn then printError(err)return end
local ok,err=pcall(fn)
if not ok then printError(err) end
while true do _G.os.pullEvent() end