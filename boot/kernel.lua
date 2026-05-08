-- CloverOS kernel loader
-- Copyright (c) 2026 PalorderSoftWorksOfficial
-- This file locates CloverOS components and starts the OS.
---@diagnostic disable: undefined-global
-- luacheck: globals fs shell colors printError os term peripheral

local function findFile(fileName)
	for i = 0, 99 do
		local d = "/disk" .. (i == 0 and "" or i)
		local p = d .. "/" .. fileName
		if fs.exists(p) then
			return p
		end
	end

	if fs.exists("/" .. fileName) then
		return "/" .. fileName
	end

	return nil
end

local path = findFile("CloverOS_API.lua")
if not path then
	error("CloverOS_API.lua not found")
end

local path2 = findFile("CloverOS_API2.lua")

local API = dofile(path)
local API2 = path2 and dofile(path2) or {}

local function mergeTables(t1, t2)
	for k, v in pairs(t2) do
		if type(v) == "table" and type(t1[k]) == "table" then
			mergeTables(t1[k], v)
		else
			t1[k] = v
		end
	end
	return t1
end

mergeTables(API, API2)

local osAPIFunc = {
	version = function()
		return "CloverOS v1.0.0"
	end,
	author = function()
		return "CloverOS Team"
	end,
	runInstaller = function()
		shell.run("wget", "https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua", "netinstall.lua")
		shell.run("netinstall.lua")
	end,
}

for k, v in pairs(osAPIFunc) do
	API[k] = v
end

local fsPath = findFile("etc/filesystem/main.lua")
if fsPath then
	local ok, fsModule = pcall(dofile, fsPath)
	if ok and type(fsModule) == "table" then
		API.filesystem = fsModule
	end
end

local function safeFindOS(fileName)
	local ok, result = pcall(function()
		for i = 0, 99 do
			local d = "/disk" .. (i == 0 and "" or i)
			local p = d .. "/" .. fileName
			if fs.exists(p) then
				return p
			end
		end
		if fs.exists("/" .. fileName) then
			return "/" .. fileName
		end
		return nil
	end)

	if ok then
		return result or "/CloverOS_OS.lua"
	else
		printError("Error finding OS: " .. tostring(result))
		return "/CloverOS_OS.lua"
	end
end
_G.CloverOS = setmetatable(API, {
	__newindex = function()
		error("CloverOS API is read-only")
	end,
})
local cloverOS = safeFindOS("CloverOS_OS.lua")
if not fs.exists(cloverOS) then
	error("CloverOS_OS.lua not found at: " .. cloverOS)
end
shell.run(cloverOS)
