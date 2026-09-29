local args = { ... }
local path = args[1] or "."

if not fs.exists(path) then
	printError("ls: no such path: " .. path)
	return 1
end

if not fs.isDir(path) then
	print(fs.getName(path))
	return 0
end

local items = fs.list(path)
table.sort(items)
for _, item in ipairs(items) do
	if fs.isDir(fs.combine(path, item)) then
		print(item .. "/")
	else
		print(item)
	end
end
