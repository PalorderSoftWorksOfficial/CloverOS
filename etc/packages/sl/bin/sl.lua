-- sl: a steam locomotive for mistyped `ls` (CloverOS package payload)
local train = {
	"      ====        ________                ___________",
	"  _D _|  |_______/        \\__I_I_____===__|_________|",
	"   |(_)---  |   H\\________/ |   |        =|___ ___|",
	"   /     |  |   H  |  |     |   |         ||_| |_||",
	"  |      |  |   H  |__--------------------| [___] |",
	"  | ________|___H__/__|_____/[][]~\\_______|       |",
	"  |/ |   |-----------I_____I [][] []  D   |=======|__",
	"__/ =| o |=-~~\\  /~~\\  /~~\\  /~~\\ ____Y___________|__",
	" |/-=|___|=O=====O=====O=====O   |_____/~\\___/",
	"  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/",
}

local w, h = term.getSize()
local frames = math.max(8, w + #train[1])
for step = 1, frames do
	local x = w - step
	term.setCursorPos(1, 1)
	for i, line in ipairs(train) do
		if i + 2 <= h then
			term.setCursorPos(1, i + 2)
			term.clearLine()
			if x >= 1 then
				term.write(line:sub(1, math.max(0, w - x + 1)))
			else
				term.write(line:sub(2 - x))
			end
		end
	end
	sleep(0.05)
end
term.clear()
