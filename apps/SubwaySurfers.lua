-- Subway Surfers Clone for Wireless Advanced Pocket Computer

-- Initialize variables
local playerX = 2
local playerY = 2
local playerDirection = "right"
local speed = 0.1
local score = 0
local coins = 0
local obstacles = {}
local coinsCollectible = {}
local gameRunning = true
local lastFrameTime = os.clock()

-- Game constants
local screenWidth = 20
local screenHeight = 10
local playerChar = "P"
local obstacleChar = "#"
local coinChar = "O"

-- Initialize saved data
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
    local saveData = {
        score = score,
        coins = coins
    }
    local file = fs.open("subway_save", "w")
    file.write(textutils.serialize(saveData))
    file.close()
end

-- Initialize screen
local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawPlayer()
    term.setCursorPos(playerX, playerY)
    write(playerChar)
end

local function drawObstacle(x, y)
    term.setCursorPos(x, y)
    write(obstacleChar)
end

local function drawCoin(x, y)
    term.setCursorPos(x, y)
    write(coinChar)
end

local function drawScore()
    term.setCursorPos(1, 1)
    write("Score: " .. score .. " Coins: " .. coins)
end

local function spawnObstacle()
    local x = screenWidth
    local y = math.random(3, screenHeight)
    table.insert(obstacles, {x = x, y = y})
end

local function spawnCoin()
    local x = screenWidth
    local y = math.random(3, screenHeight)
    table.insert(coinsCollectible, {x = x, y = y})
end

local function moveObstacles()
    for i, obstacle in ipairs(obstacles) do
        obstacle.x = obstacle.x - 1
        if obstacle.x < 1 then
            table.remove(obstacles, i)
        end
    end
end

local function moveCoins()
    for i, coin in ipairs(coinsCollectible) do
        coin.x = coin.x - 1
        if coin.x < 1 then
            table.remove(coinsCollectible, i)
        end
    end
end

local function checkCollisions()
    for _, obstacle in ipairs(obstacles) do
        if obstacle.x == playerX and obstacle.y == playerY then
            gameRunning = false
        end
    end
    for i, coin in ipairs(coinsCollectible) do
        if coin.x == playerX and coin.y == playerY then
            table.remove(coinsCollectible, i)
            coins = coins + 1
            score = score + 10
        end
    end
end

local function update()
    moveObstacles()
    moveCoins()
    checkCollisions()
    drawScore()
end

local function drawGame()
    clearScreen()
    drawPlayer()
    for _, obstacle in ipairs(obstacles) do
        drawObstacle(obstacle.x, obstacle.y)
    end
    for _, coin in ipairs(coinsCollectible) do
        drawCoin(coin.x, coin.y)
    end
end

local function handleInput()
    local event, key = os.pullEvent("key")
    if key == keys.left then
        if playerX > 1 then
            playerX = playerX - 1
        end
    elseif key == keys.right then
        if playerX < screenWidth then
            playerX = playerX + 1
        end
    elseif key == keys.up then
        if playerY > 1 then
            playerY = playerY - 1
        end
    elseif key == keys.down then
        if playerY < screenHeight then
            playerY = playerY + 1
        end
    end
end

-- Game loop
loadSave()
while gameRunning do
    -- Spawning obstacles and coins
    if math.random(1, 20) == 1 then
        spawnObstacle()
    end
    if math.random(1, 15) == 1 then
        spawnCoin()
    end
    
    -- Game update
    if os.clock() - lastFrameTime >= speed then
        lastFrameTime = os.clock()
        update()
        drawGame()
    end

    -- Handle input
    handleInput()
    
    -- Sleep to control game speed
    os.sleep(0.05)
end

-- End of game
clearScreen()
write("Game Over! Final Score: " .. score)
saveGame()
os.sleep(2)
