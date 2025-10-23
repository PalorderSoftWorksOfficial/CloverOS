-- Subway Surfers Clone for Wireless Advanced Pocket Computer

-- Lanes: 1=left, 2=center, 3=right
local lanes = {1, 2, 3}
local playerLane = 2
local playerY = 5 -- vertical position in lane for jump
local jumpHeight = 2
local jumping = false
local jumpProgress = 0
local speed = 0.2
local score = 0
local coins = 0
local obstacles = {}
local coinsCollectible = {}
local gameRunning = true
local lastFrameTime = os.clock()

local screenWidth = 20
local screenHeight = 10
local playerChar = "P"
local obstacleChar = "#"
local coinChar = "O"

-- Saved data
local function loadSave()
    if fs.exists("subway_save") then
        local file = fs.open("subway_save", "r")
        local data = file.readAll()
        file.close()
        local savedData = textutils.unserialize(data)
        score = savedData.score or 0
        coins = savedData.coins or 0
    else
        score = 0
        coins = 0
    end
end

local function saveGame()
    local saveData = {score = score, coins = coins}
    local file = fs.open("subway_save", "w")
    file.write(textutils.serialize(saveData))
    file.close()
end

-- Screen utilities
local function clearScreen()
    term.clear()
    term.setCursorPos(1,1)
end

local function drawPlayer()
    term.setCursorPos(playerLane * 6, playerY)
    write(playerChar)
end

local function drawObstacle(ob)
    term.setCursorPos(ob.x, ob.y)
    write(obstacleChar)
end

local function drawCoin(c)
    term.setCursorPos(c.x, c.y)
    write(coinChar)
end

local function drawScore()
    term.setCursorPos(1,1)
    write("Score: " .. score .. " Coins: " .. coins)
end

-- Spawn functions
local function spawnObstacle()
    local lane = lanes[math.random(1, #lanes)]
    table.insert(obstacles, {x=screenWidth, y=playerY, lane=lane})
end

local function spawnCoin()
    local lane = lanes[math.random(1, #lanes)]
    table.insert(coinsCollectible, {x=screenWidth, y=playerY, lane=lane})
end

-- Movement
local function moveObjects()
    for i=#obstacles,1,-1 do
        obstacles[i].x = obstacles[i].x - 1
        if obstacles[i].x < 1 then table.remove(obstacles,i) end
    end
    for i=#coinsCollectible,1,-1 do
        coinsCollectible[i].x = coinsCollectible[i].x - 1
        if coinsCollectible[i].x < 1 then table.remove(coinsCollectible,i) end
    end
end

local function checkCollisions()
    for _, ob in ipairs(obstacles) do
        if ob.x == playerLane * 6 and ob.y == playerY then
            gameRunning = false
        end
    end
    for i=#coinsCollectible,1,-1 do
        local c = coinsCollectible[i]
        if c.x == playerLane * 6 and c.y == playerY then
            table.remove(coinsCollectible,i)
            coins = coins + 1
            score = score + 10
        end
    end
end

local function update()
    moveObjects()
    checkCollisions()
    score = score + 1 -- score increases as player moves
end

local function drawGame()
    clearScreen()
    drawPlayer()
    for _, ob in ipairs(obstacles) do drawObstacle(ob) end
    for _, c in ipairs(coinsCollectible) do drawCoin(c) end
    drawScore()
end

-- Jump logic
local function handleJump()
    if jumping then
        if jumpProgress < jumpHeight then
            playerY = playerY - 1
        elseif jumpProgress < jumpHeight*2 then
            playerY = playerY + 1
        end
        jumpProgress = jumpProgress + 1
        if jumpProgress >= jumpHeight*2 then
            jumping = false
            jumpProgress = 0
        end
    end
end

-- Input
local function handleInput()
    if os.pullEventRaw then
        local event, key = os.pullEventRaw()
        if event == "key" then
            if key == keys.left and playerLane > 1 then
                playerLane = playerLane - 1
            elseif key == keys.right and playerLane < #lanes then
                playerLane = playerLane + 1
            elseif key == keys.up and not jumping then
                jumping = true
            elseif key == keys.q then
                gameRunning = false
            end
        end
    end
end

-- Main game loop
loadSave()
while gameRunning do
    if math.random(1,15) == 1 then spawnObstacle() end
    if math.random(1,10) == 1 then spawnCoin() end

    if os.clock() - lastFrameTime >= speed then
        lastFrameTime = os.clock()
        update()
        handleJump()
        drawGame()
    end

    handleInput()
    os.sleep(0.05)
end

-- End game
clearScreen()
write("Game Over! Final Score: "..score.." Coins: "..coins)
saveGame()
os.sleep(2)
