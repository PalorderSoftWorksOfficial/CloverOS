local filePath = (function() for i=0,99 do local d="disk"..(i==0 and "" or i) if fs.exists(d.."/instructions.txt") then return d.."/instructions.txt" end end return "/etc/instructions.txt" end)()

if fs.exists(filePath) then
    local file = fs.open(filePath, "r")
    local content = file.readAll()
    file.close()
    term.clear()
    term.setCursorPos(1, 1)
    print(content)
    print("\nTo run CloverOS, type the following command:")
    print("diskX/CloverOS_OS.lua")
else
    print("Instructions file not found. Please ensure the disk is inserted correctly.")
end
