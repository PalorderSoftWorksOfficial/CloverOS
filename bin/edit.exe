local chars = {
	whitespace = {
		[' '] = true,
		['\n'] = true,
		['\t'] = true,
		['\r'] = true
	},

	validEscapes = {
		['a'] = true,
		['b'] = true,
		['f'] = true,
		['n'] = true,
		['r'] = true,
		['t'] = true,
		['v'] = true,
		['"'] = true,
		['\''] = true,
		['\\'] = true,
		['\n'] = true
	},

	ident = {
		['a'] = true,
		['b'] = true,
		['c'] = true,
		['d'] = true,
		['e'] = true,
		['f'] = true,
		['g'] = true,
		['h'] = true,
		['i'] = true,
		['j'] = true,
		['k'] = true,
		['l'] = true,
		['m'] = true,
		['n'] = true,
		['o'] = true,
		['p'] = true,
		['q'] = true,
		['r'] = true,
		['s'] = true,
		['t'] = true,
		['u'] = true,
		['v'] = true,
		['w'] = true,
		['x'] = true,
		['y'] = true,
		['z'] = true,
		['A'] = true,
		['B'] = true,
		['C'] = true,
		['D'] = true,
		['E'] = true,
		['F'] = true,
		['G'] = true,
		['H'] = true,
		['I'] = true,
		['J'] = true,
		['K'] = true,
		['L'] = true,
		['M'] = true,
		['N'] = true,
		['O'] = true,
		['P'] = true,
		['Q'] = true,
		['R'] = true,
		['S'] = true,
		['T'] = true,
		['U'] = true,
		['V'] = true,
		['W'] = true,
		['X'] = true,
		['Y'] = true,
		['Z'] = true,
		['_'] = true,
		['0'] = true,
		['1'] = true,
		['2'] = true,
		['3'] = true,
		['4'] = true,
		['5'] = true,
		['6'] = true,
		['7'] = true,
		['8'] = true,
		['9'] = true,

		start = {
			['a'] = true,
			['b'] = true,
			['c'] = true,
			['d'] = true,
			['e'] = true,
			['f'] = true,
			['g'] = true,
			['h'] = true,
			['i'] = true,
			['j'] = true,
			['k'] = true,
			['l'] = true,
			['m'] = true,
			['n'] = true,
			['o'] = true,
			['p'] = true,
			['q'] = true,
			['r'] = true,
			['s'] = true,
			['t'] = true,
			['u'] = true,
			['v'] = true,
			['w'] = true,
			['x'] = true,
			['y'] = true,
			['z'] = true,
			['A'] = true,
			['B'] = true,
			['C'] = true,
			['D'] = true,
			['E'] = true,
			['F'] = true,
			['G'] = true,
			['H'] = true,
			['I'] = true,
			['J'] = true,
			['K'] = true,
			['L'] = true,
			['M'] = true,
			['N'] = true,
			['O'] = true,
			['P'] = true,
			['Q'] = true,
			['R'] = true,
			['S'] = true,
			['T'] = true,
			['U'] = true,
			['V'] = true,
			['W'] = true,
			['X'] = true,
			['Y'] = true,
			['Z'] = true,
			['_'] = true
		},
	},

	digits = {
		['0'] = true,
		['1'] = true,
		['2'] = true,
		['3'] = true,
		['4'] = true,
		['5'] = true,
		['6'] = true,
		['7'] = true,
		['8'] = true,
		['9'] = true,

		hex = {
			['0'] = true,
			['1'] = true,
			['2'] = true,
			['3'] = true,
			['4'] = true,
			['5'] = true,
			['6'] = true,
			['7'] = true,
			['8'] = true,
			['9'] = true,
			['a'] = true,
			['b'] = true,
			['c'] = true,
			['d'] = true,
			['e'] = true,
			['f'] = true,
			['A'] = true,
			['B'] = true,
			['C'] = true,
			['D'] = true,
			['E'] = true,
			['F'] = true
		}
	},

	symbols = {
		['+'] = true,
		['-'] = true,
		['*'] = true,
		['/'] = true,
		['^'] = true,
		['%'] = true,
		[','] = true,
		['{'] = true,
		['}'] = true,
		['['] = true,
		[']'] = true,
		['('] = true,
		[')'] = true,
		[';'] = true,
		['#'] = true,
		['.'] = true,
		[':'] = true,

		equality = {
			['~'] = true,
			['='] = true,
			['>'] = true,
			['<'] = true
		},

		operators = {
			['+'] = true,
			['-'] = true,
			['*'] = true,
			['/'] = true,
			['^'] = true,
			['%'] = true,
			['#'] = true
		}
	}
}

local keywords = {
	structure = {
		['and'] = true,
		['break'] = true,
		['do'] = true,
		['else'] = true,
		['elseif'] = true,
		['end'] = true,
		['for'] = true,
		['function'] = true,
		['goto'] = true,
		['if'] = true,
		['in'] = true,
		['local'] = true,
		['not'] = true,
		['or'] = true,
		['repeat'] = true,
		['return'] = true,
		['then'] = true,
		['until'] = true,
		['while'] = true
	},

	values = {
		['true'] = true,
		['false'] = true,
		['nil'] = true
	}
}

