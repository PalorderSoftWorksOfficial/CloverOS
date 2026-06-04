local BASE = "https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/"

local FILES = {
	"startup.lua",
	"CloverOS_API.lua",
	"CloverOS_OS.lua",
	"boot/config.lua",
	"boot/kernel.lua",
	"boot/pxboot.lua",
	"files.manifest",
}

local DIRS = {
	"boot",
	"etc",
	"etc/man",
	"usr",
	"usr/bin",
	"usr/local",
	"usr/local/bin",
	"bin",
	"home",
	"var",
	"tmp",
}

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("CloverOS Installer")
print("")
term.setTextColor(colors.white)

if not http then
	term.setTextColor(colors.red)
	print("HTTP API is disabled.")
	print("Enable http in server settings.")
	return
end

for _, dir in ipairs(DIRS) do
	if not fs.exists(dir) then
		fs.makeDir(dir)
	end
end

local ok_count = 0
local fail_count = 0
local failed = {}

for i, path in ipairs(FILES) do
	term.setTextColor(colors.lightGray)
	term.write("[" .. i .. "/" .. #FILES .. "] " .. path .. " ... ")
	local res = http.get(BASE .. path)
	if res then
		local f = fs.open(path, "w")
		if f then
			f.write(res.readAll())
			f.close()
			res.close()
			term.setTextColor(colors.green)
			print("OK")
			ok_count = ok_count + 1
		else
			res.close()
			term.setTextColor(colors.red)
			print("FAIL")
			fail_count = fail_count + 1
			table.insert(failed, path)
		end
	else
		term.setTextColor(colors.red)
		print("FAIL")
		fail_count = fail_count + 1
		table.insert(failed, path)
	end
end

print("")
if fail_count == 0 then
	term.setTextColor(colors.green)
	print("Done! " .. ok_count .. " files installed.")
	term.setTextColor(colors.white)
	print("")
	write("Reboot now? [y/n]: ")
	local ans = read()
	if ans == "y" or ans == "Y" then
		os.reboot()
	end
else
	term.setTextColor(colors.orange)
	print("Installed: " .. ok_count .. "  Failed: " .. fail_count)
	print("")
	term.setTextColor(colors.red)
	print("Could not download:")
	for _, p in ipairs(failed) do
		print("  - " .. p)
	end
	term.setTextColor(colors.white)
	print("")
	print("Check your internet connection.")
	print("Some files may be missing from GitHub.")
end
