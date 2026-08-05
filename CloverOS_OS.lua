local function findRoot()
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

local ROOT = findRoot()
if not ROOT then
	error("CloverOS root not found")
end

local function load(path)
	local ok, result = pcall(dofile, path)
	if not ok then
		error(result)
	end
	return result
end

local rootmod = load(ROOT .. "/runtime/root.lua")
local usersmod = load(ROOT .. "/runtime/users.lua")
local uimod = load(ROOT .. "/runtime/ui.lua")
local pkgmod = load(ROOT .. "/runtime/packages.lua")
local shellmod = load(ROOT .. "/runtime/shell.lua")

local users = usersmod.new(ROOT)
local ui = uimod.new(kernel, ROOT)
local packages = pkgmod.new(kernel, ROOT, users, ui)
local session = shellmod.new(kernel, ROOT, users, ui, packages, rootmod)

users:load()
ui:splash()
session:run()