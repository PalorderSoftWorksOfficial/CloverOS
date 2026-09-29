local args = { ... }
if #args < 1 then
	print("usage: delete <path>")
	return 1
end
if not fs.exists(args[1]) then
	printError("delete: no such path: " .. args[1])
	return 1
end
fs.delete(args[1])
