local basalt = require("basalt")
local cloverOS = require("kernel/CloverOS_OS")

local termW, termH = term.getSize()
local main = basalt.createFrame("main")
main:setSize(termW, termH)

-- Load custom apps
local apps = cloverOS.getCustomApps()
for i, app in ipairs(apps) do
    local button = main:addButton("appButton" .. i)
    button:setText(app.name)
    button:setSize(20, 3)
    button:setPosition(2, (i - 1) * 4 + 2)
    button:onClick(function()
        app.run()
    end)
end

basalt.run()