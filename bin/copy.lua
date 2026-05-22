local args={...}
local src,dst=args[1],args[2]
if not src or not dst then print("Usage: copy <src> <dst>") return end
local resolvedSrc = shell.resolve(src)
local resolvedDst = shell.resolve(dst)
if not resolvedSrc or not fs.exists(resolvedSrc) then print("Source not found.") return end
if fs.isDir(resolvedSrc) then print("Cannot copy directories.") return end
fs.copy(resolvedSrc,resolvedDst)
print("Copied "..resolvedSrc.." -> "..resolvedDst)