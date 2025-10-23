local termWidth, termHeight = 10, 20 -- Tetris grid
local grid = {}
local currentPiece
local nextPiece
local score = 0
local gameRunning = true
local lastUpdate = os.clock()
local speed = 0.5 -- seconds per fall step

-- Tetris pieces (tetrominoes)
local pieces = {
    { -- I
        {{1,1,1,1}},
        {{1},{1},{1},{1}}
    },
    { -- O
        {{1,1},{1,1}}
    },
    { -- T
        {{0,1,0},{1,1,1}},
        {{1,0},{1,1},{1,0}},
        {{1,1,1},{0,1,0}},
        {{0,1},{1,1},{0,1}}
    },
    { -- L
        {{1,0},{1,0},{1,1}},
        {{1,1,1},{1,0,0}},
        {{1,1},{0,1},{0,1}},
        {{0,0,1},{1,1,1}}
    },
    { -- J
        {{0,1},{0,1},{1,1}},
        {{1,0,0},{1,1,1}},
        {{1,1},{1,0},{1,0}},
        {{1,1,1},{0,0,1}}
    },
    { -- S
        {{0,1,1},{1,1,0}},
        {{1,0},{1,1},{0,1}}
    },
    { -- Z
        {{1,1,0},{0,1,1}},
        {{0,1},{1,1},{1,0}}
    }
}

-- Initialize empty grid
for y=1,termHeight do
    grid[y] = {}
    for x=1,termWidth do
        grid[y][x] = 0
    end
end

-- Utility functions
local function drawGrid()
    term.clear()
    for y=1,termHeight do
        for x=1,termWidth do
            if grid[y][x] ~= 0 then
                write("█")
            else
                write(".")
            end
        end
        print()
    end
    print("Score: "..score)
end

local function newPiece()
    local piece = pieces[math.random(1,#pieces)]
    local rotation = 1
    return {shape=piece, rot=rotation, x=math.floor(termWidth/2)-1, y=1}
end

local function canPlace(piece,x,y,rot)
    local shape = piece.shape[rot]
    for py=1,#shape do
        for px=1,#shape[py] do
            if shape[py][px] == 1 then
                local gx = x + px - 1
                local gy = y + py - 1
                if gx<1 or gx>termWidth or gy>termHeight or grid[gy][gx] ~= 0 then
                    return false
                end
            end
        end
    end
    return true
end

local function placePiece(piece)
    local shape = piece.shape[piece.rot]
    for py=1,#shape do
        for px=1,#shape[py] do
            if shape[py][px] == 1 then
                grid[piece.y + py -1][piece.x + px -1] = 1
            end
        end
    end
end

local function clearLines()
    local linesCleared = 0
    for y=termHeight,1,-1 do
        local full = true
        for x=1,termWidth do
            if grid[y][x] == 0 then
                full = false
                break
            end
        end
        if full then
            table.remove(grid,y)
            table.insert(grid,1,{0,0,0,0,0,0,0,0,0,0})
            linesCleared = linesCleared + 1
        end
    end
    score = score + linesCleared*100
end

-- Input handling
local function handleInput()
    local event, key = os.pullEvent("key")
    if key == keys.left and canPlace(currentPiece,currentPiece.x-1,currentPiece.y,currentPiece.rot) then
        currentPiece.x = currentPiece.x - 1
    elseif key == keys.right and canPlace(currentPiece,currentPiece.x+1,currentPiece.y,currentPiece.rot) then
        currentPiece.x = currentPiece.x + 1
    elseif key == keys.down then
        if canPlace(currentPiece,currentPiece.x,currentPiece.y+1,currentPiece.rot) then
            currentPiece.y = currentPiece.y + 1
        end
    elseif key == keys.up then
        local nextRot = currentPiece.rot + 1
        if nextRot > #currentPiece.shape then nextRot = 1 end
        if canPlace(currentPiece,currentPiece.x,currentPiece.y,nextRot) then
            currentPiece.rot = nextRot
        end
    end
end

-- Game loop
currentPiece = newPiece()
while gameRunning do
    -- Draw grid with current piece
    for y=1,termHeight do
        for x=1,termWidth do
            if grid[y][x] ~= 0 then
                term.setCursorPos(x,y)
                write("█")
            else
                term.setCursorPos(x,y)
                write(".")
            end
        end
    end
    -- Draw current piece
    local shape = currentPiece.shape[currentPiece.rot]
    for py=1,#shape do
        for px=1,#shape[py] do
            if shape[py][px] == 1 then
                local gx = currentPiece.x + px -1
                local gy = currentPiece.y + py -1
                term.setCursorPos(gx,gy)
                write("█")
            end
        end
    end
    term.setCursorPos(1,termHeight+1)
    print("Score: "..score)

    -- Handle input
    if os.pullEvent("key") then
        handleInput()
    end

    -- Automatic fall
    if os.clock() - lastUpdate >= speed then
        lastUpdate = os.clock()
        if canPlace(currentPiece,currentPiece.x,currentPiece.y+1,currentPiece.rot) then
            currentPiece.y = currentPiece.y + 1
        else
            placePiece(currentPiece)
            clearLines()
            currentPiece = newPiece()
            if not canPlace(currentPiece,currentPiece.x,currentPiece.y,currentPiece.rot) then
                gameRunning = false
            end
        end
    end

    os.sleep(0.05)
end

-- Game over
term.clear()
term.setCursorPos(1,1)
print("Game Over! Final Score: "..score)
os.sleep(2)
