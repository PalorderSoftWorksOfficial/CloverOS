local syscall = setmetatable({}, {
	__index = function(self, idx)
		return function(...)
			local retval = table.pack(coroutine.yield("syscall", idx, ...))
			if retval[1] then
				return table.unpack(retval, 2, retval.n)
			else
				error(retval[2], 2)
			end
		end
	end,
	__newindex = function() end,
})
local has_lfs, lfs = pcall(require, "lfs")
if has_lfs then
	fs = {}
	function fs.list(path)
		local list = {}
		for name in lfs.dir(path) do
			if not name:match("^%.+$") then
				list[#list + 1] = name
			end
		end
		table.sort(list)
		return list
	end
	function fs.combine(a, b)
		return a .. "/" .. b
	end
end

local args = { ... }
if #args < 2 then
	error("Usage: compile <kernel.lua> <output.lua>")
end

local file, err = io.open(args[1], "r")
if not file then
	error("Could not open kernel: " .. err)
end
local kernel = file:read("*a")
file:close()

local parts = ""
for _, v in ipairs((fs or syscall).list(args[1] .. ".d")) do
	file, err = io.open((fs or syscall).combine(args[1] .. ".d", v), "r")
	if not file then
		error("Could not open component " .. v .. ": " .. err)
	end
	parts = parts .. "--#region " .. v .. "\n\n" .. file:read("*a") .. "\n\n--#endregion\n\n"
	file:close()
end

file, err = io.open(args[2], "w")
if not file then
	error("Could not open output: " .. err)
end
file:write((kernel:sub(1, kernel:find("-- ==== LOADER ====", 1, true) - 1):gsub("%$BUILD_DATE%$", os.date())))
file:write(parts)
file:write(kernel:sub(select(2, kernel:find("-- == END LOADER ==", 1, true)) + 1))
file:close()
print("Wrote compiled kernel to " .. args[2])
