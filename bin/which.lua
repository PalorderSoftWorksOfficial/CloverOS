-- which: locate a program
local args = { ... }
local name = args[1]
if not name then
	print("usage: which <command>")
	return 1
end

local dirs = { "bin", "usr/bin", "apps" }
for _, dir in ipairs(dirs) do
	for _, ext in ipairs({ ".lua", ".exe", "" }) do
		local path = dir .. "/" .. name .. ext
		if fs.exists(path) then
			print(path)
			return 0
		end
	end
end

printError("which: not found: " .. name)
return 1
