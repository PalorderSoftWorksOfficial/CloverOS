-- stat: show file metadata
local args = { ... }
local path = args[1]
if not path then
	print("usage: stat <file>")
	return 1
end

if not fs.exists(path) then
	printError("stat: no such file: " .. path)
	return 1
end

local info = {}
pcall(function()
	info = fs.attributes(path) or {}
end)

print("  file: " .. path)
print("  type: " .. (fs.isDir(path) and "directory" or "file"))
print("  size: " .. tostring(fs.getSize(path)))
if info.created then
	print("created: " .. os.date("!%Y-%m-%d %H:%M:%S", math.floor(info.created / 1000)))
end
if info.modified then
	print("  edit: " .. os.date("!%Y-%m-%d %H:%M:%S", math.floor(info.modified / 1000)))
end
print(" perms: " .. (fs.isReadOnly(path) and "read-only" or "read-write"))
