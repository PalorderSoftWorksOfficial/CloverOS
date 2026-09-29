local args = { ... }
if #args < 2 then
	print("usage: copy <src> <dst>")
	return 1
end
if not fs.exists(args[1]) then
	printError("copy: no such file: " .. args[1])
	return 1
end
fs.copy(args[1], args[2])
