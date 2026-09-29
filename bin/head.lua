-- head: show the beginning of a file (or stdin)
local args = { ... }

local count = 10
local file = nil
local i = 1
while i <= #args do
	if args[i] == "-n" then
		count = tonumber(args[i + 1]) or 10
		i = i + 2
	elseif tonumber(args[i]) and not file then
		count = tonumber(args[i])
		i = i + 1
	else
		file = args[i]
		i = i + 1
	end
end

local lines = {}
if file then
	local access = dofile(fs.combine(CLOVER_ROOT or fs.getDir(shell.getRunningProgram()),
		"runtime/access.lua")).attach()
	local h, err
	if access then
		h, err = access:openForRead(file)
	else
		h = fs.open(file, "r")
	end
	if not h then
		printError("head: " .. tostring(err or ("cannot open " .. file)))
		return 1
	end
	local data = h.readAll()
	h.close()
	for line in (data or ""):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
else
	while true do
		local ok, line = pcall(read)
		if not ok or line == nil then
			break
		end
		lines[#lines + 1] = line
	end
end

for n = 1, math.min(count, #lines) do
	print(lines[n])
end
