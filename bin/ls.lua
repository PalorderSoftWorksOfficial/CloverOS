---@diagnostic disable: undefined-global, undefined-field
local args = { ... }
local argPath = args[1] or "."
local path = argPath
if argPath:match("^disk%d*$") then
    path = "/" .. argPath
end
path = shell.resolve(path)

local function listDir(p)
    if not fs.exists(p) then
        print("Directory not found: " .. p)
        return
    end
    if not fs.isDir(p) then
        print(p .. " is not a directory")
        return
    end

    term.setTextColor(colors.yellow)
    print(" Directory of " .. shell.resolve(p))
    term.setTextColor(colors.white)
    print("")

    local list = fs.list(p)
    local fileCount, dirCount = 0, 0

    for _, item in ipairs(list) do
        local fullPath = fs.combine(p, item)
        if fs.isDir(fullPath) then
            term.setTextColor(colors.cyan)
            print(string.format("%-20s <DIR>", item))
            dirCount = dirCount + 1
        else
            term.setTextColor(colors.white)
            print(string.format("%-20s %d bytes", item, fs.getSize(fullPath)))
            fileCount = fileCount + 1
        end
    end

    term.setTextColor(colors.lightGray)
    print("")
    print(string.format(" %d File(s)    %d Dir(s)", fileCount, dirCount))
    term.setTextColor(colors.white)
end

listDir(path)

