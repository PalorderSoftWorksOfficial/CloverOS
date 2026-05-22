args = {...}
local filePath = args[1]

if not filePath or filePath == "" then
    print("Usage: run <file>")
    return
end

local resolved = shell.resolve(filePath)

if not resolved or not fs.exists(resolved) then
    print("File not found: " .. filePath)
    return
end

shell.run(resolved)
