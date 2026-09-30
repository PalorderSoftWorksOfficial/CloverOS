-- ssh: run a command on another CloverOS computer over rednet.
--
--   ssh <computer id> <command>
--
-- Prompts for the remote user's password, opens an authenticated session,
-- streams the output, closes. The server half lives in runtime/ssh.lua and
-- starts with `systemctl start sshd` (or runs at boot when enabled).
local root = CLOVER_ROOT or fs.getDir(shell.getRunningProgram())
local okModule, ssh = pcall(function()
	return dofile(fs.combine(root, "runtime/ssh.lua"))
end)

if not okModule or type(ssh) ~= "table" or type(ssh.run) ~= "function" then
	print("ssh: runtime/ssh.lua unavailable")
	return
end

local args = { ... }
local host = args[1]
local command = nil
if #args > 1 then
	command = table.concat(args, " ", 2, #args)
end

if not host or not command then
	print("usage: ssh <computer id> <command>")
	return
end

local ok, err = ssh.run({
	user = _G.CLOVER_USER,
	host = host,
	command = command,
}, host, command, function(line)
	print(line)
end)

if not ok then
	print("ssh: " .. tostring(err))
end
