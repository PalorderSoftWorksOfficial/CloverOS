-- CloverOS /bin/sh — Bourne-like shell using the kernel API
local M = {}

function M.start(ctx)
  local root = ctx.root
  local env = {
    kernel = ctx.kernel,
    fs = ctx.fs,
    process = ctx.process,
    term = ctx.term,
    path = ctx.path,
    colors = ctx.colors,
    textutils = ctx.textutils,
    trim = ctx.kernel.text.trim,
    readInput = ctx.readInput,
    Terminal = ctx.Terminal,
    ROOT = root,
    users = ctx.accounts.users,
    groups = ctx.accounts.groups,
    loadUsers = ctx.accounts.load,
    saveUsers = ctx.accounts.saveUsers,
    saveGroups = ctx.accounts.saveGroups,
    ensureDirectory = ctx.accounts.ensureDirectory,
    APT_DIR = root .. "/etc/apt/packages",
    APT_INSTALLED_FILE = root .. "/etc/apt/installed",
    settingsLoaded = ctx.settingsLoaded,
    editionSettings = ctx.editionSettings,
    currentUser = ctx.currentUser,
    write = write,
    read = read,
    print = print,
    os = os,
    table = table,
    string = string,
    math = math,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    pcall = pcall,
    ipairs = ipairs,
    pairs = pairs,
    select = select,
  }

  setmetatable(env, { __index = _G })

  local bodyPath = fs.combine(root, "os/_sh_body.lua")
  local h = fs.open(bodyPath, "r")
  if not h then
    error("shell body missing: " .. bodyPath)
  end
  local src = h.readAll()
  h.close()
  local chunk, err = load(src, "@" .. bodyPath, "t", env)
  if not chunk then
    error("shell load failed: " .. tostring(err))
  end
  local ok, runErr = pcall(chunk)
  if not ok then
    error("shell init failed: " .. tostring(runErr))
  end

  env.autoRegisterCompletions()
  ctx.Terminal.clear()

  local motdPath = root .. "/etc/motd"
  if ctx.fs.exists(motdPath) then
    local h = ctx.fs.open(motdPath, "r")
    if h then
      while true do
        local line = h.readLine()
        if not line then
          break
        end
        ctx.Terminal.print(line)
      end
      h.close()
      ctx.Terminal.print("")
    end
  end

  env.shellEnv.USER = ctx.currentUser or "root"
  local u = env.users[env.shellEnv.USER]
  env.shellEnv.HOME = (u and u.home) or "/root"
  env.shellEnv.SHELL = "/bin/sh"
  env.shellEnv.HOSTNAME = ctx.kernel.system.hostname()
  env.shellEnv.MANPATH = root .. "/etc/man"
  env.shellEnv.PS1 = "%u@%h:%w$ "
  env.shellEnv.PATH = root .. "/bin:" .. root .. "/usr/bin:/bin:/usr/bin"
  ctx.process.setDir(env.shellEnv.HOME)
  env.shellEnv.PWD = ctx.process.dir()
  env.shellEnv["?"] = "0"
  env.loadShellProfiles()

  local history = {}

  while true do
    if env.isKernelShutdownOrReboot() then
      return
    end
    local line = env.readLine(env.formatPrompt(), history)
    local commandLine = line and line:match("^%s*(.-)%s*$") or ""
    if commandLine ~= "" then
      if history[#history] ~= commandLine then
        history[#history + 1] = commandLine
        env.commandHistory = history
      end
      local parts = env.tokenize(commandLine)
      local command = table.remove(parts, 1)
      while command and command:match("^[%w_]+=.*$") do
        local name, value = command:match("^([%w_]+)=(.*)$")
        if not name then
          break
        end
        env.shellEnv[name] = env.expandToken(value)
        command = table.remove(parts, 1)
      end
      for i = 1, #parts do
        parts[i] = env.expandToken(parts[i])
      end
      local commands = env.listCommands()
      local resolved = env.resolveAlias(command)
      if env.builtins[resolved] then
        local ok2, err2 = pcall(env.builtins[resolved], table.unpack(parts))
        env.shellEnv["?"] = ok2 and "0" or "1"
        if not ok2 then
          ctx.Terminal.print(tostring(err2))
        elseif resolved == "exit" then
          return
        end
      elseif commands[resolved] then
        local ok2, err2 = pcall(ctx.process.run, commands[resolved], table.unpack(parts))
        env.shellEnv["?"] = ok2 and "0" or "1"
        if not ok2 then
          ctx.Terminal.print(tostring(err2))
        end
      else
        ctx.Terminal.print(resolved .. ": command not found")
        env.shellEnv["?"] = "127"
      end
    end
  end
end

return M
