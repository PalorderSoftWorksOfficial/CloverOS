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
local dumpWindow = window.create(term.current(), 1, 1, 1, 1, false)
function disableoutput()
    ogTerm = term.current()
    term.redirect(dumpWindow)
    return ogTerm
end
function enableoutput(ogTerm)
    term.redirect(ogTerm)
end

local envType = nil
menuOptions("Select your OS environment", {"CC:Tweaked", "CraftOS"}, {
    function() envType = "cct" end,
    function() envType = "craftos" end
})

if envType == "craftos" then
    print("Setting up CraftOS environment...")
    pcall(function()
        shell.run("attach left drive")
        shell.run("attach right speaker")
        shell.run("attach back monitor")
        if disk and disk.insertDisk then
            disk.insertDisk("left", "C:\\CloverOS_Disks\\0")
        end
    end)
    print("Environment setup complete.")
    sleep(1)
end

local githubPagesBaseURL = "https://palordersoftworksofficial.github.io/CloverOS/"
local rawBaseURL = "https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/"
local manifestURL_Pages = githubPagesBaseURL .. "files.manifest"
local manifestURL_Raw = manifestURL_Pages

local function listMounts()
    local mounts = {
        { name = "computer (root)", path = "/" }
    }
    for _, mount in ipairs(fs.list("/")) do
        local path = "/" .. mount
        if fs.isDir(path) and mount:match("^disk%d*$") and mount ~= "rom" then
            table.insert(mounts, { name = mount, path = path })
        end
    end
    return mounts
end

local disks = listMounts()
if #disks == 0 then
    print("No disks detected! Insert one and reboot.")
    return
end

local choices = {}
local actions = {}
local selectedDisk = nil

for i, d in ipairs(disks) do
    table.insert(choices, d.name)
    actions[i] = function()
        selectedDisk = d
    end
end

menuOptions("Select target disk", choices, actions)

if not selectedDisk then
    print("No disk selected. Aborting.")
    return
end

print("Selected disk: " .. selectedDisk.name .. " (" .. selectedDisk.path .. ")")

local sourceChoice = nil
local baseURL = nil
local manifestURL = nil

menuOptions("Select source server", {"GitHub Pages (recommended)", "Raw GitHub"}, {
    function()
        baseURL = githubPagesBaseURL
        manifestURL = manifestURL_Pages
        sourceChoice = "pages"
    end,
    function()
        baseURL = rawBaseURL
        manifestURL = manifestURL_Raw
        sourceChoice = "raw"
    end
})

local edition = nil
menuOptions("Select CloverOS edition", {"default", "soft"}, {
    function() edition = "default" end,
    function() edition = "soft" end
})

local fileList = {}
if edition == "default" then
    local manifestPath = selectedDisk.path .. "/files.manifest"
    shell.run("wget " .. manifestURL .. " " .. manifestPath)
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
        for i, v in ipairs(fileList) do
        if v == "netinstall.lua" then
            table.remove(fileList, i)
            break
        end
    end
    _G.softinstall = false
    else
        print("Failed to read manifest. Aborting.")
        return
    end
elseif edition == "soft" then
    table.insert(fileList, "CloverOS_OS.lua")
    for i, v in ipairs(fileList) do
    if v == "netinstall.lua" then
        table.remove(fileList, i)
        break
    end
end
    local basicCommands = {
        "bin/cd.exe",
        "bin/cls.exe",
        "bin/dir.exe",
        "bin/del.exe",
        "bin/copy.exe",
        "bin/move.exe",
        "bin/ren.exe",
        "bin/mkdir.exe",
        "bin/rmdir.exe",
        "bin/type.exe",
        "bin/man.exe",
        "bin/makeboot.exe",
        "bin/peripherals.exe",
        "bin/eject.exe",
        "bin/label.exe",
        "bin/edit.exe",
        "bin/drive.exe",
        "bin/apt.exe"
    }

    local manFiles = {
        "etc/man/cd.man",
        "etc/man/cls.man",
        "etc/man/dir.man",
        "etc/man/del.man",
        "etc/man/copy.man",
        "etc/man/move.man",
        "etc/man/ren.man",
        "etc/man/mkdir.man",
        "etc/man/rmdir.man",
        "etc/man/type.man",
        "etc/man/man.man"
    }

    for _, file in ipairs(basicCommands) do
        table.insert(fileList, file)
    end

    for _, man in ipairs(manFiles) do
        table.insert(fileList, man)
    end
end

for _, file in ipairs(fileList) do
    print("Downloading " .. file)
    local dir = file:match("(.*/)")
    if dir then fs.makeDir(selectedDisk.path .. "/" .. dir) end
    shell.run("wget " .. baseURL .. file .. " " .. selectedDisk.path .. "/" .. file)
end

print("CloverOS installed successfully to " .. selectedDisk.path)
_G.softinstall = true
sleep(1)

local minuxChoice = nil
menuOptions("Do you also want to install Minux OS? CloverOS is inspired by it.", {"Yes", "No"}, {
    function() minuxChoice = true end,
    function() minuxChoice = false end
})

if minuxChoice then
    print("Launching Minux OS installer...")
    shell.run("wget https://minux.cc/netinstall /tmp/minux_netinstall.lua")
    shell.run("/tmp/minux_netinstall.lua")
end

print("Installation complete.")
sleep(2)
os.reboot()
