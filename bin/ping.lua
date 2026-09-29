-- ping: round trip times to a host, using CC:Tweaked's ping().
--
-- ping is a global function on CC:Tweaked, not a table, and it raises on an
-- unresolvable host rather than returning nil.
local host = ...
if not host or host == "" then
	print("usage: ping <host> [count]")
	return
end

local countArg = select(2, ...)
local count = tonumber(countArg) or 4
if type(ping) ~= "function" then
	print("ping: this computer cannot resolve hostnames")
	return
end

local ok, times = pcall(ping, host, count)
if not ok or type(times) ~= "table" then
	print("ping: " .. tostring(host) .. " is unreachable")
	return
end

if #times == 0 then
	print("ping: no replies from " .. host)
	return
end

local total, best, worst = 0, times[1], times[1]
for i, ms in ipairs(times) do
	print(string.format("reply from %s: %d ms", host, ms))
	total = total + ms
	if ms < best then
		best = ms
	end
	if ms > worst then
		worst = ms
	end
end

print(string.format("--- %s ping statistics ---", host))
print(string.format("%d sent, %d received, %.1f%% loss", count, #times, (count - #times) / count * 100))
print(string.format("min/avg/max = %d/%.1f/%d ms", best, total / #times, worst))
