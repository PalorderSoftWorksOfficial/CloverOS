-- CloverOS main interface and shell
---@diagnostic disable: undefined-global
-- luacheck: globals peripheral fs shell term colors textutils read write os

local monitor = peripheral.find("monitor")
local fs = fs
local shell = shell
local term = term
local colors = colors
local textutils = textutils

local function mirrorWrite(text)
  write(text)
  if monitor then
    monitor.write(text)
  end
end

local function mirrorClear()
  term.clear()
  term.setCursorPos(1, 1)
  if monitor then
    monitor.clear()
    monitor.setCursorPos(1, 1)
  end
end

local function mirrorSetCursor(x, y)
  term.setCursorPos(x, y)
  if monitor then
    monitor.setCursorPos(x, y)
  end
end

local Terminal = {}

function Terminal.clear()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  mirrorClear()
end

function Terminal.write(text)
  mirrorWrite(text)
end

function Terminal.print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  mirrorWrite(table.concat(parts, "\t"))
  mirrorWrite("\n")
end

function Terminal.read(hidden)
  if hidden then
    return read("*")
  end
  return read()
end

function Terminal.setCursor(x, y)
  mirrorSetCursor(x, y)
end

function Terminal.getSize()
  return term.getSize()
end

function Terminal.centerText(y, text, fg, bg)
  if fg then term.setTextColor(fg) end
  if bg then term.setBackgroundColor(bg) end
  local w = select(1, Terminal.getSize())
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  mirrorSetCursor(x, y)
  mirrorWrite(text)
  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)
end

local function findCloverRoot()
  if fs.exists("/CloverOS_OS.lua") and fs.exists("/CloverOS_API.lua") then
    return "/"
  end
  for i = 0, 99 do
    local root = "/disk" .. (i == 0 and "" or i)
    if fs.exists(root .. "/CloverOS_OS.lua") and fs.exists(root .. "/CloverOS_API.lua") then
      return root
    end
  end
  return "/"
end

local ROOT = findCloverRoot()
local AUTH_FILE = ROOT .. "/auth"

local function readInput(prompt, hidden)
  if prompt then
    Terminal.write(prompt)
  end
  local value = Terminal.read(hidden) or ""
  Terminal.print("")
  return value
end

local function loadAuth()
  if not fs.exists(AUTH_FILE) then
    return nil
  end

  local handle = fs.open(AUTH_FILE, "r")
  if not handle then
    return nil
  end

  local ok, auth = pcall(textutils.unserialize, handle.readAll())
  handle.close()

  if ok and type(auth) == "table" and auth.user and auth.pass then
    return auth
  end

  return nil
end

local function saveAuth(username, password)
  local handle = fs.open(AUTH_FILE, "w")
  if not handle then
    return false
  end
  handle.write(textutils.serialize({ user = tostring(username), pass = tostring(password) }))
  handle.close()
  return true
end

local function login()
  local auth = loadAuth()
  if not auth then
    Terminal.clear()
    Terminal.centerText(2, "CloverOS Setup", colors.white, colors.blue)
    Terminal.print("")
    local username = readInput("New username: ")
    local password = readInput("New password: ", true)
    saveAuth(username, password)
    Terminal.print("Account created. Starting CloverOS...")
    os.sleep(1.2)
    return
  end

  while true do
    Terminal.clear()
    Terminal.centerText(2, "CloverOS Login", colors.white, colors.blue)
    Terminal.print("")
    local username = readInput("Username: ")
    local password = readInput("Password: ", true)

    if username == auth.user and password == auth.pass then
      Terminal.print("Login successful.")
      os.sleep(1)
      return
    end

    Terminal.print("Invalid credentials. Try again.")
    os.sleep(1.2)
  end
end

