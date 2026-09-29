local M = {}

M.major = 2
M.minor = 1
M.patch = 0
M.suffix = ""
M.codename = "Numbat"
M.name = "CloverOS"
M.vendor = "PalorderSoftWorks"

function M.version()
	return string.format("%d.%d.%d%s", M.major, M.minor, M.patch, M.suffix)
end

function M.string()
	return M.name .. " " .. M.version() .. " \"" .. M.codename .. "\""
end

function M.kernelVersion()
	return M.version()
end

return M
