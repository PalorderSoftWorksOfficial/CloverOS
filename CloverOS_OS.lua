-- CloverOS OS entry: wires runtime modules, runs first-run setup + login,
-- then starts the desktop (GUI) or the text shell with a text fallback.
-- Expects CLOVER_ROOT set and `kernel` loaded (boot/loader.lua).
local version = dofile(fs.combine(CLOVER_ROOT, "etc/version.lua"))

local paths = dofile(fs.combine(CLOVER_ROOT, "runtime/paths.lua")).new(CLOVER_ROOT)
_G.paths = paths

local function loadRuntime(name)
	local path = fs.combine(CLOVER_ROOT, "runtime/" .. name .. ".lua")
	local ok, result = pcall(dofile, path)
	if not ok or type(result) ~= "table" then
		printError("CloverOS: failed to load runtime/" .. name .. ".lua: " .. tostring(result))
		return nil
	end
	return result
end

local usersModule = loadRuntime("users")
local uiModule = loadRuntime("textui")
local packagesModule = loadRuntime("packages")
local shellModule = loadRuntime("shell")

if not (usersModule and uiModule and packagesModule and shellModule) then
	printError("CloverOS: runtime is incomplete; dropping to recovery shell")
	print("Type 'exit' to return to CraftOS.")
	while true do
		write("> ")
		local line = read()
		if line == "exit" then
			return
		end
		local fn, err = load(line, "=recovery", "t", _ENV)
		if fn then
			local ok, result = pcall(fn)
			if not ok then
				printError(result)
			end
		else
			printError(err)
		end
	end
end

local users = usersModule.new(paths)
local ui = uiModule.new(paths)
local packages = packagesModule.new(paths)

local function bootInfo(message)
	if kernel and kernel.info then
		kernel.info(message)
	end
end

local session = shellModule.new({
	paths = paths,
	users = users,
	ui = ui,
	packages = packages,
})

_G.CloverOS = {
	version = version.version(),
	paths = paths,
	users = users,
	ui = ui,
	packages = packages,
	session = session,
}

users:load()

local function firstRunSetup()
	if kernel and kernel.info then
		kernel.info("first-run setup: awaiting user creation")
	end
	ui:clear(colors.black, colors.white)
	ui:center(2, "CloverOS first-run setup", colors.lime)
	print()
	print("No user account exists yet. Create one now.")
	print()
	local name
	while true do
		write("username: ")
		name = read()
		if name and name ~= "" and users:createUser(name, "changeme") then
			break
		end
		print("invalid or duplicate username; try again")
	end
	-- set a real password for the new account
	while true do
		write("password: ")
		local pass = read("*")
		write("confirm:  ")
		local confirm = read("*")
		if pass == confirm and #pass > 0 then
			users:setPassword(name, pass)
			break
		end
		print("passwords do not match or are empty; try again")
	end
	-- optional root password
	write("set a root password too? [y/N] ")
	local ans = read()
	if ans and ans:lower():sub(1, 1) == "y" then
		write("root password: ")
		local rpass = read("*")
		if not users:exists("root") then
			users:createUser("root", rpass)
		else
			users:setPassword("root", rpass)
		end
	end
	users:save()
	print()
	print("user '" .. name .. "' created. Starting login.")
	sleep(1)
end

local function loginScreen()
	if kernel and kernel.info then
		kernel.info("login prompt ready")
	end
	while true do
		ui:clear(colors.black, colors.white)
		ui:center(2, "CloverOS " .. version.version(), colors.green)
		ui:center(4, "login (ctrl+T to shut down)", colors.lightGray)
		write("login: ")
		local name = read(nil, nil, function(line)
			local names = users:list()
			local out = {}
			for _, n in ipairs(names) do
				if n:sub(1, #line) == line then
					out[#out + 1] = n:sub(#line + 1)
				end
			end
			return out
		end)
		if not name or name == "" then
			return nil
		end
		if not users:exists(name) then
			print("unknown user")
			sleep(1)
		else
			write("password: ")
			local pass = read("*")
			if users:authenticate(name, pass or "") then
				users:login(name)
				bootInfo("session started for " .. name)
				return name
			end
			print("wrong password")
			sleep(1)
		end
	end
end


-- first-run setup before login
if not users:hasAnyUser() then
	bootInfo("no users found; entering first-run setup")
	firstRunSetup()
end

-- session loop: login -> desktop (or text shell) -> logout -> login
while true do
		local user = loginScreen()
	if not user then
		-- ctrl+T at the login prompt shuts the system down
		print("shutting down...")
		sleep(0.5)
		if kernel and kernel.shutdown then
			kernel:shutdown()
		else
			os.shutdown()
		end
		return
	end

	-- GUI preference is a persisted setting; text mode stays available.
	-- session = "gnome" is the default desktop, "text" forces the shell.
	local cfg = kernel.config.loadOrCreate("settings", { gui = true, session = "gnome" })
	local wantDesktop = cfg.gui and cfg.session ~= "text"

	local logoutRequested = false

	if wantDesktop then
		-- the same launcher the `cloveros` shell command uses
		local launcherOk, launcher = pcall(function()
			local launcherModule = dofile(fs.combine(CLOVER_ROOT, "runtime/launcher.lua"))
			return launcherModule.new({
				paths = paths,
				users = users,
				ui = ui,
				packages = packages,
				session = session,
				kernel = kernel,
			})
		end)

		if launcherOk and launcher then
			local result = launcher:startDesktop()
			if not result.ok then
				printError("CloverOS desktop failed: " .. tostring(result.error))
				print("falling back to text mode for this session")
			else
				-- normal desktop exit or logout both return to the login screen
				logoutRequested = true
			end
		else
			printError("CloverOS GUI unavailable: " .. tostring(launcher))
			print("Continuing in text mode.")
		end
	end

	if not logoutRequested then
		-- text-mode shell for the current user (also the GUI failure path)
		bootInfo("text session started for " .. tostring(users:currentName()))
		session.running = true
		session.logoutRequested = nil
		local ran, err = pcall(session.run, session)
		if not ran then
			printError("CloverOS shell failed: " .. tostring(err))
			print("returning to login")
		end
	end

	users:logout()
	pcall(function() users:save() end)
end
