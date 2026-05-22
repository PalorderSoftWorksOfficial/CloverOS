---@diagnostic disable: undefined-global
args = {...}
appname = args[1]

local function buildManualDirs()
    local dirs = { "/etc/man", "/usr/share/man", "/usr/local/share/man" }
    for i=0,99 do
        local disk = (i == 0 and "disk" or "disk" .. i)
        table.insert(dirs, "/" .. disk .. "/etc/man")
        table.insert(dirs, "/" .. disk .. "/usr/share/man")
        table.insert(dirs, "/" .. disk .. "/usr/local/share/man")
    end
    return dirs
end

local function findManualPath(name)
    for _, dir in ipairs(buildManualDirs()) do
        local path = dir .. "/" .. name .. ".man"
        if fs.exists(path) then
            return path
        end
    end
    return nil
end

if appname == "list" then
    if fs.exists("/etc/man/") then shell.run("ls", "/etc/man/") end
    for i=0,99 do
        local prefix = (i==0 and "disk" or "disk"..i).."/etc/man/"
        if fs.exists(prefix) then shell.run("ls", prefix) end
    end
    return 0
elseif appname == "" or appname == nil then
    print("no app given, try 'man list'")
    return 0
end

local path = findManualPath(appname)
if not path then
    print("I have no manuals on this topic, this is what i have:")
    if fs.exists("/etc/man/") then shell.run("ls", "/etc/man/") end
    for i=0,99 do
        local prefix = (i==0 and "disk" or "disk"..i).."/etc/man/"
        if fs.exists(prefix) then shell.run("ls", prefix) end
    end
    return 0
end

shell.run("edit", path)
