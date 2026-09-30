-- CloverOS Clocks: clock, stopwatch and countdown timer, GNOME style.
-- deps injected by runtime/desktop.lua: window, notify
local M = {}

-- hh:mm:ss from a number of seconds; used by the stopwatch and the timer.
function M.format(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local notify = deps.notify

	local mode = "clock" -- clock | stopwatch | timer
	local last = os.clock()

	local swRunning = false
	local swElapsed = 0

	local timerSet = 0 -- seconds the countdown was set to
	local timerLeft = 0
	local timerRunning = false
	local timerExpired = false
	local timerInput = ""

	local function step()
		local now = os.clock()
		local dt = now - last
		last = now
		if dt < 0 or dt > 60 then
			dt = 0 -- host suspended or clock jumped; do not fast-forward
		end
		if swRunning then
			swElapsed = swElapsed + dt
		end
		if timerRunning then
			timerLeft = timerLeft - dt
			if timerLeft <= 0 then
				timerLeft = 0
				timerRunning = false
				timerExpired = true
				if notify then
					notify({ app = "clocks", title = "Timer finished" })
				end
			end
		end
	end

	return {
		onDraw = function()
			step()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(2, 2)
			term.setTextColor(colors.yellow)
			term.write("Clocks  [1]clock [2]stopwatch [3]timer")
			term.setTextColor(colors.white)

			if mode == "clock" then
				term.setCursorPos(2, 6)
				term.write(os.date("%H:%M:%S"))
				term.setCursorPos(2, 8)
				term.setTextColor(colors.lightGray)
				term.write(os.date("%A, %d %B %Y"))
				term.setTextColor(colors.white)
			elseif mode == "stopwatch" then
				term.setCursorPos(2, 6)
				term.write(M.format(swElapsed))
				term.setCursorPos(2, 8)
				term.setTextColor(colors.lightGray)
				term.write("space: start/stop  r: reset")
				term.setTextColor(colors.white)
			else
				term.setCursorPos(2, 4)
				term.write("set: " .. timerInput .. "_ seconds")
				term.setCursorPos(2, 6)
				term.write(M.format(timerLeft))
				if timerExpired then
					term.setTextColor(colors.orange)
					term.setCursorPos(2, 8)
					term.write("** timer finished **")
					term.setTextColor(colors.white)
				end
				term.setCursorPos(2, 10)
				term.setTextColor(colors.lightGray)
				term.write("0-9: set  enter: start  space: pause")
				term.setTextColor(colors.white)
			end
			term.setCursorPos(2, win.frame.h - 1)
			term.setTextColor(colors.lightGray)
			term.write("1/2/3: mode")
			term.setTextColor(colors.white)
		end,
		onKey = function(_w, key)
			if key == keys.one then
				mode = "clock"
			elseif key == keys.two then
				mode = "stopwatch"
			elseif key == keys.three then
				mode = "timer"
			elseif mode == "stopwatch" then
				if key == keys.space then
					swRunning = not swRunning
				elseif key == keys.r then
					swRunning = false
					swElapsed = 0
				end
			elseif mode == "timer" then
				if key == keys.enter then
					if tonumber(timerInput) and tonumber(timerInput) > 0 then
						timerSet = tonumber(timerInput)
						timerLeft = timerSet
						timerRunning = true
						timerExpired = false
					end
				elseif key == keys.space then
					timerRunning = not timerRunning and timerLeft > 0
				elseif key == keys.backspace then
					timerInput = timerInput:sub(1, -2)
				end
			end
		end,
		onChar = function(_w, ch)
			if mode == "timer" and ch:match("%d") and #timerInput < 6 then
				timerInput = timerInput .. ch
			end
		end,
		onClose = function() end,
	}
end

return M
