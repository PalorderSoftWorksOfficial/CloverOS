-- CloverOS Calculator: a GNOME Calculator style app, keyboard driven.
-- deps injected by runtime/desktop.lua: window, notify, desktop
local M = {}

-- Recursive-descent evaluator for + - * / and parentheses over decimals.
-- Hand-rolled instead of loadstring so an expression can never execute
-- anything but arithmetic, and so the result is testable without a sandbox.
local function evaluate(expression)
	local text = tostring(expression or ""):gsub("%s", "")
	local pos = 1

	local function peek()
		return text:sub(pos, pos)
	end

	local parseExpr, parseTerm, parseFactor

	local function parseNumber()
		local start = pos
		while peek():match("[%d%.]") do
			pos = pos + 1
		end
		local value = tonumber(text:sub(start, pos - 1))
		if value == nil then
			return nil, "bad number at " .. start
		end
		return value
	end

	parseFactor = function()
		local ch = peek()
		if ch == "-" then
			pos = pos + 1
			local value, err = parseFactor()
			if value == nil then
				return nil, err
			end
			return -value
		elseif ch == "(" then
			pos = pos + 1
			local value, err = parseExpr()
			if value == nil then
				return nil, err
			end
			if peek() ~= ")" then
				return nil, "missing )"
			end
			pos = pos + 1
			return value
		elseif ch:match("[%d%.]") then
			return parseNumber()
		end
		return nil, "unexpected '" .. (ch == "" and "end" or ch) .. "'"
	end

	parseTerm = function()
		local left, err = parseFactor()
		if left == nil then
			return nil, err
		end
		while peek() == "*" or peek() == "/" do
			local op = peek()
			pos = pos + 1
			local right
			right, err = parseFactor()
			if right == nil then
				return nil, err
			elseif op == "/" and right == 0 then
				return nil, "division by zero"
			end
			if op == "*" then
				left = left * right
			else
				left = left / right
			end
		end
		return left
	end

	parseExpr = function()
		local left, err = parseTerm()
		if left == nil then
			return nil, err
		end
		while peek() == "+" or peek() == "-" do
			local op = peek()
			pos = pos + 1
			local right
			right, err = parseTerm()
			if right == nil then
				return nil, err
			end
			if op == "+" then
				left = left + right
			else
				left = left - right
			end
		end
		return left
	end

	local value, err = parseExpr()
	if value == nil then
		return nil, err
	end
	if pos <= #text then
		return nil, "unexpected '" .. text:sub(pos, pos) .. "'"
	end
	return value
end

M.evaluate = evaluate

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local notify = deps.notify

	local buffer = ""
	local result = ""
	local status = "type an expression"

	local function press(ch)
		if ch:match("[%d%+%-%*%/%%%.%(%)])" ) then
			buffer = buffer .. ch
			status = "expression"
		elseif ch == "=" then
			local value, err = evaluate(buffer)
			if value == nil then
				result = ""
				status = "error: " .. tostring(err)
				if notify then
					notify({ app = "calculator", title = "error: " .. tostring(err) })
				end
			else
				result = string.format("%.6f", value):gsub("%.?0+$", "")
				status = buffer .. " ="
				buffer = result
			end
		elseif ch == "\8" then
			buffer = buffer:sub(1, -2)
		end
	end

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(2, 2)
			term.setTextColor(colors.yellow)
			term.write("Calculator")
			term.setTextColor(colors.white)

			term.setCursorPos(2, 4)
			term.setBackgroundColor(colors.black)
			term.write(" " .. status:sub(1, win.frame.w - 4))
			term.setCursorPos(2, 5)
			term.write(" " .. (buffer ~= "" and buffer or "0"):sub(1, win.frame.w - 4))
			if result ~= "" then
				term.setCursorPos(2, 6)
				term.setTextColor(colors.lime)
				term.write(" = " .. result:sub(1, win.frame.w - 5))
				term.setTextColor(colors.white)
			end
			term.setBackgroundColor(colors.gray)

			term.setTextColor(colors.lightGray)
			term.setCursorPos(2, win.frame.h - 1)
			term.write("0-9 + - * / ( )  enter:=  bs:delete  c:clear")
			term.setTextColor(colors.white)
		end,
		onKey = function(_w, key)
			if key == keys.enter then
				press("=")
			elseif key == keys.backspace then
				press("\8")
			elseif key == keys.c then
				buffer = ""
				result = ""
				status = "cleared"
			end
		end,
		onChar = function(_w, ch)
			press(ch)
		end,
		onClose = function() end,
	}
end

return M
