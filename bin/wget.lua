-- wget: fetch a URL over http.get and write it somewhere useful.
--
-- http.get is the only network path CC:Tweaked offers, and it returns
-- nil plus a reason rather than raising, so every failure is reported the
-- same way instead of crashing the shell.
local args = { ... }
if #args == 0 then
	print("usage: wget [-O <file>] [-q] <url>")
	return
end

local output, quiet, url
local i = 1
while i <= #args do
	local a = args[i]
	if a == "-O" or a == "-o" then
		output = args[i + 1]
		i = i + 1
	elseif a == "-q" then
		quiet = true
	elseif a == "-h" or a == "--help" then
		print("usage: wget [-O <file>] [-q] <url>")
		return
	else
		url = a
	end
	i = i + 1
end

if not url or url == "" then
	print("wget: no URL given")
	return
end
if type(http) ~= "table" or type(http.get) ~= "function" then
	print("wget: this computer cannot make HTTP requests")
	return
end

local handle, err = http.get(url)
if not handle then
	print("wget: " .. tostring(err or "request failed"))
	return
end

local body = handle.readAll()
if type(handle.close) == "function" then
	handle.close()
end
if type(body) ~= "string" then
	print("wget: empty response from " .. url)
	return
end

local defaultName = url:gsub("^https?://", ""):gsub("[^%w%._%-]", "_")
if defaultName == "" then
	defaultName = "index.html"
end
local target = output or defaultName

local handleOut, openErr = fs.open(target, "w")
if not handleOut then
	print("wget: cannot write " .. tostring(target) .. ": " .. tostring(openErr))
	return
end
handleOut.write(body)
handleOut.close()

if quiet then
	return
end

local size = #body
print(string.format("saved %d bytes to %s", size, target))
if type(handle.getResponseCode) == "function" then
	print("http " .. tostring(handle.getResponseCode()))
end
