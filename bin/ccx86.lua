local root="/ccx86"
local app="apps/ccx86_lab.lua"
if not fs.exists(root.."/main.lua") then
    print("CC-X86 is not installed at "..root)
    print("Install PalorderSoftWorksOfficial/CC-x86 into /ccx86 first")
    return
end
local appPath=fs.exists(app) and app or "/apps/ccx86_lab.lua"
if not fs.exists(appPath) then
    print("CloverOS CC-X86 lab is not installed")
    return
end
local ok=shell.run(appPath,...)
if not ok then
    error("CC-X86 lab failed")
end
