-- CloverOS Media Player: tones and jingles through a speaker peripheral,
-- found through the system layer, duck-typed like everywhere else.
-- deps injected by runtime/desktop.lua: window, system, notify
local M = {}

-- Note frequencies (Hz) for one octave of C major, plus the jingle
-- definitions. Plain data so tests can inspect them without audio hardware.
M.NOTES = {
	C4 = 261.63, D4 = 293.66, E4 = 329.63, F4 = 349.23,
	G4 = 392.00, A4 = 440.00, B4 = 493.88,
	C5 = 523.25, D5 = 587.33, E5 = 659.25, G5 = 783.99,
}

M.JINGLES = {
	login = { { "C4", 0.125 }, { "E4", 0.125 }, { "G4", 0.125 }, { "C5", 0.25 } },
	chime = { { "E5", 0.1 }, { "C5", 0.1 }, { "G4", 0.2 } },
	blip = { { "C5", 0.06 } },
}

-- The speaker surface CloverOS uses. Returns the peripheral or nil; the
-- duck typing matches runtime/system.lua's rule that nothing may compare
-- type(p) against "userdata" directly.
function M.findSpeaker(system)
	local p = nil
	if system and type(system.state) == "table" then
		for _, entry in ipairs(system.state.peripherals or {}) do
			if entry.type == "speaker" then
				p = entry.peripheral
				break
			end
		end
	end
	if p == nil and type(peripheral) == "table" and type(peripheral.find) == "function" then
		local ok, found = pcall(peripheral.find, "speaker")
		p = ok and found or nil
	end
	if type(p) ~= "table" and type(p) ~= "userdata" then
		return nil
	end
	if type(p.playNote) ~= "function" and type(p.playSound) ~= "function" then
		return nil
	end
	return p
end

-- Play one jingle by name. Returns true, or nil plus a reason; every call
-- is wrapped so a misbehaving peripheral cannot crash the app.
function M.play(speaker, notes, jingleName)
	local jingle = M.JINGLES[jingleName]
	if not jingle then
		return nil, "no such jingle: " .. tostring(jingleName)
	end
	if not speaker then
		return nil, "no speaker attached"
	end
	for _, part in ipairs(jingle) do
		local noteName, length = part[1], part[2]
		local freq = M.NOTES[noteName]
		if type(speaker.playNote) == "function" and freq then
			-- map the frequency onto the note instrument's 0-24 range
			local semitone = math.floor((freq / 261.63) * 12 + 0.5)
			local ok = pcall(speaker.playNote, speaker, "harp", 1, semitone % 25)
			if not ok then
				return nil, "speaker refused the note"
			end
		elseif type(speaker.playSound) == "function" then
			pcall(speaker.playSound, speaker, "minecraft:block.note_block.harp", 1, freq and (freq / 440) or 1)
		end
		if length and type(sleep) == "function" then
			pcall(sleep, length)
		end
	end
	return true, notes
end

function M.new(deps)
	deps = deps or {}
	local win = deps.window
	local system = deps.system
	local notify = deps.notify

	local status = "select a jingle"
	local lastPlayed = nil

	local function play(name)
		local speaker = M.findSpeaker(system)
		if not speaker then
			status = "no speaker peripheral attached"
			if notify then
				notify({ app = "media", title = status })
			end
			return
		end
		status = "playing " .. name .. "..."
		local ok, err = M.play(speaker, M.NOTES, name)
		status = ok and ("played " .. name) or ("error: " .. tostring(err))
		if ok then
			lastPlayed = name
		end
	end

	return {
		onDraw = function()
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.clear()
			term.setCursorPos(2, 2)
			term.setTextColor(colors.yellow)
			term.write("Media Player")
			term.setTextColor(colors.white)

			term.setCursorPos(2, 4)
			term.write("[1] login jingle")
			term.setCursorPos(2, 5)
			term.write("[2] chime")
			term.setCursorPos(2, 6)
			term.write("[3] blip")
			if lastPlayed then
				term.setCursorPos(2, 8)
				term.setTextColor(colors.lime)
				term.write("last: " .. lastPlayed)
				term.setTextColor(colors.white)
			end

			term.setCursorPos(2, 10)
			term.setTextColor(colors.lightGray)
			term.write(status:sub(1, win.frame.w - 3))
			term.setTextColor(colors.white)
		end,
		onKey = function(_w, key)
			if key == keys.one then
				play("login")
			elseif key == keys.two then
				play("chime")
			elseif key == keys.three then
				play("blip")
			end
		end,
		onChar = function(_w, ch) end,
		onClose = function() end,
	}
end

return M
