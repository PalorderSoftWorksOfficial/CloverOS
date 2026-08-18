local root="/ccx86"
local source="examples/cloveros_boot.asm"
local binary="examples/cloveros_boot.bin"
if not fs.exists(root.."/main.lua") then
 print("CC-X86 is not installed at /ccx86")
 print("Install PalorderSoftWorksOfficial/CC-x86 into /ccx86 first")
 return
end
if not fs.exists(root.."/"..source) then
 print("CloverOS CC-X86 boot probe is missing")
 return
end
local previous=shell.dir()
shell.setDir(root)
local assembled=shell.run("asm.lua",source,binary)
if not assembled or not fs.exists(binary) then
 shell.setDir(previous)
 print("Failed to assemble CloverOS CC-X86 boot probe")
 return
end
print("Running CloverOS x86 boot probe:")
shell.run("main.lua",binary,"--debug","--trace")
shell.setDir(previous)
