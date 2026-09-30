-- CloverOS theme: palettes, accent colors and wallpapers.
--
-- The Ubuntu look adapted to CraftOS' 16-color palette: a light and a dark
-- mode built around aubergine and orange, an accent color the desktop and
-- the menus reuse, and wallpapers that are either one of the built-in
-- patterns or an .nfp image. Everything persists per user in
-- ~/.config/clover/desktop.cfg. A missing or damaged file must never stop
-- the desktop, so every read falls back to the defaults and every write
-- reports failure instead of raising.
local M = {}

local MODES = {
	light = {
		bg = colors.white,
		text = colors.black,
		bar = colors.lightGray,
		barText = colors.black,
	},
	dark = {
		bg = colors.black,
		text = colors.white,
		bar = colors.black,
		barText = colors.white,
	},
}

M.ACCENTS = { "orange", "purple", "blue", "green", "red", "lime" }

local DEFAULTS = { mode = "dark", accent = "orange", wallpaper = "aubergine" }

function M.defaults()
	local cfg = {}
	for key, value in pairs(DEFAULTS) do
		cfg[key] = value
	end
	return cfg
end

-- Never nil: an unknown mode falls back to dark rather than failing the
-- desktop that asked for it.
function M.palette(name)
	local mode = MODES[name or ""] and name or "dark"
	local palette = { mode = mode }
	for key, value in pairs(MODES[mode]) do
		palette[key] = value
	end
	return palette
end

function M.accent(name)
	if type(colors) == "table" and type(colors[name or ""]) == "number" then
		return colors[name]
	end
	return colors.orange
end

