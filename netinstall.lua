local baseURL = "https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/"
local manifestFile = "files.manifest"

-- download manifest first
shell.run("wget " .. baseURL .. manifestFile .. " " .. manifestFile)

local fileList = {}
local f = fs.open(manifestFile, "r")
if f then
    local function lines(file)
        return function()
            local line = file.readLine()
            if line then return line end
        end
    end

    for line in lines(f) do
        table.insert(fileList, line)
    end

    f.close()
else
    print("Failed to open manifest file!")
    return
end

for _, file in ipairs(fileList) do
    print("Downloading " .. file)
    local dir = file:match("(.*/)")
    if dir then fs.makeDir(dir) end
    shell.run("wget " .. baseURL .. file .. " " .. file)
end

print("✅ All files downloaded successfully!")
