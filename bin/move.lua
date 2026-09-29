local args = { ... }
if #args < 2 then
	print("usage: move <src> <dst>")
	return 1
end
if not fs.exists(args[1]) then
	printError("move: no such file: " .. args[1])
	return 1
end
fs.move(args[1], args[2])
