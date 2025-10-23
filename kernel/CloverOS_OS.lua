-- CloverOS.lua
local CloverOS = {}

-- ==== SETUP ====
local modem = peripheral.find("modem")
if modem then modem.open(123) end

-- ==== STATE ====
local minimizedApps = {}

-- ==== APP STATE ====
function CloverOS.saveAppState(appName, state)
    minimizedApps[appName] = state
end

function CloverOS.restoreAppState(appName)
    return minimizedApps[appName]
end

-- ==== LOGIN ====
--- Authenticates a user.
-- @param username string
-- @param password string
-- @return table { success = bool, message = string }
function CloverOS.login(username, password)
    local success = (username == "user" and password == "pass")
    return {
        success = success,
        message = success and "Login successful!" or "Invalid credentials."
    }
end


-- ==== FILE MANAGEMENT ====
function CloverOS.listFiles(path)
    path = path or "/"
    local files = fs.list(path)
    local result = {}
    for _, file in ipairs(files) do
        local full = fs.combine(path, file)
        table.insert(result, {
            name = file,
            path = full,
            isDir = fs.isDir(full),
            size = fs.isDir(full) and 0 or fs.getSize(full)
        })
    end
    return result
end

function CloverOS.readFile(path)
    if not fs.exists(path) then
        return nil, "File not found"
    end
    local f = fs.open(path, "r")
    local data = f.readAll()
    f.close()
    return data
end

function CloverOS.writeFile(path, content)
    local f = fs.open(path, "w")
    f.write(content or "")
    f.close()
    return true
end

function CloverOS.deleteFile(path)
    if fs.exists(path) then
        fs.delete(path)
        return true
    end
    return false, "File not found"
end

-- ==== CUSTOM APP SCANNER ====
function CloverOS.getCustomApps()
    local appList = {}
    local appDirs = {"apps", "disk/apps"}

    for _, dir in ipairs(appDirs) do
        if fs.exists(dir) then
            for _, file in ipairs(fs.list(dir)) do
                if file:match("%.lua$") then
                    local appName = file:gsub("%.lua$", "")
                    table.insert(appList, {
                        name = appName,
                        path = fs.combine(dir, file),
                        run = function()
                            shell.run(fs.combine(dir, file))
                        end
                    })
                end
            end
        end
    end
    return appList
end

-- ==== BUILT-IN APPS ====
CloverOS.icons = {
    {
        name = "Terminal",
        type = "builtin",
        run = function()
            shell.run("shell")
        end
    },
    {
        name = "File Manager",
        type = "builtin",
        run = function()
            return CloverOS.listFiles("/")
        end
    },
    {
        name = "Shutdown",
        type = "builtin",
        run = function()
            os.shutdown()
        end
    }
}

-- ==== COMBINE ICONS ====
function CloverOS.getDesktopIcons()
    local icons = {}
    for _, v in ipairs(CloverOS.icons) do table.insert(icons, v) end
    for _, v in ipairs(CloverOS.getCustomApps()) do table.insert(icons, v) end
    return icons
end

-- ==== TRANSMIT SCREEN/STATE (OPTIONAL NETWORK SYNC) ====
function CloverOS.transmitData(data)
    if modem then
        modem.transmit(123, 123, data)
        return true
    end
    return false, "No modem found"
end

-- ==== RETURN MODULE ====
return CloverOS
