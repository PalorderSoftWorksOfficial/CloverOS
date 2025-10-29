local args={...}
local p=args[1]
if not p or p=="" then print("Usage: rmdir <dir>") return end
if not fs.exists(p) then print("Directory not found.") return end
if not fs.isDir(p) then print("Not a directory.") return end
fs.delete(p)
print("Removed directory "..p)
