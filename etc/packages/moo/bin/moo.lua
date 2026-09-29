-- moo: a cow repeats wisdom (CloverOS package payload, needs fortune)
local fortune = shell.resolve and shell.resolve("bin/fortune.lua") or "bin/fortune.lua"
local wisdom = {}
local oldPrint = print
print = function(line)
	wisdom[#wisdom + 1] = line
end
local ok = pcall(shell.run, fortune)
print = oldPrint
if not ok or #wisdom == 0 then
	print("moo: fortune is not installed (apt install fortune)")
	return
end

local text = wisdom[#wisdom]
local bar = string.rep("-", #text + 2)
print(" " .. bar)
print("< " .. text .. " >")
print(" " .. bar)
print("        \\   ^__^")
print("         \\  (oo)\\_______")
print("            (__)\\       )\\/\\")
print("                ||----w |")
print("                ||     ||")
