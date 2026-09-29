-- CloverOS session launcher: builds the GUI stack and runs the desktop
-- session. Shared by CloverOS_OS.lua (graphical login) and the `cloveros`
-- shell command, so both paths start exactly the same desktop.
local M = {}

function M.new(deps)
	deps = deps or {}
	local self = {
		paths = deps.paths,
		users = deps.users,
		ui = deps.ui,
		packages = deps.packages,
		session = deps.session,
		kernel = deps.kernel or kernel,
	}

	local function load(name)
		local ok, module = pcall(dofile, self.paths:join("runtime", name .. ".lua"))
		if not ok or type(module) ~= "table" or type(module.new) ~= "function" then
			return nil, tostring(module)
		end
		return module
	end

	-- true when the graphical stack is installed and loadable
	function self:available()
		local guiModule, err = load("gui")
		if not guiModule then
			return false, err
		end
		local desktopModule, derr = load("desktop")
		if not desktopModule then
			return false, derr
		end
		return true
	end

	function self:buildStack()
		local guiModule, err = load("gui")
		if not guiModule then
			return nil, err
		end
		local desktopModule, derr = load("desktop")
		if not desktopModule then
			return nil, derr
		end
		local ok, gui = pcall(guiModule.new, {
			paths = self.paths,
			users = self.users,
			ui = self.ui,
			packages = self.packages,
			session = self.session,
			kernel = self.kernel,
		})
		if not ok then
			return nil, tostring(gui)
		end
		local dok, desktop = pcall(desktopModule.new, {
			paths = self.paths,
			users = self.users,
			ui = self.ui,
			packages = self.packages,
			session = self.session,
			kernel = self.kernel,
			gui = gui,
		})
		if not dok then
			return nil, tostring(desktop)
		end
		return { gui = gui, desktop = desktop }
	end

	function self:appList()
		local stack = self:buildStack()
		if not stack then
			return {}
		end
		return stack.desktop:appList()
	end

	-- Run the desktop until the user logs out or the session ends.
	-- Returns { ok = bool, logout = bool, error = string? }.
	function self:startDesktop(opts)
		opts = opts or {}
		local stack, err = self:buildStack()
		if not stack then
			return { ok = false, logout = false, error = err }
		end
		local ran, runErr = pcall(stack.desktop.run, stack.desktop)
		local logout = stack.desktop.requestLogout and true or false
		-- kernel.isShutdown is a plain function, not a method, and the
		-- kernel is absent in host-side tests: never call it blindly.
		local shuttingDown = false
		if not ran and self.kernel and type(self.kernel.isShutdown) == "function" then
			shuttingDown = self.kernel.isShutdown(runErr)
		end
		if not ran and not shuttingDown then
			return { ok = false, logout = logout, error = tostring(runErr) }
		end
		if self.kernel and type(self.kernel.info) == "function" then
			self.kernel.info("desktop session exited (logout=" .. tostring(logout) .. ")")
		end
		return { ok = true, logout = logout }
	end

	return self
end

return M
