local filePath = "disk/instructions.txt"

if fs.exists(filePath) then
    local file = fs.open(filePath, "r")
    local content = file.readAll()
    file.close()
    term.clear()
    term.setCursorPos(1, 1)
    shell.run("lua")
    print(content)
    print("\nTo run CloverOS, type the following command:")
    print("shell.run('disk/CloverOS_OS.lua')")
else
    print("Instructions file not found. Please ensure the disk is inserted correctly.")
end