function M.nextAccent(current)
	for i, name in ipairs(M.ACCENTS) do
		if name == current then
			return M.ACCENTS[(i % #M.ACCENTS) + 1]
		end
	end
	return M.ACCENTS[1]
end

-- ---------- wallpapers ----------
-- The built-in patterns are pure functions of (x, y, accent) so they can be
-- tested without a terminal and drawn cell by cell; CraftOS has no layered
-- drawing, and this keeps every pixel deterministic.
local PATTERNS = {
	solid = function(_x, _y, accent)
		return accent
	end,
	aubergine = function(x, y, accent)
		return ((x + y) % 6 < 2) and accent or colors.purple
	end,
	grid = function(x, y, accent)
		return (x % 5 == 1 and (y - 2) % 4 == 1) and accent or colors.black
	end,
}

function M.patternColor(name, x, y, accent)
	local pattern = PATTERNS[name or ""] or PATTERNS.aubergine
	return pattern(x, y, accent)
end

-- Wallpaper ids: "aubergine" | "solid" | "grid" | a path ending in .nfp.
-- Bundled images come from etc/clover/wallpapers; an image copied to
-- ~/.config/clover/wallpaper.nfp (Files: "set as wallpaper") shows up as
-- Custom.
function M.wallpapers(paths)
	local list = {
		{ id = "aubergine", label = "Aubergine wave" },
		{ id = "solid", label = "Solid accent" },
		{ id = "grid", label = "Dark grid" },
	}
	local dirs = {}
	if paths and type(paths.join) == "function" then
		dirs[#dirs + 1] = paths:join("etc", "clover", "wallpapers")
		dirs[#dirs + 1] = paths:join("home", ".config", "clover")
	end
	dirs[#dirs + 1] = "etc/clover/wallpapers"
	local seen = {}
	for _, dir in ipairs(dirs) do
		if type(fs) == "table" and fs.isDir(dir) then
			local ok, names = pcall(fs.list, dir)
			if ok and type(names) == "table" then
				for _, name in ipairs(names) do
					if type(name) == "string" and name:sub(-4) == ".nfp" then
						local id = fs.combine(dir, name)
						if not seen[id] then
							seen[id] = true
							list[#list + 1] = {
								id = id,
								label = (name == "wallpaper.nfp" and "Custom") or name:gsub("%.nfp$", ""),
							}
						end
					end
				end
			end
		end
	end
	return list
end

function M.configPath(paths, user)
	local home = "home"
	if paths and type(paths.join) == "function" then
		home = paths:join("home", user or "")
	end
	return fs.combine(home, ".config/clover/desktop.cfg")
end

function M.load(paths, user)
	local cfg = M.defaults()
	local path = M.configPath(paths, user)
	if type(fs) ~= "table" or not fs.exists(path) then
		return cfg
	end
	local handle = fs.open(path, "r")
	if not handle then
		return cfg
	end
	local data = handle.readAll()
	handle.close()
	if type(data) ~= "string" then
		return cfg
	end
	local ok, value = pcall(textutils.unserialize, data)
	if not ok or type(value) ~= "table" then
		return cfg
	end
	for _, key in ipairs({ "mode", "accent", "wallpaper" }) do
		local v = value[key]
		if type(v) == "string" and v ~= "" then
			cfg[key] = v
		end
	end
	return cfg
end

function M.save(paths, user, cfg)
	if type(textutils) ~= "table" or type(textutils.serialize) ~= "function" then
		return false
	end
	local path = M.configPath(paths, user)
	if type(fs) ~= "table" or type(fs.open) ~= "function" then
		return false
	end
	fs.makeDir(fs.getDir(path))
	local handle = fs.open(path, "w")
	if not handle then
		return false
	end
	handle.write(textutils.serialize({
		mode = (cfg and cfg.mode) or DEFAULTS.mode,
		accent = (cfg and cfg.accent) or DEFAULTS.accent,
		wallpaper = (cfg and cfg.wallpaper) or DEFAULTS.wallpaper,
	}))
	handle.close()
	return true
end

-- Draw an .nfp wallpaper. Returns false when the target is not a readable
-- image, so the caller can fall back to a pattern; hosts without
-- paintutils.parseImage are such a case too.
function M.drawNfp(target, w, h, accent)
	if type(target) ~= "string" or target:find("%.nfp$") == nil then
		return false
	end
	if type(fs) ~= "table" or type(fs.open) ~= "function" or not fs.exists(target) then
		return false
	end
	if type(paintutils) ~= "table" or type(paintutils.parseImage) ~= "function" then
		return false
	end
	local handle = fs.open(target, "r")
	if not handle then
		return false
	end
	local okData, data = pcall(handle.readAll, handle)
	handle.close()
	if not okData or type(data) ~= "string" then
		return false
	end
	local okImage, image = pcall(paintutils.parseImage, data)
	if not okImage or type(image) ~= "table" then
		return false
	end
	for y = 2, h do
		term.setCursorPos(1, y)
		term.setBackgroundColor(accent)
		term.write(string.rep(" ", w))
	end
	if type(paintutils.drawImage) == "function" then
		pcall(paintutils.drawImage, image, 1, 2)
	else
		for y = 1, math.min(#image, h - 1) do
			local row = image[y]
			if type(row) == "table" then
				for x = 1, math.min(#row, w) do
					local color = row[x]
					if type(color) == "number" and color ~= 0 then
						term.setCursorPos(x, y + 1)
						term.setBackgroundColor(color)
						term.write(" ")
					end
				end
			end
		end
	end
	term.setBackgroundColor(colors.black)
	return true
end

-- Paint the wallpaper for a screen w x h (row 1 is the panel's).
function M.draw(paths, cfg, w, h)
	if type(term) ~= "table" or type(term.setCursorPos) ~= "function"
		or type(term.write) ~= "function" then
		return false
	end
	w = tonumber(w) or 51
	h = tonumber(h) or 19
	local accent = M.accent(cfg and cfg.accent)
	local name = (cfg and cfg.wallpaper) or DEFAULTS.wallpaper
	if M.drawNfp(name, w, h, accent) then
		return true
	end
	for y = 2, h do
		for x = 1, w do
			term.setCursorPos(x, y)
			term.setBackgroundColor(M.patternColor(name, x, y, accent))
			term.write(" ")
		end
	end
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
	return true
end

return M
