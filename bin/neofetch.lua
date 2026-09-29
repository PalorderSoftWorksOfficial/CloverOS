-- neofetch: system summary with the CloverOS logo
local logo = {
	"   _____ _                      ____   _____ ",
	"  / ____| |                    / __ \\ / ____|",
	" | |    | | _____   _____ _ __| |  | | (___  ",
	" | |    | |/ _ \\ \\ / / _ \\ '__| |  | |\\___ \\ ",
	" | |____| | (_) |\\ V /  __/ |  | |__| |____) |",
	"  \\_____|_|\\___/  \\/ \\___|_|   \\____/|_____/ ",
}

local osVersion = "unknown"
pcall(function()
	osVersion = dofile("etc/version.lua").string()
end)

local packages = 0
pcall(function()
	local root = CLOVER_ROOT or fs.getDir(fs.getDir(shell.getRunningProgram()))
	local pathsMod = dofile(fs.combine(root, "runtime/paths.lua"))
	local pkgMod = dofile(fs.combine(root, "runtime/packages.lua"))
	packages = #pkgMod.new(pathsMod.new(root)):installed()
end)

local info = {
	osVersion,
	"host:     " .. os.version(),
	"computer: " .. tostring(os.getComputerLabel() or ("computer-" .. os.getComputerID())),
	"id:       " .. os.getComputerID(),
	"uptime:   " .. string.format("%.1f min", os.clock() / 60),
	"packages: " .. packages,
	"shell:    clover-sh",
	"http:     " .. (http and "enabled" or "disabled"),
	"disk:     " .. tostring(fs.getFreeSpace("/")) .. " bytes free",
}

for i = 1, math.max(#logo, #info) do
	local left = logo[i] or string.rep(" ", logo[1] and #logo[1] or 0)
	local right = info[i] or ""
	print(left .. "   " .. right)
end
