local args={...}
local p=args[1]
if not p or p=="" then print("Usage: mkdir <path>") return end
if fs.exists(p) then print("Already exists.") return end
fs.makeDir(p)
print("Created directory "..p)
