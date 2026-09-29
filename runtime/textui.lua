-- CloverOS text-mode UI: terminal primitives and screen helpers.
local M = {}

M.__index = M

function M.new(paths)
	local self = setmetatable({}, M)
	self.paths = paths
	self.term = term
	return self
end

function M:size()
	return self.term.getSize()
end

function M:clear(bg, fg)
	self.term.setBackgroundColor(bg or colors.black)
	self.term.setTextColor(fg or colors.white)
	self.term.clear()
	self.term.setCursorPos(1, 1)
end

function M:write(text)
	self.term.write(tostring(text or ""))
end

function M:println(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	print(table.concat(parts, " "))
end

function M:at(x, y, text, fg, bg)
	local w, h = self.term.getSize()
	x = math.max(1, math.min(x, w))
	y = math.max(1, math.min(y, h))
	self.term.setCursorPos(x, y)
	if fg then
		self.term.setTextColor(fg)
	end
	if bg then
		self.term.setBackgroundColor(bg)
	end
	self.term.write(tostring(text or ""))
	self.term.setTextColor(colors.white)
	self.term.setBackgroundColor(colors.black)
end

function M:center(y, text, fg, bg)
	local w = self:size()
	text = tostring(text or "")
	local x = math.max(1, math.floor((w - #text) / 2) + 1)
	self:at(x, y, text, fg, bg)
end

function M:line(y, char, fg, bg)
	local w = self:size()
	self:at(1, y, string.rep(char or "-", w), fg, bg)
end

local notifyText = nil
local notifyUntil = 0

function M:notify(text)
	notifyText = tostring(text or "")
	notifyUntil = os.clock() + 3
end

function M:drawNotify(y)
	if notifyText and os.clock() < notifyUntil then
		local w = self:size()
		local x = math.max(1, w - #notifyText - 2)
		self.term.setBackgroundColor(colors.white)
		self.term.setTextColor(colors.black)
		self.term.setCursorPos(x, y or self:size())
		self.term.clearLine()
		self.term.write(" " .. notifyText .. " ")
		self.term.setBackgroundColor(colors.black)
		self.term.setTextColor(colors.white)
	elseif notifyText then
		notifyText = nil
	end
end

function M:hostname()
	local label = os.getComputerLabel()
	if label and label ~= "" then
		return label
	end
	return "computer-" .. tostring(os.getComputerID())
end

function M:versionString()
	local ok, v = pcall(dofile, self.paths:join("etc", "version.lua"))
	if ok and type(v) == "table" and v.version then
		return v.name .. " " .. v.version()
	end
	return "CloverOS"
end

function M:motd()
	local h = fs.open(self.paths:join("etc", "motd.txt"), "r")
	if not h then
		return ""
	end
	local data = h.readAll()
	h.close()
	return data
end

function M:splash()
	self:clear(colors.black, colors.green)
	local logo = {
		"   _____ _                      ____   _____ ",
		"  / ____| |                    / __ \\ / ____|",
		" | |    | | _____   _____ _ __| |  | | (___  ",
		" | |    | |/ _ \\ \\ / / _ \\ '__| |  | |\\___ \\ ",
		" | |____| | (_) |\\ V /  __/ |  | |__| |____) |",
		"  \\_____|_|\\___/  \\/ \\___|_|   \\____/|_____/ ",
	}
	local w = self:size()
	for i, line in ipairs(logo) do
		if #line <= w then
			self:center(2 + i, line, colors.green)
		end
	end
	self:center(10, self:versionString() .. " - text mode", colors.white)
end

function M:prompt(promptText, hidden, history, completion)
	if promptText and promptText ~= "" then
		self.term.write(tostring(promptText))
	end
	if hidden then
		return read("*", history, completion)
	end
	return read(nil, history, completion)
end

return M
