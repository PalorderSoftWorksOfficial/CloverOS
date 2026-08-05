local M = {}

function M.new(kernel, root)
	local self = {
		kernel = kernel,
		root = root,
	}

	function self:clear()
		kernel.term.setBackgroundColor(colors.black)
		kernel.term.setTextColor(colors.white)
		kernel.term.clear()
		kernel.term.setCursorPos(1, 1)
	end

	function self:println(...)
		local out = {}
		for i = 1, select("#", ...) do
			out[i] = tostring(select(i, ...))
		end
		print(table.concat(out, " "))
	end

	function self:write(...)
		local out = {}
		for i = 1, select("#", ...) do
			out[i] = tostring(select(i, ...))
		end
		write(table.concat(out, " "))
	end

	function self:center(y, text, fg, bg)
		local w = select(1, kernel.term.getSize())
		text = tostring(text or "")
		local x = math.max(1, math.floor((w - #text) / 2) + 1)
		if fg then
			kernel.term.setTextColor(fg)
		end
		if bg then
			kernel.term.setBackgroundColor(bg)
		end
		kernel.term.setCursorPos(x, y)
		kernel.term.write(text)
		kernel.term.setTextColor(colors.white)
		kernel.term.setBackgroundColor(colors.black)
	end

	function self:hostname()
		local label = os.getComputerLabel()
		if label and label ~= "" then
			return label
		end
		return "computer-" .. tostring(os.getComputerID())
	end

	function self:splash()
		self:clear()
		local lines = {
			"   _____ _                      ____   _____ ",
			"  / ____| |                    / __ \\ / ____|",
			" | |    | | _____   _____ _ __| |  | | (___  ",
			" | |    | |/ _ \\ \\ / / _ \\ '__| |  | |\\___ \",
			" | |____| | (_) |\\ V /  __/ |  | |__| |____) |",
			"  \\_____|_|\\___/ \\/ \\___|_|   \\____/|_____/ ",
		}

		for i, line in ipairs(lines) do
			self:center(2 + i, line, colors.green)
			kernel.sleep(0.04)
		end

		self:center(10, "CloverOS", colors.white)
		kernel.sleep(0.35)
	end

	return self
end

return M