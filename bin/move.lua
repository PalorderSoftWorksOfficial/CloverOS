local args={...}
local src,dst=args[1],args[2]
if not src or not dst then print("Usage: move <src> <dst>") return end
if not fs.exists(src) then print("Source not found.") return end
fs.move(src,dst)
print("Moved "..src.." -> "..dst)
