local M = {}

function M.find()
	if fs.exists("/CloverOS_OS.lua") and fs.exists("/runtime/root.lua") then
		return "/"
	end

	for i = 0, 99 do
		local root = "/disk" .. (i == 0 and "" or i)
		if fs.exists(root .. "/CloverOS_OS.lua") and fs.exists(root .. "/runtime/root.lua") then
			return root
		end
	end

	local running = shell and shell.getRunningProgram and shell.getRunningProgram() or nil
	if running then
		local dir = fs.getDir(running)
		while dir and dir ~= "" do
			if fs.exists(dir .. "/CloverOS_OS.lua") and fs.exists(dir .. "/runtime/root.lua") then
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

function M.join(root, ...)
	local path = tostring(root or "")
	local parts = { ... }
	for i = 1, #parts do
		path = fs.combine(path, tostring(parts[i] or ""))
	end
	return path
end

return M