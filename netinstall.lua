-- Netinstall for CloverOS
local http = require("http")
local fs = require("fs")

local baseURL = "https://palordersoftworksofficial.github.io/CloverOS/"
local manifestURL = baseURL .. "files.manifest"

-- Fetch the manifest
local response = http.get(manifestURL)
if not response then
    print("Failed to fetch files manifest")
    return
end

-- Read all file paths from manifest
local files = {}
for line in response.readAll():gmatch("[^\r\n]+") do
    table.insert(files, line)
end
response.close()

-- Download each file
for _, file in ipairs(files) do
    local fileURL = baseURL .. file
    print("Downloading " .. file)
    local fResponse = http.get(fileURL)
    if fResponse then
        local content = fResponse.readAll()
        fResponse.close()
        local dir = file:match("(.*/)")
        if dir then fs.makeDir(dir) end
        local f = fs.open(file, "w")
        f.write(content)
        f.close()
    else
        print("Failed to download " .. file)
    end
end

print("All files downloaded successfully!")
