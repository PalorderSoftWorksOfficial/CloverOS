-- CloverOS Help: browse the installed manual pages and system information.
-- deps injected by runtime/desktop.lua: window, paths, users, kernel
local M = {}

local TOPICS = {
	{ title = "Getting started", file = "welcome" },
	{ title = "The shell", file = "man.man" },
	{ title = "Command reference", file = "ls.man" },
	{ title = "Package manager (apt)", file = "apt.man" },
	{ title = "Users and sudo", file = "sudo.man" },
	{ title = "System information", file = "neofetch.man" },
}

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local paths = deps.paths
	local kernel = deps.kernel

	local state = {
		topic = 1,
		page = {},
		status = "",
	}

	local function aboutLines()
		local version = "unknown"
		pcall(function()
			version = dofile(paths:join("etc", "version.lua")).version()
		end)
		local user = deps.users and deps.users:currentName() or "none"
		return {
			"CloverOS " .. version .. " - documentation",
			"",
			"Welcome to the CloverOS manual.",
			"",
			"Type a command in the text shell and read its page with:",
			"    man <topic>",
			"",
			"From this desktop press F1 to open a terminal window.",
			"Press F5 for the Activities overview, where every",
			"installed application is listed.",
			"",
			"Current user: " .. user,
			"Session:      " .. (kernel and kernel.name() or "text"),
			"Uptime:       " .. string.format("%.1f min", (kernel and kernel.uptime() or os.clock()) / 60),
		}
	end

	local function loadTopic()
		local topic = TOPICS[state.topic]
		if not topic then
			return
		end
		state.page = {}
		if topic.file == "welcome" then
			state.page = aboutLines()
			state.status = "getting started"
			return
		end
		local h = fs.open(paths:join("etc", "man", topic.file), "r")
		if not h then
			state.page = { "No manual page for " .. topic.title .. "." }
			state.status = "missing: etc/man/" .. topic.file
			return
		end
		for line in h.readAll():gmatch("([^\n]*)\n?") do
			state.page[#state.page + 1] = line
		end
		h.close()
		state.status = topic.title
	end

	loadTopic()

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()

			term.setBackgroundColor(colors.blue)
			term.setCursorPos(1, 1)
			local bar = " Help "
			term.write(bar .. string.rep(" ", math.max(0, win.frame.w - 1 - #bar)))
			term.setBackgroundColor(colors.gray)

			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, 2)
			local topic = TOPICS[state.topic]
			term.write((topic and topic.title or "") .. "  (" .. state.topic .. "/" .. #TOPICS .. ")")
			term.setTextColor(colors.white)

			local rows = math.max(1, win.frame.h - 5)
			for i = 1, rows do
				local line = state.page[i]
				if line then
					term.setCursorPos(2, 3 + i - 1)
					term.write(line:sub(1, win.frame.w - 3))
				end
			end

			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write("left/right change topic  F5 reload")
			term.setTextColor(colors.white)
		end,
		onKey = function(w, key)
			if key == keys.left then
				state.topic = math.max(1, state.topic - 1)
				loadTopic()
			elseif key == keys.right then
				state.topic = math.min(#TOPICS, state.topic + 1)
				loadTopic()
			elseif key == keys.f5 then
				loadTopic()
			end
		end,
		onChar = function() end,
		onClose = function() end,
	}
end

return M
