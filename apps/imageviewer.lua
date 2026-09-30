-- CloverOS Image Viewer: browse .nfp images, paint-format pictures.
-- deps injected by runtime/desktop.lua: window, paths, notify, theme, desktop
local M = {}

-- Parse NFP (nano for potatOS paint) text into rows of color numbers.
-- Character -> color follows the CC:Tweaked paint convention; a space is
-- transparent (0). Split out from drawing so tests can check it directly.
function M.parse(lines)
	local rows = {}
	for _, line in ipairs(lines or {}) do
		local row = {}
		for i = 1, #line do
			row[#row + 1] = paintutils and paintutils.parseChar
				and paintutils.parseChar(line:sub(i, i))
				or M.charToColor(line:sub(i, i))
		end
		rows[#rows + 1] = row
	end
	return rows
end

function M.charToColor(ch)
	local map = {
		["0"] = colors.white, ["1"] = colors.orange, ["2"] = colors.magenta,
		["3"] = colors.lightBlue, ["4"] = colors.yellow, ["5"] = colors.lime,
		["6"] = colors.pink, ["7"] = colors.gray, ["8"] = colors.lightGray,
		["9"] = colors.cyan, ["a"] = colors.purple, ["b"] = colors.blue,
		["c"] = colors.brown, ["d"] = colors.green, ["e"] = colors.red,
		["f"] = colors.black,
	}
	return map[ch] or 0
end

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local paths = deps.paths
	local notify = deps.notify
	local theme = deps.theme
	local desktop = deps.desktop

	local dir = "/"
	local names = {}
	local index = 1
	local image = {}
	local status = "no image loaded"
	local fileName = nil

	local function refresh()
		names = {}
		if fs.isDir(dir) then
			local ok, list = pcall(fs.list, dir)
			if ok then
				for _, name in ipairs(list) do
					if name:sub(-4) == ".nfp" or name:sub(-4) == ".paint" then
						names[#names + 1] = name
					end
				end
			end
		end
		table.sort(names)
		if #names == 0 then
			dir = paths and paths:join("etc", "clover", "wallpapers") or "etc/clover/wallpapers"
			if fs.isDir(dir) then
				local ok, list = pcall(fs.list, dir)
				if ok then
					for _, name in ipairs(list) do
						if name:sub(-4) == ".nfp" then
							names[#names + 1] = name
						end
					end
				end
			end
			table.sort(names)
		end
		index = math.min(index, math.max(1, #names))
	end

	local function load()
		if #names == 0 then
			image = {}
			status = "no .nfp images found"
			return
		end
		local name = names[index]
		local path = fs.combine(dir, name)
		local handle = fs.open(path, "r")
		if not handle then
			status = "cannot read " .. name
			return
		end
		local lines = {}
		while true do
			local line = handle.readLine()
			if not line then
				break
			end
			lines[#lines + 1] = line
		end
		handle.close()
		image = M.parse(lines)
		fileName = name
		status = name .. " (" .. #image .. " rows)"
	end

	local function drawImage()
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
		term.clear()
		for y = 1, math.min(#image, win.frame.h - 4) do
			local row = image[y]
			for x = 1, math.min(#row, win.frame.w - 2) do
				local color = row[x]
				if type(color) == "number" and color ~= 0 then
					term.setCursorPos(x + 1, y + 2)
					term.setBackgroundColor(color)
					term.write(" ")
				end
			end
		end
		term.setBackgroundColor(colors.gray)
		term.setTextColor(colors.lightGray)
		term.setCursorPos(2, win.frame.h - 2)
		term.write(status:sub(1, win.frame.w - 3))
		term.setCursorPos(2, win.frame.h - 1)
		term.write("left/right: image  w: wallpaper")
		term.setTextColor(colors.white)
	end

	refresh()
	if #names > 0 then
		load()
	end

	return {
		onDraw = drawImage,
		onKey = function(_w, key)
			if key == keys.right then
				index = (index % math.max(1, #names)) + 1
				load()
			elseif key == keys.left then
				index = ((index - 2) % math.max(1, #names)) + 1
				load()
			elseif key == keys.r then
				refresh()
				load()
			elseif key == keys.w and fileName and theme then
				-- set as wallpaper: copy next to the config, flip the
				-- setting, persist
				local target = paths and paths:join("home", ".config", "clover")
					or ".config/clover"
				fs.makeDir(target)
				local destination = fs.combine(target, "wallpaper.nfp")
				local source = fs.combine(dir, fileName)
				local okCopy = pcall(fs.copy, source, destination)
				if okCopy and desktop and desktop.themeCfg then
					desktop.themeCfg.wallpaper = destination
					if desktop.saveTheme then
						desktop.saveTheme()
					end
					status = "wallpaper set: " .. fileName
					if notify then
						notify({ app = "imageviewer", title = "Wallpaper set: " .. fileName })
					end
				else
					status = "could not set wallpaper"
				end
			end
		end,
		onChar = function(_w, ch) end,
		onClose = function() end,
	}
end

return M
