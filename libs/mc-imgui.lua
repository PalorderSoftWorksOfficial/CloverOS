-- MC-ImGui (vendored from THEHHOY/MC-ImGui, MIT License, see libs/MC-ImGui-LICENSE)
-- Hardened for CloverOS: title bar with close/minimize controls, fixed
-- undefined width/height in frame rendering, corrected widget hitboxes,
-- and deterministic event results. Global state is intentional in the
-- upstream design; CloverOS wraps it behind runtime/gui.lua.

local imgui = {
	style = {
		primary = colors.blue,
		secondary = colors.gray,
		text = colors.white,
		background = colors.black,
	},
	frames = {},
}

imgui.objects = {}

function imgui.objects.button(tbl)
	local button = {}
	button.x = tbl.x
	button.y = tbl.y
	button.label = tbl.label or "button"
	button.id = tbl.id
	function button.event(ev, parent)
		if ev[1] == "mouse_click" then
			if ev[4] == parent.position.y + button.y then
				local mx = ev[3]
				if mx >= button.x + parent.position.x and mx < parent.position.x + button.x + #button.label then
					return {
						type = "button_click",
						mouseButton = ev[2],
						id = button.id,
					}
				end
			end
		end
	end

	function button.render()
		term.setCursorPos(button.x, button.y + 1)
		term.setBackgroundColor(imgui.style.primary)
		term.setTextColor(colors.white)
		term.write(button.label)
	end

	return button
end

function imgui.objects.label(tbl)
	local label = {}
	label.x = tbl.x
	label.y = tbl.y
	label.label = tbl.label or ""
	label.id = tbl.id
	function label.event() end

	function label.render()
		term.setCursorPos(label.x, label.y + 1)
		term.setBackgroundColor(imgui.style.secondary)
		term.setTextColor(colors.white)
		term.write(label.label)
	end

	return label
end

function imgui.objects.textbox(tbl)
	local box = {}
	box.x = tbl.x
	box.y = tbl.y
	box.placeholder = tbl.placeholder or ""
	box.text = tbl.text or ""
	box.id = tbl.id
	box.width = tbl.width or math.max(#box.placeholder + 2, 8)
	box.typing = false

	function box.event(ev, parent)
		if ev[1] == "mouse_click" then
			local mx, my = ev[3], ev[4]
			if my == parent.position.y + box.y
				and mx >= parent.position.x + box.x
				and mx < parent.position.x + box.x + box.width then
				box.typing = true
			else
				box.typing = false
			end
		elseif ev[1] == "key" then
			if box.typing then
				if ev[2] == keys.enter then
					local text = box.text
					box.text = ""
					box.typing = false
					return {
						type = "textbox_enter",
						text = text,
						id = box.id,
					}
				elseif ev[2] == keys.backspace then
					box.text = box.text:sub(1, -2)
				end
			end
		elseif ev[1] == "char" then
			if box.typing then
				box.text = box.text .. ev[2]
			end
		end
	end

	function box.render()
		term.setCursorPos(box.x, box.y + 1)
		term.setBackgroundColor(box.typing and colors.black or imgui.style.secondary)
		term.setTextColor(colors.white)
		local shown = #box.text > 0 and box.text or box.placeholder
		if #shown > box.width then
			shown = shown:sub(1, box.width)
		end
		term.write(shown .. string.rep(" ", box.width - #shown))
	end

	return box
end

function imgui.init(win, parent)
	win.setPaletteColor(colors.gray, 0x252525)
	imgui.window = win
	imgui.parent = parent or term.native()
	imgui.termSize = { win.getSize() }
end

function imgui.setStyle(style)
	imgui.style = style
end

function imgui.createFrame(name, x, y, w, h)
	local frame = {
		elements = {},
		w = w,
		h = h,
	}

	frame.win = window.create(imgui.window, x, y, w, h)
	frame.label = name
	frame.style = {
		indent = true,
		maximised = true,
	}
	frame.hold = {}
	frame.position = { x = x, y = y }
	frame.visible = true
	frame.closeRequested = false

	frame.setVisible = function(bool)
		frame.visible = bool and true or false
	end

	-- draws only the title bar and elements; window content belongs to the
	-- app's onDraw callback which runs first (see runtime/gui.lua)
	frame.render = function()
		term.redirect(frame.win)
		term.blit("\3" .. (" "):rep(w - 1) .. "\4",
			colors.toBlit(colors.white) .. colors.toBlit(imgui.style.text):rep(w - 1) .. colors.toBlit(colors.white),
			colors.toBlit(colors.red) .. colors.toBlit(imgui.style.primary):rep(w - 1) .. colors.toBlit(colors.orange))
		term.setBackgroundColor(imgui.style.primary)
		term.setTextColor(imgui.style.text)
		term.setCursorPos(3, 1)
		term.write(name)
		for _, a in ipairs(frame.elements) do
			a.render()
		end
		term.redirect(imgui.parent or term.native())
		frame.win.redraw()
	end

	frame.indent = function(bool)
		frame.style.indent = bool and true or false
	end

	frame.setMaximised = function(bool)
		if bool then
			frame.win.reposition(frame.position.x, frame.position.y, w, h)
		else
			frame.win.reposition(frame.position.x, frame.position.y, w, 1)
		end
		frame.style.maximised = bool and true or false
	end

	-- CloverOS extension: live resize (window snapping); updates the same
	-- width/height upvalues the render and hit-test code uses
	frame.setBounds = function(nx, ny, nw, nh)
		w, h = nw, nh
		frame.w, frame.h = nw, nh
		frame.position.x, frame.position.y = nx, ny
		frame.win.reposition(nx, ny, nw, frame.style.maximised and nh or 1)
	end

	frame.insert = function(el)
		table.insert(frame.elements, el)
	end

	frame.processEvent = function(ev)
		local results = {}

		if ev[1] == "mouse_click" then
			local mx, my = ev[3], ev[4]
			if my == frame.position.y then
				if mx == frame.position.x + w - 1 then
					frame.closeRequested = true
					return results
				elseif mx == frame.position.x then
					frame.setMaximised(not frame.style.maximised)
					return results
				elseif mx > frame.position.x and mx < frame.position.x + w then
					frame.hold.offset = mx - frame.position.x
					frame.holded = true
					return results
				end
			end
		elseif ev[1] == "mouse_drag" then
			if frame.holded then
				local nx = math.max(1, math.min(ev[3] - frame.hold.offset, imgui.termSize[1] - w + 1))
				local ny = math.max(1, math.min(ev[4], imgui.termSize[2] - (frame.style.maximised and h or 1) + 1))
				frame.position.x = nx
				frame.position.y = ny
				frame.win.reposition(nx, ny, w, frame.style.maximised and h or 1)
				frame.render()
			end
			return results
		elseif ev[1] == "mouse_up" then
			frame.holded = false
		end

		if frame.style.maximised then
			for _, a in ipairs(frame.elements) do
				local e = a.event(ev, frame)
				if e then
					table.insert(results, e)
				end
			end
		end
		return results
	end

	table.insert(imgui.frames, frame)
	return frame
end

function imgui.render()
	imgui.window.setVisible(false)
	imgui.window.clear()
	for _, a in ipairs(imgui.frames) do
		if a.visible then
			term.redirect(a.win)
			a.render()
		end
	end
	term.redirect(imgui.parent or term.native())
	imgui.window.setVisible(true)
end

return imgui
