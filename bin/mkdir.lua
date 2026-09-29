local args = { ... }
if #args < 1 then
	print("usage: mkdir <dir>")
	return 1
end
fs.makeDir(args[1])
