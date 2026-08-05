local function findCloverRoot()
	if fs.exists("/CloverOS_API.lua") and fs.exists("/boot/kernel.lua") then
		return "/"
	end

	for i = 0, 99 do
		local root = "/disk" .. (i == 0 and "" or i)
		if fs.exists(root .. "/CloverOS_API.lua") and fs.exists(root .. "/boot/kernel.lua") then
			return root
		end
	end

	local running = shell and shell.getRunningProgram and shell.getRunningProgram() or nil
	if running then
		local dir = fs.getDir(running)
		while dir and dir ~= "" do
			if fs.exists(dir .. "/CloverOS_API.lua") and fs.exists(dir .. "/boot/kernel.lua") then
				return dir
			end
			if dir == "/" then
				break
			end
			dir = fs.getDir(dir)
		end
	end

	return nil
end

local root = findCloverRoot()
if not root then
	error("CloverOS root not found. Ensure CloverOS is installed on a mounted disk or in the current directory.")
end

local ok, api = pcall(dofile, root .. "/CloverOS_API.lua")
if ok and type(api) == "table" then
	if _G then
		rawset(_G, "CloverOS_API", api)
		rawset(_G, "CloverOS", api)
	end
	if _ENV and _ENV ~= _G then
		rawset(_ENV, "CloverOS_API", api)
		rawset(_ENV, "CloverOS", api)
	end
else
	error("Failed to load CloverOS_API: " .. tostring(api))
end

local loaders = {
	root .. "/boot/pxboot.lua",
	root .. "/boot/kernel.lua",
}

for _, path in ipairs(loaders) do
	if fs.exists(path) then
		local launched, err = pcall(shell.run, path)
		if launched then
			return
		end
		printError("Failed to launch CloverOS via " .. path .. ": " .. tostring(err))
	end
end

error("No CloverOS boot loader could be started.")