local filesystem = {}

local cwd = "/"

local function normalize(path)
    if not path or path == "" then
        return cwd
    end

    if string.sub(path, 1, 1) ~= "/" then
        path = fs.combine(cwd, path)
    end

    local parts = {}
    for part in string.gmatch(path, "[^/]+") do
        if part == ".." then
            if #parts > 0 then
                table.remove(parts)
            end
        elseif part ~= "." and part ~= "" then
            table.insert(parts, part)
        end
    end

    return "/" .. table.concat(parts, "/")
end

local function resolve(path)
    return normalize(path)
end

function filesystem.cwd()
    return cwd
end

function filesystem.chdir(path)
    local p = resolve(path)
    if fs.exists(p) and fs.isDir(p) then
        cwd = p
        return true
    end
    return false
end

function filesystem.exists(path)
    return fs.exists(resolve(path))
end

function filesystem.isDir(path)
    return fs.isDir(resolve(path))
end

function filesystem.isReadOnly(path)
    return fs.isReadOnly(resolve(path))
end

function filesystem.list(path)
    return fs.list(resolve(path))
end

function filesystem.makeDir(path)
    return fs.makeDir(resolve(path))
end

function filesystem.makeDirRecursive(path)
    local full = resolve(path)
    local build = ""
    for part in string.gmatch(full, "[^/]+") do
        build = fs.combine(build, part)
        if not fs.exists(build) then
            fs.makeDir(build)
        end
    end
end

local function deleteRecursive(path)
    if fs.isDir(path) then
        for _, file in ipairs(fs.list(path)) do
            deleteRecursive(fs.combine(path, file))
        end
    end
    fs.delete(path)
end

function filesystem.delete(path, recursive)
    local p = resolve(path)
    if recursive then
        deleteRecursive(p)
    else
        fs.delete(p)
    end
end

local function copyRecursive(from, to)
    if fs.isDir(from) then
        fs.makeDir(to)
        for _, file in ipairs(fs.list(from)) do
            copyRecursive(fs.combine(from, file), fs.combine(to, file))
        end
    else
        fs.copy(from, to)
    end
end

function filesystem.copy(from, to)
    local f = resolve(from)
    local t = resolve(to)
    copyRecursive(f, t)
end

function filesystem.move(from, to)
    return fs.move(resolve(from), resolve(to))
end

function filesystem.rename(from, to)
    return filesystem.move(from, to)
end

function filesystem.getSize(path)
    return fs.getSize(resolve(path))
end

function filesystem.getFreeSpace(path)
    return fs.getFreeSpace(resolve(path))
end

function filesystem.attributes(path)
    local p = resolve(path)
    if not fs.exists(p) then
        return nil
    end
    return {
        size = fs.getSize(p),
        isDir = fs.isDir(p),
        isReadOnly = fs.isReadOnly(p),
        created = os.clock(),
        modified = os.clock(),
        path = p
    }
end

function filesystem.getMounts()
    local mounts = {}
    for _, name in ipairs(fs.list("/")) do
        if string.match(name, "^disk") then
            table.insert(mounts, "/" .. name)
        end
    end
    return mounts
end

function filesystem.readFile(path)
    local h = fs.open(resolve(path), "r")
    if not h then return nil end
    local data = h.readAll()
    h.close()
    return data
end

function filesystem.writeFile(path, data)
    local h = fs.open(resolve(path), "w")
    if not h then return nil end
    h.write(data)
    h.close()
    return true
end

function filesystem.appendFile(path, data)
    local h = fs.open(resolve(path), "a")
    if not h then return nil end
    h.write(data)
    h.close()
    return true
end

function filesystem.open(path, mode)
    local handle = fs.open(resolve(path), mode)
    if not handle then
        return nil
    end

    local file = {}

    function file.readAll()
        return handle.readAll()
    end

    function file.readLine(trailing)
        return handle.readLine(trailing)
    end

    function file.read(n)
        return handle.read(n)
    end

    function file.write(data)
        handle.write(data)
    end

    function file.writeLine(data)
        handle.writeLine(data)
    end

    function file.flush()
        if handle.flush then
            handle.flush()
        end
    end

    function file.seek(whence, offset)
        if handle.seek then
            return handle.seek(whence, offset)
        end
    end

    function file.close()
        handle.close()
    end

    return file
end

function filesystem.walk(path)
    local results = {}
    local function scan(p)
        for _, file in ipairs(fs.list(p)) do
            local full = fs.combine(p, file)
            table.insert(results, full)
            if fs.isDir(full) then
                scan(full)
            end
        end
    end
    scan(resolve(path))
    return results
end

return filesystem