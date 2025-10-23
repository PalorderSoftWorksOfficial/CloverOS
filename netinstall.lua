local baseURL = "https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/"
local manifestFile = "files.manifest"

local function listMounts()
    local mounts = {}
    for _, mount in ipairs(fs.list("/")) do
        if fs.isDir(mount) then
            if mount:match("^disk%d*$") or mount == "rom" or mount == "computer" then
                table.insert(mounts, mount)
            end
        end
    end
    return mounts
end

local function drawMenu(options, selected)
    term.clear()
    term.setCursorPos(1,1)
    print("== Select Install Target ==")
    print("")
    for i, opt in ipairs(options) do
        if i == selected then
            print("> [" .. opt .. "]")
        else
            print("  [" .. opt .. "]")
        end
    end
end

local options = listMounts()
if #options == 0 then
    print("No disks detected! Insert one and reboot.")
    return
end

local selected = 1
drawMenu(options, selected)

while true do
    local e, key = os.pullEvent("key")
    if key == keys.up then
        selected = selected - 1
        if selected < 1 then selected = #options end
        drawMenu(options, selected)
    elseif key == keys.down then
        selected = selected + 1
        if selected > #options then selected = 1 end
        drawMenu(options, selected)
    elseif key == keys.enter then
        break
    end
end

local target = options[selected]
print("Selected target: " .. target)
print("Preparing to install CloverOS to /" .. target)
sleep(1)

local targetPath = "/" .. target .. "/" .. manifestFile
if not fs.exists(targetPath) then
    print("Downloading files.manifest...")
    shell.run("wget " .. baseURL .. manifestFile .. " " .. targetPath)
end

local fileList = {}
local f = fs.open(targetPath, "r")
if f then
    local line = f.readLine()
    while line do
        table.insert(fileList, line)
        line = f.readLine()
    end
    f.close()
else
    print("Failed to open manifest file!")
    return
end

for _, file in ipairs(fileList) do
    print("Downloading " .. file)
    local dir = file:match("(.*/)")
    if dir then fs.makeDir("/" .. target .. "/" .. dir) end
    shell.run("wget " .. baseURL .. file .. " /" .. target .. "/" .. file)
end

print("✅ CloverOS installed successfully to /" .. target)
