local args={...}
local src,dst=args[1],args[2]
if not src or not dst then print("Usage: ren <old> <new>") return end
if not fs.exists(src) then print("File not found.") return end
fs.move(src,dst)
print("Renamed "..src.." -> "..dst)
