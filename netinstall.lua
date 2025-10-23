local defaultSource = "https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/"

local ogTerm = term.current()
local termX, termY = term.getSize()
local bufferWindow = window.create(ogTerm, 1, 1, termX, termY)

function menuOptions(title, tChoices, tActions)
    local check = true
    local nSelection = 1
    repeat
        bufferWindow.setVisible(false)
        term.redirect(bufferWindow)
        term.clear()
        local width, height = term.getSize()
        paintutils.drawLine(1, 1, width, 1, colors.gray)
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.gray)
        print(title)
        term.setBackgroundColor(colors.black)
        print("")
        for nLine = 1, #tChoices do 
            if nSelection == nLine then
                term.setTextColor(colors.lightGray)
                print("> " .. tChoices[nLine])
                term.setTextColor(colors.white)
            else
                print("  " .. tChoices[nLine])
            end
        end
        bufferWindow.setVisible(true)
        local sEvent, nKey = os.pullEvent("key")
        if nKey == keys.up or nKey == keys.w then
            if tChoices[nSelection - 1] then nSelection = nSelection - 1 end
        elseif nKey == keys.down or nKey == keys.s then
            if tChoices[nSelection + 1] then nSelection = nSelection + 1 end
        elseif nKey == keys.enter then
            if tActions[nSelection] then
                tActions[nSelection]()
                check = false
            end
        end
    until check == false
end

-- redirect output to dummy window
local dumpWindow = window.create(term.current(), 1, 1, 1, 1, false)
function disableoutput()
    ogTerm = term.current()
    term.redirect(dumpWindow)
    return ogTerm
end
function enableoutput(ogTerm)
    term.redirect(ogTerm)
end

-- Disk selection
local function listMounts()
    local mounts = {}
    for _, mount in ipairs(fs.list("/")) do
        if fs.isDir(mount) and (mount:match("^disk%d*$") or mount == "rom" or mount == "computer") then
            table.insert(mounts, mount)
        end
    end
    return mounts
end

local disks = listMounts()
if #disks == 0 then
    print("No disks detected! Insert one and reboot.")
    return
end

local selectedDisk = nil
menuOptions("Select target disk", disks, (function()
    local actions = {}
    for i, d in ipairs(disks) do
        actions[i] = function() selectedDisk = d end
    end
    return actions
end)())

-- Edition selection
local edition = nil
menuOptions("Select CloverOS edition", {"default", "soft"}, {
    function() edition = "default" end,
    function() edition = "soft" end
})

-- Installation source
local selectedSource = defaultSource
menuOptions("Select installation source", {"GitHub - default", "Custom URL"}, {
    function() selectedSource = defaultSource end,
    function()
        print("Enter full URL for source:")
        local url = read()
        if url ~= nil and url ~= "" then selectedSource = url else selectedSource = defaultSource end
    end
})

-- Download manifest if default edition
local fileList = {}
if edition == "default" then
    local manifestPath = "/" .. selectedDisk .. "/files.manifest"
    shell.run("wget " .. selectedSource .. "files.manifest " .. manifestPath)
    if not fs.exists(manifestPath) then
        print("Failed to download manifest. Aborting.")
        return
    end
    local f = fs.open(manifestPath, "r")
    if f then
        local line = f.readLine()
        while line do
            table.insert(fileList, line)
            line = f.readLine()
        end
        f.close()
    else
        print("Failed to read manifest. Aborting.")
        return
    end
elseif edition == "soft" then
    table.insert(fileList, "CloverOS_OS.lua")
end

-- Download all files
for _, file in ipairs(fileList) do
    print("Downloading " .. file)
    local dir = file:match("(.*/)")
    if dir then fs.makeDir("/" .. selectedDisk .. "/" .. dir) end
    shell.run("wget " .. selectedSource .. file .. " /" .. selectedDisk .. "/" .. file)
end

print("CloverOS installed successfully to /" .. selectedDisk)
sleep(2)
os.reboot()
