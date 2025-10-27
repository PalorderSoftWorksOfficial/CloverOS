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
        if disk and disk.InsertDisk then
            disk.InsertDisk("left", "C:\\CloverOS_Disks\\0")
        end
    end)
    print("Environment setup complete.")
    sleep(1)
end

local githubPagesBaseURL = "https://palordersoftworksofficial.github.io/CloverOS/"
local rawBaseURL = "https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/"
local manifestURL_Pages = githubPagesBaseURL .. "files.manifest"
local manifestURL_Raw = rawBaseURL .. "files.manifest"

local function listMounts()
    local mounts = {}
    for _, mount in ipairs(fs.list("/")) do
        if fs.isDir(mount) and (mount:match("^disk%d*$") or mount == "rom" or mount == "computer" or mount == "/") then
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
    local manifestPath = "/" .. selectedDisk .. "/files.manifest"
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
    else
        print("Failed to read manifest. Aborting.")
        return
    end
elseif edition == "soft" then
    table.insert(fileList, "CloverOS_OS.lua")
end

for _, file in ipairs(fileList) do
    print("Downloading " .. file)
    local dir = file:match("(.*/)")
    if dir then fs.makeDir("/" .. selectedDisk .. "/" .. dir) end
    shell.run("wget " .. baseURL .. file .. " /" .. selectedDisk .. "/" .. file)
end

print("CloverOS installed successfully to /" .. selectedDisk)
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