local function simulateLoading()
  Terminal.clear()
  local logLines = {
    "[BOOT] Initializing CloverOS...",
    "[BOOT] Detecting hardware...",
    "[BOOT] Loading modules...",
    "[BOOT] Mounting filesystems...",
    "[BOOT] Starting core services...",
    "[OK] CloverOS ready."
  }

  local w, _ = Terminal.getSize()
  for i, message in ipairs(logLines) do
    Terminal.centerText(4 + i, message)
    os.sleep(0.25)
  end
  os.sleep(0.5)
end

local function listCommands()
  local commands = {}
  local paths = {
    ROOT .. "/bin",
    "/bin",
    "/rom/programs"
  }
  for _, path in ipairs(paths) do
    if fs.exists(path) and fs.isDir(path) then
      for _, file in ipairs(fs.list(path)) do
        local full = fs.combine(path, file)
        if fs.exists(full) and not fs.isDir(full) then
          local isExecutable = file:match("%.[lL][uU][aA]$") or file:match("%.[eE][xX][eE]$") or file:match("%.[dD][lL][lL]$") or not file:match("%.")
          if isExecutable then
            local name = file:gsub("%..+$", "")
          commands[name] = full
          end
        end
      end
    end
  end
  return commands
end

local function shellBuiltinHelp()
  Terminal.print("Available commands:")
  Terminal.print("  help")
  Terminal.print("  exit")
  Terminal.print("  shutdown")
  Terminal.print("  installer")
  Terminal.print("  run <command>")
  local commands = listCommands()
  for name in pairs(commands) do
    Terminal.print("  " .. name)
  end
end

local function shellBuiltinSettings()
  Terminal.print("CloverOS v1.0.0")
  Terminal.print("Author: CloverOS Team")
end

local function runShell()
  Terminal.clear()
  Terminal.print("Welcome to CloverOS Shell. Type help for available commands.")

  while true do
    local line = readInput("root@CloverOS:~$ ")
    local commandLine = line and line:match("^%s*(.-)%s*$") or ""
    if commandLine == "" then
      goto continue
    end

    local parts = {}
    for word in commandLine:gmatch("%S+") do
      table.insert(parts, word)
    end

    local command = table.remove(parts, 1)
    local commands = listCommands()
    local builtins = {
      help = shellBuiltinHelp,
      exit = function() return true end,
      shutdown = function() os.shutdown() end,
      installer = function()
        if _G.CloverOS and type(_G.CloverOS.runInstaller) == "function" then
          _G.CloverOS.runInstaller()
        else
          shell.run("wget", "run", "https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua")
        end
      end,
      run = function(...)
        if #parts == 0 then
          Terminal.print("Usage: run <command>")
          return
        end
        local target = table.remove(parts, 1)
        local targetPath = commands[target]
        if not targetPath then
          Terminal.print("Unknown program: " .. target)
          return
        end
        shell.run(targetPath, table.unpack(parts))
      end
    }

    if builtins[command] then
      local ok, err = pcall(builtins[command], table.unpack(parts))
      if not ok then
        Terminal.print("Error: " .. tostring(err))
      elseif builtins[command] == builtins.exit then
        return
      end
    elseif commands[command] then
      local ok, err = pcall(shell.run, commands[command], table.unpack(parts))
      if not ok then
        Terminal.print("Error: " .. tostring(err))
      end
    else
      Terminal.print("Command not found: " .. tostring(command))
    end

    ::continue::
  end
end

local function getCustomApps()
  local appList = {}
  local appDirs = { ROOT .. "/apps", "/apps" }
  for _, dir in ipairs(appDirs) do
    if fs.exists(dir) and fs.isDir(dir) then
      for _, file in ipairs(fs.list(dir)) do
        if file:match("%.[lL][uU][aA]$") or file:match("%.[eE][xX][eE]$") or file:match("%.[dD][lL][lL]$") then
          local filePath = fs.combine(dir, file)
          local appName = file:gsub("%..+$", "")
          table.insert(appList, {
            name = appName,
            run = function()
              Terminal.clear()
              local ok, err = pcall(function()
                shell.run(filePath)
              end)
              if not ok then
                Terminal.print("App crash: " .. tostring(err))
                os.sleep(1.5)
              end
            end
          })
        end
      end
    end
  end
  return appList
