local args = { ... }

if #args == 0 then
	print("usage: cat <file> [file...]")
	return 1
end

for _, path in ipairs(args) do
	local h = fs.open(path, "r")
	if not h then
		printError("cat: cannot open " .. path)
	else
		local content = h.readAll()
		h.close()
		if content then
			io.write(content)
			if content:sub(-1) ~= "\n" then
				print()
			end
		end
	end
end
