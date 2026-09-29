-- CloverOS terminal app: runs the real shell engine inside a GUI window.
-- The app object receives lifecycle callbacks from the desktop; it never
-- pulls events itself and never draws outside its own window.
local M = {}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local session = deps.session

	local winW, winH = win.frame.w, win.frame.h
	local rows = winH - 3 -- title bar row 1, prompt row winH-1
	local width = winW

	local out = {}
	local input = ""

	-- A shell instance scoped to this window, provided by the session.
	local shell = session and session.forkWindowShell and session:forkWindowShell(win) or nil
	if not shell then
		return {
			onDraw = function() end,
			onKey = function() end,
			onChar = function() end,
			onClose = function() end,
		}
	end

	local function pushWrapped(line)
		line = tostring(line or "")
		if line == "" then
			out[#out + 1] = ""
		else
			while #line > width do
				out[#out + 1] = line:sub(1, width)
				line = line:sub(width + 1)
			end
			out[#out + 1] = line
		end
		while #out > rows do
			table.remove(out, 1)
		end
	end

	local function flush()
		for _, line in ipairs(shell:drainOutput()) do
			pushWrapped(line)
		end
	end

	local function draw()
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
		term.clear()
		for i, line in ipairs(out) do
			term.setCursorPos(1, i + 1) -- below the title bar
			term.write(line:sub(1, width))
		end
		term.setTextColor(colors.lime)
		term.setCursorPos(1, winH - 1)
		term.clearLine()
		local prompt = shell:promptLine()
		local visible = prompt .. input
		if #visible > width then
			visible = visible:sub(#visible - width + 1)
		end
		term.write(visible)
		term.setTextColor(colors.white)
	end

	local function promptLine()
		return shell:promptLine()
	end

	local function submit()
		local line = input
		input = ""
		pushWrapped(promptLine() .. line)
		pushWrapped("")
		local ok, err = pcall(shell.execute, shell, line)
		if not ok then
			pushWrapped("sh: internal error: " .. tostring(err))
		end
		flush()
	end

	return {
		onDraw = draw,
		onKey = function(w, key)
			if key == keys.enter then
				submit()
			elseif key == keys.backspace then
				input = input:sub(1, -2)
			end
		end,
		onChar = function(w, ch)
			input = input .. ch
		end,
		onClose = function() end,
	}
end

return M
