-- cpu_loader.lua

local shared = require("cpu_shared")

local M = {}

local function readonly(api, name)
	return shared.newReadOnlyApi(api, name)
end

function M.load()
	local RISCV = require("riscv")
	local X86 = require("x86")
	local AMD64 = require("amd64")

	return {
		shared = shared,

		RISCV = RISCV,
		X86 = X86,
		AMD64 = AMD64,
	}
end

function M.install(env)
	env = env or _G

	local mods = M.load()
	env.RISCV = readonly(mods.RISCV, "RISCV")
	env.X86 = readonly(mods.X86, "X86")
	env.AMD64 = readonly(mods.AMD64, "AMD64")
	env.CPU_ARCHS = readonly({
		RISCV = env.RISCV,
		X86 = env.X86,
		AMD64 = env.AMD64,
	}, "CPU_ARCHS")

	return mods
end

function M.get(name)
	local mods = M.load()

	if name == "riscv" or name == "RISCV" then
		return mods.RISCV
	elseif name == "x86" or name == "X86" then
		return mods.X86
	elseif name == "amd64" or name == "AMD64" or name == "x64" then
		return mods.AMD64
	end

	error(("unknown CPU architecture '%s'"):format(tostring(name)))
end

function M.create(name, ...)
	local arch = M.get(name)

	if type(arch.new) == "function" then
		return arch.new(...)
	end

	if type(arch.create) == "function" then
		return arch.create(...)
	end

	local instance = {}

	for k, v in pairs(arch) do
		instance[k] = v
	end

	if type(instance.reset) == "function" then
		instance:reset(...)
	end

	return instance
end

return M