-- grep: print lines matching a pattern
local access = dofile(fs.combine(CLOVER_ROOT or fs.getDir(shell.getRunningProgram()),
	"runtime/access.lua")).attach()
local args = { ... }

local ignoreCase = false
local invert = false
local number = false
local pattern = nil
local files = {}

for _, a in ipairs(args) do
	if a == "-i" then
		ignoreCase = true
	elseif a == "-v" then
		invert = true
	elseif a == "-n" then
		number = true
	elseif not pattern then
		pattern = a
	else
		files[#files + 1] = a
	end
end

if not pattern then
	print("usage: grep [-i] [-v] [-n] <pattern> [file...]")
	return 1
end

local needle = ignoreCase and pattern:lower() or pattern

local function matches(line)
	local hay = ignoreCase and line:lower() or line
	local found = hay:find(needle, 1, true) ~= nil
	if invert then
		return not found
	end
	return found
end

local function filter(lines, label)
	local shown = 0
	for i, line in ipairs(lines) do
		if matches(line) then
			shown = shown + 1
			if label and number then
				print(label .. ":" .. i .. ":" .. line)
			elseif label then
				print(label .. ":" .. line)
			elseif number then
				print(i .. ":" .. line)
			else
				print(line)
			end
		end
	end
	return shown
end

local function readLines(path)
	local h, err
	if access then
		h, err = access:openForRead(path)
	else
		h = fs.open(path, "r")
	end
	if not h then
		printError("grep: " .. tostring(err or ("cannot open " .. path)))
		return nil
	end
	local data = h.readAll()
	h.close()
	local lines = {}
	for line in (data or ""):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	return lines
end

if #files == 0 then
	-- stdin (pipe); ends when the pipe is exhausted
	local lines = {}
	while true do
		local ok, line = pcall(read)
		if not ok or line == nil then
			break
		end
		lines[#lines + 1] = line
	end
	filter(lines, nil)
else
	for _, path in ipairs(files) do
		local lines = readLines(path)
		if lines then
			filter(lines, #files > 1 and path or nil)
		end
	end
end
