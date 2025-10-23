local filePath = "disk/instructions.txt"

if fs.exists(filePath) then
    local file = fs.open(filePath, "r")
    local content = file.readAll()
    file.close()
    term.clear()
    term.setCursorPos(1, 1)
    print(content)
    print("\nTo run TRGS OS, type the following command:")
    print("shell.run('disk/TRGS_OS.lua')")
    shell.run(lua)
else
    print("Instructions file not found. Please ensure the disk is inserted correctly.")
end
