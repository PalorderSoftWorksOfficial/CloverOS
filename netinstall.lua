local baseURL = "https://palordersoftworksofficial.github.io/CloverOS/"
local manifestFile = "files.manifest"

-- Make sure manifest exists locally
if not fs.exists(manifestFile) then
    print("Downloading files.manifest...")
    shell.run("wget " .. baseURL .. manifestFile .. " " .. manifestFile)
end

local fileList = {}
local f = fs.open(manifestFile, "r")
for line in f:lines() do
    table.insert(fileList, line)
end
f:close()

-- Download all files
for _, file in ipairs(fileList) do
    print("Downloading " .. file)
    local dir = file:match("(.*/)")
    if dir then fs.makeDir(dir) end
    shell.run("wget " .. baseURL .. file .. " " .. file)
end

print("All files downloaded successfully!")
