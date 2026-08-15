local root="/ccx86"
local guest="examples/add.bin"
if not fs.exists(root.."/main.lua") then
 print("CC-X86 is not installed at /ccx86")
 print("Install PalorderSoftWorksOfficial/CC-x86 into /ccx86 first")
 return
end
local previous=shell.dir()
shell.setDir(root)
shell.run("main.lua",guest,"--debug")
shell.setDir(previous)