function lex(text)
	local pos = 1
	local start = 1
	local len = #text
	local buffer = {}
	local lines = {}

	local function look(delta)
		delta = pos + (delta or 0)

		return text:sub(delta, delta)
	end

	local function get()
		local char = text:sub(pos, pos)

		pos = pos + 1

		return char
	end

	local function getLevel()
		local num = 0

		while look(num) == '=' do
			num = num + 1
		end

		if look(num) == '[' then
			pos = pos + num

			return num
		else
			return nil
		end
	end

	local function getToken()
		return text:sub(start, pos - 1)
	end

	local currentLineLength = 0
	local lineoffset = 0

	local function token(type, text)
		local tk = buffer[#buffer]

		if not tk or tk.type ~= type then
			local tk = {
				type = type,
				data = text or getToken(),
				posFirst = start - lineoffset,
				posLast = pos - 1 - lineoffset
			}

			if tk.data ~= '' then
				buffer[#buffer + 1] = tk
			end
		else
			tk.data = tk.data .. (text or getToken())
			tk.posLast = tk.posFirst + #tk.data - 1
			--tk.posLast = getCol(pos - 1)
		end

		currentLineLength = currentLineLength + (text or getToken()):len()

		start = pos
		return tk
	end

	local function newline()
		lines[#lines + 1] = buffer
		buffer = {}
		get()
		token('newline')
		buffer[1] = nil
		lineoffset = lineoffset + currentLineLength
		currentLineLength = 0
	end

	local function getData(level, type)
		while true do
			local char = get()

			if char == '' then
				return
			elseif char == '\n' then
				pos = pos - 1
				token(type)
				newline()
			elseif char == ']' then
				local valid = true

				for i = 1, level do
					if look() == '=' then
						pos = pos + 1
					else
						valid = false
						break
					end
				end

				if valid and look() == ']' then
					pos = pos + 1

					return
				end
			end
		end
	end

	while true do
		while true do
			local char = look()

			if char == '\n' then
				token('whitespace')
				newline()
			elseif chars.whitespace[char] then
				pos = pos + 1
			else
				break
			end
		end

		token('whitespace')

		local char = get()

		if char == '' then
			break
		elseif char == '-' and look() == '-' then
			pos = pos + 1

			if look() == '[' then
				pos = pos + 1

				local level = getLevel()

				if level then
					getData(level, 'comment')
				else
					while true do
						local char2 = get()

						if char2 == '' or char2 == '\n' then
							pos = pos - 1
							token('comment')

							if char2 == '\n' then
								newline()
							end

							break
						end
					end
				end
			else
				while true do
					local char2 = get()

					if char2 == '' or char2 == '\n' then
						pos = pos - 1
						token('comment')

						if char2 == '\n' then
							newline()
						end

						break
					end
				end
			end

			token('comment')
		elseif char == '\'' or char == '"' then
			while true do
				local char2 = get()

				if char2 == '\\' then
					pos = pos - 1
					token('string')
					get()

					local char3 = get()

					if chars.digits[char3] then
						for i = 1, 2 do
							if chars.digits[look()] then
								pos = pos + 1
							end
						end
					elseif char3 == 'x' then
						if chars.digits.hex[look()] and chars.digits.hex[look(1)] then
							pos = pos + 2
						else
							token('unidentified')
						end
					elseif char3 == '\n' then
						pos = pos - 1
						token('escape')
						newline()
					elseif not chars.validEscapes[char3] then
                        token('unidentified')
					end

					token('escape')
				elseif char2 == '\n' then
					pos = pos - 1
					token('string')
					newline()

					break
				elseif char2 == char or char2 == '' then
					break
				end
			end

			token('string')
		elseif chars.ident.start[char] then
			while chars.ident[look()] do
				pos = pos + 1
			end

			local word = getToken()

			if keywords.structure[word] then
				token('keyword')
			elseif keywords.values[word] then
				token('value')
			else
				token('ident')
			end
		elseif chars.digits[char] or (char == '.' and chars.digits[look()]) then
			if char == '0' and look() == 'x' then
				pos = pos + 1

				while chars.digits.hex[look()] do
					pos = pos + 1
				end
			else
				while chars.digits[look()] do
					pos = pos + 1
				end

				if look() == '.' then
					pos = pos + 1

					while chars.digits[look()] do
						pos = pos + 1
					end
				end

				if look():lower() == 'e' then
					pos = pos + 1

					if look() == '-' then
						pos = pos + 1
					end

					while chars.digits[look()] do
						pos = pos + 1
					end
				end
			end

			token('number')
		elseif char == '[' then
			local level = getLevel()

			if level then
				getData(level, 'string')
				token('string')
			else
				token('symbol')
			end
		elseif char == '.' then
			if look() == '.' then
				pos = pos + 1

				if look() == '.' then
					pos = pos + 1
				end
			end

			token('symbol')
		elseif chars.symbols.equality[char] then
			if look() == '=' then
				pos = pos + 1
			end

			token('operator')
		elseif chars.symbols[char] then
			if chars.symbols.operators[char] then
				token('operator')
			else
				token('symbol')
			end
		else
			token('unidentified')
		end
	end

	lines[#lines + 1] = buffer

	return lines
end

-- Get file to edit
local tArgs = { ... }
if #tArgs == 0 then
	print( "Usage: edit <path>" )
	return
end

-- Error checking
local sPath = shell.resolve( tArgs[1] )
local bReadOnly = fs.isReadOnly( sPath )
if fs.exists( sPath ) and fs.isDir( sPath ) then
	print( "Cannot edit a directory." )
	return
end

local x,y = 1,1
local markX, markY = 1, 1
local w,h = term.getSize()
local scrollX, scrollY = 0,0

local tLines = {}
local bRunning = true

-- Colors
local highlightColor, keywordColor, commentColor, textColor, bgColor, stringColor
if term.isColor() then
	bgColor = colors.black
	textColor = colors.white
	highlightColor = colors.yellow
	keywordColor = colors.yellow
	commentColor = colors.green
	stringColor = colors.red
else
	bgColor = colors.black
	textColor = colors.white
	highlightColor = colors.white
	keywordColor = colors.white
	commentColor = colors.white
	stringColor = colors.white
end

-- Menus
local bMenu = false
local nMenuItem = 1
local tMenuItems = {}
if not bReadOnly then
	table.insert( tMenuItems, "Save" )
end
if shell.openTab then
	table.insert( tMenuItems, "Run" )
end
if peripheral.find( "printer" ) then
	table.insert( tMenuItems, "Print" )
end
table.insert( tMenuItems, "Exit" )
table.insert(tMenuItems, 'Tools')
table.insert(tMenuItems, 'Find')
table.insert(tMenuItems, 'Jump')
table.insert(tMenuItems, 'Copy')
table.insert(tMenuItems, 'VPaste')

local sStatus = "Press Ctrl to access menu"
if string.len( sStatus ) > w - 5 then
	sStatus = "Press Ctrl for menu"
end

local function load( _sPath )
	tLines = {}
	if fs.exists( _sPath ) then
		local file = io.open( _sPath, "r" )
		local sLine = file:read()
		while sLine do
			table.insert( tLines, sLine )
			sLine = file:read()
		end
		file:close()
	end

	if #tLines == 0 then
		table.insert( tLines, "" )
	end
end

local function save( _sPath )
	-- Create intervening folder
	local sDir = _sPath:sub(1, _sPath:len() - fs.getName(_sPath):len() )
	if not fs.exists( sDir ) then
		fs.makeDir( sDir )
	end

	-- Save
	local file = nil
	local function innerSave()
		file = fs.open( _sPath, "w" )
		if file then
			for n, sLine in ipairs( tLines ) do
				file.write( sLine .. "\n" )
			end
		else
			error( "Failed to open ".._sPath )
		end
	end

	local ok, err = pcall( innerSave )
	if file then
		file.close()
	end
	return ok, err
end

local tKeywords = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"]= true,
	["while"] = true,
}

local function tryWrite( sLine, regex, color )
	local match = string.match( sLine, regex )
	if match then
		if type(color) == "number" then
			term.setTextColor( color )
		else
			term.setTextColor( color(match) )
		end
		term.write( match )
		term.setTextColor( textColor )
		return string.sub( sLine, string.len(match) + 1 )
	end
	return nil
end

--[[local function writeHighlighted( sLine )
	while string.len(sLine) > 0 do
		sLine =
			tryWrite( sLine, "^%-%-%[%[.-%]%]", commentColor ) or
			tryWrite( sLine, "^%-%-.*", commentColor ) or
			tryWrite( sLine, "^\"\"", stringColor ) or
			tryWrite( sLine, "^\".-[^\\]\"", stringColor ) or
			tryWrite( sLine, "^\'\'", stringColor ) or
			tryWrite( sLine, "^\'.-[^\\]\'", stringColor ) or
			tryWrite( sLine, "^%[%[.-%]%]", stringColor ) or
			tryWrite( sLine, "^[%w_]+", function( match )
				if tKeywords[ match ] then
					return keywordColor
				end
				return textColor
			end ) or
			tryWrite( sLine, "^[^%w_]", textColor )
	end
end]]

local apis = {
	-- tables
	bit = true,
	bit32 = true,
	bitop = true,
	colors = true,
	colours = true,
	coroutine = true,
	disk = true,
	fs = true,
	gps = true,
	help = true,
	http = true,
	io = true,
	keys = true,
	math = true,
	os = true,
	paintutils = true,
	parallel = true,
	peripheral = true,
	rednet = true,
	redstone = true,
	rs = true,
	settings = true,
	shell = true,
	socket = true,
	string = true,
	table = true,
	term = true,
	textutils = true,
	vector = true,
	window = true,

	-- functions
	assert = true,
	collectgarbage = true,
	dofile = true,
	error = true,
	getfenv = true,
	getmetatable = true,
	ipairs = true,
	loadfile = true,
	loadstring = true,
	module = true,
	next = true,
	pairs = true,
	pcall = true,
	print = true,
	rawequal = true,
	rawget = true,
	rawset = true,
	require = true,
	select = true,
	setfenv = true,
	setmetatable = true,
	tonumber = true,
	tostring = true,
	type = true,
	unpack = true,
	xpcall =  true,
	printError = true,
	write = true
}

local function onUpdate()
	tokenized = lex(table.concat(tLines, '\n'))
end

local function markExists()
	if markX ~= x or markY ~= y then
		return true
	else
		return false
	end
end

local function isMarked(newX, newY)
	if (newY > markY and newY < y) or (newY > y and newY < markY) then
		return true
	end

	if newY == markY and newY == y then
		if markX > x and newX >= x and newX < markX then
			return true
		elseif markX < x and newX >= markX and newX < x then
			return true
		end
	elseif newY == markY then
		if newX < markX and y < markY then
			return true
		elseif newX >= markX and y > markY then
			return true
		end
	elseif newY == y then
		if newX < x and y > markY then
			return true
		elseif newX >= x and y < markY then
			return true
		end
	end

	return false
end

local function getMarks()
	local msx, msy
	local mex, mey

	if markY == y then
		if markX > x then
			msx = x
			msy = y
			mex = markX
			mey = markY
		else
			msx = markX
			msy = markY
			mex = x
			mey = y
		end
	else
		if markY > y then
			msx = x
			msy = y
			mex = markX
			mey = markY
		else
			msx = markX
			msy = markY
			mex = x
			mey = y
		end
	end

	return msx, msy, mex, mey
end

local function getCharDisplay(char)
	if char == '\t' then
		return '    '
	else
		return char
	end
end

local function getCharWidth(char)
	return getCharDisplay(char):len()
end

local function writeHighlighted(lineNr)
	local tokens = tokenized[lineNr] or {}
	local textColor = term.getTextColor()
	local bgColor = term.getBackgroundColor()
	local setX, setY = term.getCursorPos()
	local msx, msy, mex, mey = getMarks()

	if lineNr < mey and lineNr >= msy then
		term.setBackgroundColor(colors.white)
	end

	term.clearLine()
	term.setCursorPos(setX, setY)

	for t = 1, #tokens do
		local token = tokens[t]
		local color = colors.white

		if token.type == 'keyword' or token.type == 'operator' then
			color = colors.yellow
		elseif token.type == 'number' or token.type == 'value' then
			color = colors.purple
		elseif token.type == 'comment' then
			color = colors.green
		elseif token.type == 'ident' and apis[token.data] then
			color = colors.lightGray
		elseif token.type == 'string' then
			color = colors.cyan
		elseif token.type == 'escape' then
			color = colors.purple
		elseif token.type == 'unidentified' then
			color = colors.red
		end

		for p = 1, #token.data do
			local sub = getCharDisplay(token.data:sub(p, p))

			local cX, cY = p + token.posFirst - 1, lineNr

			if (cY == msy and cY == mey and cX >= msx and cX < mex) or (cY == msy and cY ~= mey and cX >= msx) or (cY == mey and cY ~= msy and cX < mex) or (cY > msy and cY < mey) then
				term.setTextColor(colors.black)
				term.setBackgroundColor(color)
			else
				term.setBackgroundColor(colors.black)
				term.setTextColor(color)
			end

			term.write(sub)
		end
	end

	term.setTextColor(textColor)
	term.setBackgroundColor(bgColor)
end

local tCompletions
local nCompletion

local tCompleteEnv = _ENV
local function complete( sLine )
	if settings.get( "edit.autocomplete" ) then
		local nStartPos = string.find( sLine, "[a-zA-Z0-9_%.]+$" )
		if nStartPos then
			sLine = string.sub( sLine, nStartPos )
		end
		if #sLine > 0 then
			return textutils.complete( sLine, tCompleteEnv )
		end
	end
	return nil
end

local function recomplete()
	local sLine = tLines[y]
	if not bMenu and not bReadOnly and x == string.len(sLine) + 1 then
		tCompletions = complete( sLine )
		if tCompletions and #tCompletions > 0 then
			nCompletion = 1
		else
			nCompletion = nil
		end
	else
		tCompletions = nil
		nCompletion = nil
	end
end

local function writeCompletion( sLine )
	if nCompletion then
		local sCompletion = tCompletions[ nCompletion ]
		term.setTextColor( colors.white )
		term.setBackgroundColor( colors.gray )
		term.write( sCompletion )
		term.setTextColor( textColor )
		term.setBackgroundColor( bgColor )
	end
end

local function getCursorX(lineNr)
	local line = tLines[lineNr]
	local cx = 1

	for i = 1, x - 1 do
		cx = cx + getCharWidth(line:sub(i, i))
	end

	return cx
end

local function cxToPos(lineNr, cx)
	local line = tLines[lineNr]
	local num = 1
	local pos = 1

	for i = 1, #line do
		amt = getCharWidth(line:sub(i, i))

		if num + amt > cx then
			return pos
		else
			num = num + amt
			pos = pos + 1
		end
	end

	return pos
end

local function redrawText()
	local cursorX, cursorY = x, y
	for y=1,h-1 do
		term.setCursorPos( 1 - scrollX, y )
		term.clearLine()

		local sLine = tLines[ y + scrollY ]
		if sLine ~= nil then
			--writeHighlighted( sLine )
			writeHighlighted(y + scrollY)
			if cursorY == y + scrollY and cursorX == #sLine + 1 then
				writeCompletion()
			end
		end
	end

	local cx = getCursorX(y)

	term.setCursorPos( cx - scrollX, y - scrollY )
end

--[[local function redrawLine(_nY)
	local sLine = tLines[_nY]
	if sLine then
		term.setCursorPos( 1 - scrollX, _nY - scrollY )
		term.clearLine()
		--writeHighlighted( sLine )
		writeHighlighted(_nY)
		if _nY == y and x == #sLine + 1 then
			writeCompletion()
		end
		term.setCursorPos( x - scrollX, _nY - scrollY )
	end
end]]

local redrawLine = redrawText

local function redrawMenu()
	-- Clear line
	term.setCursorPos( 1, h )
	term.clearLine()

	-- Draw line numbers
	--[[term.setCursorPos( w - string.len( "Ln "..y ) + 1, h )
	term.setTextColor( highlightColor )
	term.write( "Ln " )
	term.setTextColor( textColor )
	term.write( y )]]

	if not bMenu then
		-- Draw status
		term.setTextColor( highlightColor )
		term.write( sStatus )
		term.setTextColor( textColor )

		term.setCursorPos(w - ('[' .. x .. ':' .. y .. ']:[' .. markX .. ':' .. markY .. ']'):len() + 1, h)
		term.setTextColor(highlightColor)
		term.write('[')
		term.setTextColor(textColor)
		term.write(x)
		term.setTextColor(highlightColor)
		term.write(':')
		term.setTextColor(textColor)
		term.write(y)
		term.setTextColor(highlightColor)
		term.write(']:[')
		term.setTextColor(textColor)
		term.write(markX)
		term.setTextColor(highlightColor)
		term.write(':')
		term.setTextColor(textColor)
		term.write(markY)
		term.setTextColor(highlightColor)
		term.write(']')
		term.setTextColor(textColor)
	else
		-- Draw menu
		term.setTextColor( textColor )
		for nItem,sItem in pairs( tMenuItems ) do
			if nItem == nMenuItem then
				term.setTextColor( highlightColor )
				term.write( "[" )
				term.setTextColor( textColor )
				term.write( sItem )
				term.setTextColor( highlightColor )
				term.write( "]" )
				term.setTextColor( textColor )
			else
				term.write( " "..sItem.." " )
			end
		end
	end

	-- Reset cursor
	term.setCursorPos( getCursorX(y) - scrollX, y - scrollY )
end

local function setCursor( newX, newY )
	local oldX, oldY = x, y
	x, y = newX, newY
	local screenX = getCursorX(y) - scrollX
	local screenY = y - scrollY

	local bRedraw = false
	if screenX < 1 then
		scrollX = getCursorX(y) - 1
		screenX = 1
		bRedraw = true
	elseif screenX > w then
		scrollX = scrollX + (screenX - w)
		screenX = w
		bRedraw = true
	end

	if screenY < 1 then
		scrollY = y - 1
		screenY = 1
		bRedraw = true
	elseif screenY > h-1 then
		scrollY = y - (h-1)
		screenY = h-1
		bRedraw = true
	end

	recomplete()
	if bRedraw then
		redrawText()
	elseif y ~= oldY then
		redrawLine( oldY )
		redrawLine( y )
	else
		redrawLine( y )
	end
	term.setCursorPos( screenX, screenY )

	redrawMenu()
end

local function setCursorMark(newX, newY)
	markX, markY = newX, newY
	setCursor(newX, newY)
end

local function deleteMarked()
	if markExists() then
		local msx, msy, mex, mey = getMarks()

		if msy == mey then
			local line = tLines[mey]

			tLines[mey] = line:sub(1, msx - 1) .. line:sub(mex)
		else
			if mey - msy > 1 then
				for i = 1, mey - msy - 1 do
					table.remove(tLines, msy + 1)
				end
			end

			local line = tLines[msy]
			local line2 = tLines[msy + 1]

			tLines[msy] = line:sub(1, msx - 1) .. line2:sub(mex)
			table.remove(tLines, msy + 1)
		end

		setCursorMark(msx, msy)
	end
end

local function getMarked()
	if markExists() then
		local msx, msy, mex, mey = getMarks()

		if msy == mey then
			return tLines[msy]:sub(msx, mex - 1)
		else
			local marked = tLines[msy]:sub(msx)

			if mey - msy > 1 then
				for i = msy + 1, mey - 1 do
					marked = marked .. '\n' .. tLines[i]
				end
			end

			marked = marked .. '\n' .. tLines[mey]:sub(1, mex - 1)

			return marked
		end
	end
end

local toolsFuncs = {
	{
		'Convert 2 spaces to tabs',
		function()
			for i = 1, #tLines do
				local line = tLines[i]
				local count = 0

				while true do
					if line:sub(count * 2 + 1, count * 2 + 2) == '  ' then
						count = count + 1
					else
						break
					end
				end

				tLines[i] = ('\t'):rep(count) .. line:sub(count * 2 + 1)
			end
		end
	}, {
		'Convert tabs to 2 spaces',
		function()
			for i = 1, #tLines do
				local line = tLines[i]
				local count = 0

				while true do
					if line:sub(count + 1, count + 1) == '\t' then
						count = count + 1
					else
						break
					end
				end

				tLines[i] = ('  '):rep(count) .. line:sub(count + 1)
			end
		end
	}
}

-- for testing scrolling, etc in the tools menu
--[[for i = 1, 50 do
	table.insert(toolsFuncs, {'Do nothing ' .. tostring(i), function() end})
end]]


local findHistory = {}
local jumpHistory = {}
local vClipboard = ''

local tMenuFuncs = {
	Save = function()
		if bReadOnly then
			sStatus = "Access denied"
		else
			local ok, err = save( sPath )
			if ok then
				sStatus="Saved to "..sPath
			else
				sStatus="Error saving to "..sPath
			end
		end
		redrawMenu()
	end,
	Print = function()
		local printer = peripheral.find( "printer" )
		if not printer then
			sStatus = "No printer attached"
			return
		end

		local nPage = 0
		local sName = fs.getName( sPath )
		if printer.getInkLevel() < 1 then
			sStatus = "Printer out of ink"
			return
		elseif printer.getPaperLevel() < 1 then
			sStatus = "Printer out of paper"
			return
		end

		local screenTerminal = term.current()
		local printerTerminal = {
			getCursorPos = printer.getCursorPos,
			setCursorPos = printer.setCursorPos,
			getSize = printer.getPageSize,
			write = printer.write,
		}
		printerTerminal.scroll = function()
			if nPage == 1 then
				printer.setPageTitle( sName.." (page "..nPage..")" )
			end

			while not printer.newPage()	do
				if printer.getInkLevel() < 1 then
					sStatus = "Printer out of ink, please refill"
				elseif printer.getPaperLevel() < 1 then
					sStatus = "Printer out of paper, please refill"
				else
					sStatus = "Printer output tray full, please empty"
				end

				term.redirect( screenTerminal )
				redrawMenu()
				term.redirect( printerTerminal )

				local timer = os.startTimer(0.5)
				sleep(0.5)
			end

			nPage = nPage + 1
			if nPage == 1 then
				printer.setPageTitle( sName )
			else
				printer.setPageTitle( sName.." (page "..nPage..")" )
			end
		end

		bMenu = false
		term.redirect( printerTerminal )
		local ok, error = pcall( function()
			term.scroll()
			for n, sLine in ipairs( tLines ) do
				print( sLine )
			end
		end )
		term.redirect( screenTerminal )
		if not ok then
			print( error )
		end

		while not printer.endPage() do
			sStatus = "Printer output tray full, please empty"
			redrawMenu()
			sleep( 0.5 )
		end
		bMenu = true

		if nPage > 1 then
			sStatus = "Printed "..nPage.." Pages"
		else
			sStatus = "Printed 1 Page"
		end
		redrawMenu()
	end,
	Exit = function()
		bRunning = false
	end,
	Run = function()
		local sTempPath = "/.temp"
		local ok, err = save( sTempPath )
		if ok then
			local nTask = shell.openTab( sTempPath )
			if nTask then
				shell.switchTab( nTask )
			else
				sStatus="Error starting Task"
			end
			fs.delete( sTempPath )
		else
			sStatus="Error saving to "..sTempPath
		end
		redrawMenu()
	end,
	Tools = function()
		bMenu = false
		redrawText()
		redrawMenu()

		local bgColor = term.getBackgroundColor()
		paintutils.drawFilledBox(2, 2, w - 1, h - 1, colors.gray)
		term.setCursorPos(3, 3)
		term.write('ShEdit Tools')

		local scrollY = 0
		local height = h - 8
		local offset = 5
		local selected = 1
		local run = false

		term.setTextColor(colors.lightGray)
		term.setCursorPos(3, offset + height + 1)
		term.write('Arrows to select. Enter to run. Ctrl to cancel.')

		while true do
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.lightGray)
			local toWrite = '(' .. tostring(selected) .. '/' .. tostring(#toolsFuncs) .. ')'
			term.setCursorPos(w - toWrite:len() - 1, 3)
			term.write(toWrite)
			term.setTextColor(colors.white)

			for i = 1, height do
				local index = i + scrollY
				term.setTextColor(colors.white)

				if selected == index then
					term.setTextColor(keywordColor)
				end

				if index <= #toolsFuncs then
					paintutils.drawLine(2, offset + i - 1, w - 1, offset + i - 1, color)
					term.setCursorPos(3, offset + index - scrollY - 1)

					if selected == index then
						term.write('> ')
					else
						term.write('  ')
					end

					term.write(toolsFuncs[index][1])
				end
			end

			local evt, arg1, arg2, arg3 = os.pullEvent()
			local clampScroll = false

			if evt == 'key' then
				clampScroll = true

				if arg1 == keys.up then
					if selected == 1 then
						selected = #toolsFuncs
					else
						selected = selected - 1
					end
				elseif arg1 == keys.down then
					if selected == #toolsFuncs then
						selected = 1
					else
						selected = selected + 1
					end
				elseif arg1 == keys.pageUp then
					selected = math.max(1, math.min(#toolsFuncs, selected - height))
				elseif arg1 == keys.pageDown then
					selected = math.max(1, math.min(#toolsFuncs, selected + height))
				elseif arg1 == keys.enter then
					run = true

					break
				elseif arg1 == keys.leftCtrl then
					break
				else
					clampScroll = false
				end
			elseif evt == 'mouse_click' then
				if arg1 == 1 then
					if arg2 > 1 and arg2 < w then
						if arg3 >= offset and arg3 < offset + height then
							local index = arg3 - offset + scrollY + 1

							if index <= #toolsFuncs then
								selected = index
								run = true

								break
							end
						end
					end
				end
			elseif evt == 'mouse_scroll' then
				if arg2 > 1 and arg2 < w then
					if arg3 >= offset and arg3 < offset + height then
						scrollY = math.max(0, math.min(#toolsFuncs - height, scrollY + arg1))
					end
				end
			end

			if clampScroll == true then
				if selected > height + scrollY then
					scrollY = selected - height
				elseif selected <= scrollY then
					scrollY = selected - 1
				end
			end
		end

		term.setBackgroundColor(bgColor)
		redrawText()
		bMenu = true

		if run then
			if not bReadOnly then
				bMenu = false
				redrawMenu()
				toolsFuncs[selected][2]()
				onUpdate()
				redrawText()
				bMenu = true
			else
				sStatus = 'File is read-only'
			end
		end
	end,
	Find = function()
		term.setCursorPos(1, h)
		term.clearLine()

		term.setTextColor(highlightColor)
		term.write('Find: ')
		term.setTextColor(textColor)

		local text = read(nil, findHistory)
		table.insert(findHistory, text)

		local fLine, fPos
		local found = false

		for i = y, #tLines do
			local searchText = tLines[i]

			if i == y then
				searchText = searchText:sub(x + 1)
			end

			local searchPat = ''

			local escapedChars = {
				['%'] = true, ['.'] = true, ['('] = true, [')'] = true,
				['%'] = true, ['+'] = true, ['-'] = true, ['*'] = true,
				['?'] = true, ['['] = true, ['^'] = true, ['$'] = true
			}

			for i = 1, #text do
				local char = text:sub(i, i)

				if escapedChars[char] == true then
					searchPat = searchPat .. '%'
				end

				searchPat = searchPat .. char
			end

			local pos = searchText:find(searchPat)

			if pos then
				fLine = i
				fPos = pos

				if i == y then
					fPos = fPos + x
				end

				found = true

				break
			end
		end

		if not found then
			sStatus = 'Found no matches'
		else
			setCursorMark(fPos, fLine)
			setCursor(fPos + text:len(), fLine)
			sStatus = 'Found a match on line ' .. tostring(fLine)
		end

		redrawText()
	end,
	Jump = function()
		term.setCursorPos(1, h)
		term.clearLine()

		term.setTextColor(highlightColor)
		term.write('Jump: ')
		term.setTextColor(textColor)

		local toJump = read(nil, jumpHistory)
		table.insert(jumpHistory, toJump)

		local num = tonumber(toJump)

		if not num then
			sStatus = 'Invalid line'
		else
			if num % 1 == 0 then
				if num >= 1 and num <= #tLines then
					setCursorMark(1, num)
					sStatus = 'Successfully jumped to line ' .. toJump
				else
					sStatus = 'Line is not in the range 1 - ' .. tostring(#tLines)
				end
			else
				sStatus = 'Line must be an integer'
			end
		end

		redrawText()
	end,
	Copy = function()
		vClipboard = getMarked()

		local lines = 1

		for i = 1, #vClipboard do
			if vClipboard:sub(i, i) == '\n' then
				lines = lines + 1
			end
		end

		sStatus = 'Copied ' .. tostring(lines) .. ' lines'
	end,
	VPaste = function()
		if not bReadOnly then
			deleteMarked()
			local lines = 1

			for i = 1, #vClipboard do
				local char = vClipboard:sub(i, i)

				if char == '\n' then
					lines = lines + 1
					local sLine = tLines[y]
					tLines[y] = string.sub(sLine,1,x-1)
					table.insert( tLines, y+1, string.sub(sLine,x) )
					x = 1
					y = y + 1
				else
					tLines[y] = tLines[y]:sub(1, x - 1) .. char .. tLines[y]:sub(x)
					x = x + 1
				end
			end

			setCursorMark(x, y)
			onUpdate()
			redrawText()

			sStatus = 'Pasted ' .. tostring(lines) .. ' lines'
		else
			sStatus = 'File is read-only'
		end
	end
}

local function doMenuItem( _n )
	tMenuFuncs[tMenuItems[_n]]()
	if bMenu then
		bMenu = false
		term.setCursorBlink( true )
	end
	redrawMenu()
end

-- Actual program functionality begins
load(sPath)

term.setBackgroundColor( bgColor )
term.clear()
term.setCursorPos(getCursorX(y), y)
term.setCursorBlink( true )

recomplete()
onUpdate()
redrawText()
redrawMenu()

local function acceptCompletion()
	if nCompletion then
		-- Append the completion
		local sCompletion = tCompletions[ nCompletion ]
		tLines[y] = tLines[y] .. sCompletion
		onUpdate()
		setCursorMark( x + string.len( sCompletion ), y )
	end
end

local holdingShift = false

-- Handle input
while bRunning do
	local sEvent, param, param2, param3 = os.pullEvent()
	if sEvent == "key" then
		local oldX, oldY = x, y
		if param == keys.up then
			local cursorSet = setCursorMark

			if holdingShift then
				cursorSet = setCursor
			end

			-- Up
			if not bMenu then
				if nCompletion then
					-- Cycle completions
					nCompletion = nCompletion - 1
					if nCompletion < 1 then
						nCompletion = #tCompletions
					end
					redrawLine(y)

				elseif y > 1 then
					-- Move cursor up
					--[[cursorSet(
						math.min( x, string.len( tLines[y - 1] ) + 1 ),
						y - 1
					)]]

					local cx = getCursorX(y)
					local pos = cxToPos(y - 1, cx)

					cursorSet(pos, y - 1)
				else
					cursorSet(1, y)
				end
			end

		elseif param == keys.down then
			local cursorSet = setCursorMark

			if holdingShift then
				cursorSet = setCursor
			end

			-- Down
			if not bMenu then
				-- Move cursor down
				if nCompletion then
					-- Cycle completions
					nCompletion = nCompletion + 1
					if nCompletion > #tCompletions then
						nCompletion = 1
					end
					redrawLine(y)

				elseif y < #tLines then
					-- Move cursor down
					--[[cursorSet(
						math.min( x, string.len( tLines[y + 1] ) + 1 ),
						y + 1
					)]]

					local cx = getCursorX(y)
					local pos = cxToPos(y + 1, cx)

					cursorSet(pos, y + 1)
				else
					cursorSet(#tLines[y] + 1, y)
				end
			end

		elseif param == keys.tab then
			-- Tab
			if not bMenu and not bReadOnly then
				if nCompletion and x == string.len(tLines[y]) + 1 then
					-- Accept autocomplete
					acceptCompletion()
				else
					local msx, msy, mex, mey = getMarks()

					for i = msy, mey do
						local line = tLines[i]

						if holdingShift then
							-- Unindent line
							if line:sub(1, 1) == '\t' then
								line = line:sub(2)
							end
						else
							-- Indent line
							if markExists() then
								line = '\t' .. line
							else
								line = line:sub(1, x - 1) .. '\t' .. line:sub(x)
							end
						end

						tLines[i] = line
					end

					if holdingShift then
						markX = math.max(1, markX - 1)
						setCursor(math.max(1, x - 1), y)
					else
						markX = markX + 1
						setCursor(x + 1, y)
					end

					onUpdate()
					redrawText()
				end
			end

		elseif param == keys.pageUp then
			local cursorSet = setCursorMark

			if holdingShift then
				cursorSet = setCursor
			end

			-- Page Up
			if not bMenu then
				-- Move up a page
				local newY
				if y - (h - 1) >= 1 then
					newY = y - (h - 1)
				else
					newY = 1
				end
				cursorSet(
					math.min( x, string.len( tLines[newY] ) + 1 ),
					newY
				)
			end

		elseif param == keys.pageDown then
			local cursorSet = setCursorMark

			if holdingShift then
				cursorSet = setCursor
			end

			-- Page Down
			if not bMenu then
				-- Move down a page
				local newY
				if y + (h - 1) <= #tLines then
					newY = y + (h - 1)
				else
					newY = #tLines
				end
				local newX = math.min( x, string.len( tLines[newY] ) + 1 )
				cursorSet( newX, newY )
			end

		elseif param == keys.home then
			local cursorSet = setCursorMark

			if holdingShift then
				cursorSet = setCursor
			end

			-- Home
			if not bMenu then
				-- Move cursor to the beginning
				if x > 1 then
					cursorSet(1,y)
				end
			end

		elseif param == keys["end"] then
			local cursorSet = setCursorMark

			if holdingShift then
				cursorSet = setCursor
			end

			-- End
			if not bMenu then
				-- Move cursor to the end
				local nLimit = string.len( tLines[y] ) + 1
				if x < nLimit then
					cursorSet( nLimit, y )
				end
			end

		elseif param == keys.left then
			local cursorSet = setCursorMark

			if holdingShift then
				cursorSet = setCursor
			end

			-- Left
			if not bMenu then
				if x > 1 then
					-- Move cursor left
					cursorSet( x - 1, y )
				elseif x==1 and y>1 then
					cursorSet( string.len( tLines[y-1] ) + 1, y - 1 )
				end
			else
				-- Move menu left
				nMenuItem = nMenuItem - 1
				if nMenuItem < 1 then
					nMenuItem = #tMenuItems
				end
				redrawMenu()
			end

		elseif param == keys.right then
			local cursorSet = setCursorMark

			if holdingShift then
				cursorSet = setCursor
			end

			-- Right
			if not bMenu then
				local nLimit = string.len( tLines[y] ) + 1
				if x < nLimit then
					-- Move cursor right
					cursorSet( x + 1, y )
				elseif nCompletion and x == string.len(tLines[y]) + 1 then
					-- Accept autocomplete
					acceptCompletion()
				elseif x==nLimit and y<#tLines then
					-- Go to next line
					cursorSet( 1, y + 1 )
				end
			else
				-- Move menu right
				nMenuItem = nMenuItem + 1
				if nMenuItem > #tMenuItems then
					nMenuItem = 1
				end
				redrawMenu()
			end

		elseif param == keys.delete then
			-- Delete
			if not bMenu and not bReadOnly then
				if markExists() then
					deleteMarked()
				else
					local nLimit = string.len( tLines[y] ) + 1
					if x < nLimit then
						local sLine = tLines[y]
						tLines[y] = string.sub(sLine,1,x-1) .. string.sub(sLine,x+1)
					elseif y<#tLines then
						tLines[y] = tLines[y] .. tLines[y+1]
						table.remove( tLines, y+1 )
					end
				end

				onUpdate()
				recomplete()
				redrawText()
			end

		elseif param == keys.backspace then
			-- Backspace
			if not bMenu and not bReadOnly then
				if markExists() then
					deleteMarked()
				else
					if x > 1 then
						-- Remove character
						local sLine = tLines[y]
						tLines[y] = string.sub(sLine,1,x-2) .. string.sub(sLine,x)
						setCursorMark( x - 1, y )
					elseif y > 1 then
						-- Remove newline
						local sPrevLen = string.len( tLines[y-1] )
						tLines[y-1] = tLines[y-1] .. tLines[y]
						table.remove( tLines, y )
						setCursorMark( sPrevLen + 1, y - 1 )
					end
				end

				onUpdate()
				recomplete()
				redrawText()
			end

		elseif param == keys.enter then
			-- Enter
			if not bMenu and not bReadOnly then
				deleteMarked()

				-- Newline
				local sLine = tLines[y]
				local _,tabs=string.find(sLine,"^[\t]+")
				if not tabs then
					tabs=0
				end
				tLines[y] = string.sub(sLine,1,x-1)
				table.insert( tLines, y+1, string.rep('\t',tabs)..string.sub(sLine,x) )
				onUpdate()
				setCursorMark( tabs + 1, y + 1 )
				redrawText()

			elseif bMenu then
				-- Menu selection
				doMenuItem( nMenuItem )

			end

		elseif (param == keys.leftCtrl or param == keys.rightCtrl) and not param2 then
			-- Menu toggle
			bMenu = not bMenu
			if bMenu then
				term.setCursorBlink( false )
			else
				term.setCursorBlink( true )
			end
			redrawMenu()

		elseif param == 42 then
			holdingShift = true
		end

	elseif sEvent == 'key_up' then
		if param == 42 then
			holdingShift = false
		end

	elseif sEvent == "char" then
		if not bMenu and not bReadOnly then
			deleteMarked()

			-- Input text
			local sLine = tLines[y]
			tLines[y] = string.sub(sLine,1,x-1) .. param .. string.sub(sLine,x)
			onUpdate()
			setCursorMark( x + 1, y )

		elseif bMenu then
			-- Select menu items
			for n,sMenuItem in ipairs( tMenuItems ) do
				if string.lower(string.sub(sMenuItem,1,1)) == string.lower(param) then
					doMenuItem( n )
					break
				end
			end
		end

	elseif sEvent == "paste" then
		if not bMenu and not bReadOnly then
			-- Input text
			--[[local sLine = tLines[y]
			tLines[y] = string.sub(sLine,1,x-1) .. param .. string.sub(sLine,x)
			onUpdate()
			setCursorMark( x + string.len( param ), y )]]

			--[[deleteMarked()

			local newX, newY = x, y

			for i = 1, #param do
				local char = param:sub(i, i)

				if char == '\n' then
					local rest = tLines[newY]:sub(newX)
					tLines[newY] = tLines[newY]:sub(1, newX - 1)

					table.insert(tLines, rest, newY + 1)

					newY = newY + 1
					newX = 1
				else
					local line = tLines[newY]

					line = line:sub(1, newX - 1) .. char .. line:sub(newX)

					tLines[newY] = line
					newX = newX + 1
				end
			end

			onUpdate()
			setCursorMark(newX, newY)]]

			local oldvClipboard = vClipboard
			vClipboard = param
			tMenuFuncs.VPaste()
			redrawMenu()
			vClipboard = oldvClipboard
		end

	elseif sEvent == "mouse_click" then
		local cursorSet = setCursorMark

		if holdingShift then
			cursorSet = setCursor
		end

		if not bMenu then
			if param == 1 then
				-- Left click
				local cx,cy = param2, param3
				if cy < h then
					local tx, ty = cx + scrollX, cy + scrollY
					local newX, newY

					if ty <= #tLines then
						newY = math.min(#tLines, math.max(ty, 1))
						tx = cxToPos(ty, tx)
						newX = math.min(tLines[newY]:len() + 1, math.max(1, tx))
					else
						newY = #tLines
						newX = #tLines[newY] + 1
					end

					cursorSet(newX, newY)
				end
			end
		end

	elseif sEvent == "mouse_drag" then
		if not bMenu then
			if param == 1 then
				-- Left click
				local cx,cy = param2, param3
				if cy < h then
					local tx, ty = cx + scrollX, cy + scrollY
					local newX, newY

					if ty <= #tLines then
						newY = math.min(#tLines, math.max(ty, 1))
						tx = cxToPos(ty, tx)
						newX = math.min(tLines[newY]:len() + 1, math.max(1, tx))
					else
						newY = #tLines
						newX = #tLines[newY] + 1
					end

					setCursor(newX, newY)
				end
			end
		end

	elseif sEvent == "mouse_scroll" then
		if not bMenu then
			if param == -1 then
				-- Scroll up
				if scrollY > 0 then
					-- Move cursor up
					scrollY = scrollY - 1
					redrawText()
				end

			elseif param == 1 then
				-- Scroll down
				local nMaxScroll = #tLines - (h-1)
				if scrollY < nMaxScroll then
					-- Move cursor down
					scrollY = scrollY + 1
					redrawText()
				end

			end
		end

	elseif sEvent == "term_resize" then
		w,h = term.getSize()
		setCursor( x, y )
		redrawMenu()
		redrawText()

	end
end

-- Cleanup
term.clear()
term.setCursorBlink( false )
term.setCursorPos( 1, 1 )
