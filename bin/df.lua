-- df: free space on the CloverOS root and on every attached disk.
local root = CLOVER_ROOT or fs.getDir(shell.getRunningProgram())

local function free(path)
	if type(fs) ~= "table" or type(fs.getFreeSpace) ~= "function" then
		return nil
	end
	local ok, bytes = pcall(fs.getFreeSpace, path)
	if ok and type(bytes) == "number" then
		return bytes
	end
	return nil
end

local function human(bytes)
	if type(bytes) ~= "number" then
		return "-"
	end
	local units = { "B", "K", "M", "G", "T" }
	local value, index = bytes, 1
	while value >= 1024 and index < #units do
		value = value / 1024
		index = index + 1
	end
	return string.format("%.1f%s", value, units[index])
end

print(string.format("%-24s %10s  %s", "filesystem", "free", "size"))
print(string.format("%-24s %10s  %s", root, human(free(root)), "-"))

if type(peripheral) == "table" and type(peripheral.getNames) == "function" then
	local ok, names = pcall(peripheral.getNames)
	if ok and type(names) == "table" then
		for _, name in ipairs(names) do
			local tok, ptype = pcall(peripheral.getType, name)
			if tok and ptype == "disk" then
				print(string.format("%-24s %10s  %s", name, human(free(name)), "-"))
			end
		end
	end
end
