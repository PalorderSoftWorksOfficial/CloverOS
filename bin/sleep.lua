-- sleep: pause for a number of seconds
local args = { ... }
local seconds = tonumber(args[1])
if not seconds or seconds < 0 then
	print("usage: sleep <seconds>")
	return 1
end
sleep(seconds)
