args = {...}
local userinput = args[1]
local etc1 = args[2]

if not userinput or userinput == "" then
    print("Bad ARG or incorrect option, Run: man type for the manual")
    return 0
end

if userinput == "?" or userinput == "help" then
    print("prints a text file to the screen")
    print("usage: type <filename> [p]")
    print("p - pauses every 15 lines")
    return 0
end

local filename = shell.resolve(userinput)
if not filename or filename == "" then
    print("Bad ARG or incorrect option, Run: man type for the manual")
    return 0
end

if not fs.exists(filename) then
    print("file not found")
    return 0
end

if fs.isDir(filename) then
    print("path is a directory")
    return 0
end

local file = fs.open(filename, "r")
if not file then
    print("failed to open file")
    return 0
end

local linecounter = 0
while true do
    local temp = file.readLine()
    if temp == nil then break end
    print(temp)
    linecounter = linecounter + 1
    if etc1 == "p" and linecounter >= 15 then
        print("Hit ENTER for next page or q to stop")
        local input = read()
        if input == "q" or input == "Q" then
            file.close()
            return 0
        end
        linecounter = 0
    end
end

file.close()