end

local function fileManager()
  local currentDir = ROOT
  if currentDir == "/" then
    currentDir = "/"
  end

  while true do
    Terminal.clear()
    Terminal.print("File Manager")
    Terminal.print("Current directory: " .. currentDir)
    Terminal.print("")

    local entries = fs.list(currentDir)
    for index, name in ipairs(entries) do
      local path = fs.combine(currentDir, name)
      local suffix = fs.isDir(path) and "/" or ""
      Terminal.print(string.format("%2d) %s%s", index, name, suffix))
    end
    Terminal.print("")
    Terminal.print("Enter a number to browse, 'back' to go up, or 'exit' to return.")
    local selection = readInput("> ")
    if not selection then
      return
    end
    selection = selection:match("^%s*(.-)%s*$")
    if selection == "exit" then
      return
    elseif selection == "back" then
      if currentDir ~= ROOT and currentDir ~= "/" then
        currentDir = fs.getDir(currentDir)
      end
    else
      local index = tonumber(selection)
      if index and entries[index] then
        local chosen = fs.combine(currentDir, entries[index])
        if fs.isDir(chosen) then
          currentDir = chosen
        else
          local handle = fs.open(chosen, "r")
          if not handle then
            Terminal.print("Unable to open file.")
            os.sleep(1.2)
          else
            Terminal.clear()
            Terminal.print("Viewing: " .. chosen)
            Terminal.print("")
            local count = 0
            while true do
              local line = handle.readLine()
              if not line or count >= 20 then
                break
              end
              Terminal.print(line)
              count = count + 1
            end
            handle.close()
            Terminal.print("")
            Terminal.print("Press Enter to continue.")
            readInput("")
          end
        end
      end
    end
  end
end

local function desktop()
  local options = {
    { name = "Terminal", run = runShell },
    { name = "File Manager", run = fileManager },
    { name = "About", run = function()
        Terminal.clear()
        Terminal.print("CloverOS v1.0.0")
        Terminal.print("Author: CloverOS Team")
        Terminal.print("")
        Terminal.print("Press Enter to return.")
        readInput("")
      end },
    { name = "Shutdown", run = function()
        Terminal.print("Shutting down...")
        os.sleep(1)
        os.shutdown()
      end }
  }

  while true do
    Terminal.clear()
    Terminal.print("=== CloverOS Desktop ===")
    Terminal.print("")
    local allOptions = {}
    for index, option in ipairs(options) do
      Terminal.print(string.format("%2d) %s", index, option.name))
      table.insert(allOptions, option)
    end
    for _, app in ipairs(getCustomApps()) do
      table.insert(allOptions, app)
    end
    Terminal.print("")
    Terminal.print("Select a number or app name. Type 'shutdown' to power off.")

    local choice = readInput("Choice: ")
    local key = choice and choice:match("^%s*(.-)%s*$") or ""
    if key == "" then
      goto continue
    end
    key = key:lower()
    if key == "shutdown" or key == "poweroff" then
      os.shutdown()
      return
    end

    local index = tonumber(key)
    local activated = false
    if index and allOptions[index] then
      local ok, err = pcall(allOptions[index].run)
      if not ok then
        Terminal.print("Execution error: " .. tostring(err))
        os.sleep(1.5)
      end
      activated = true
    else
      for _, option in ipairs(allOptions) do
        if option.name:lower() == key then
          local ok, err = pcall(option.run)
          if not ok then
            Terminal.print("Execution error: " .. tostring(err))
            os.sleep(1.5)
          end
          activated = true
          break
        end
      end
    end

    if not activated then
      Terminal.print("No matching app found.")
      os.sleep(1.2)
    end

    ::continue::
  end
end

simulateLoading()
login()
desktop()
term.setCursorBlink(true)

