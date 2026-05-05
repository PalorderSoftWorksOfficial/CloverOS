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
local function DISK_ROOT()
  local function isCloverRoot(root)
    return fs.exists(root .. "/CloverOS_API.lua")
        and fs.exists(root .. "/boot/kernel.lua")
  end

  if isCloverRoot("") or isCloverRoot("/") then
    return ""
  end
  for i = 1, 99 do
    local root = "/disk" .. (i == 1 and "" or i)
    if isCloverRoot(root) then
      return root
    end
  end

  return nil
end
local completionInfo = {}
local aliases = {}
local shellEnv = {}

local function listCommands()
  local commands = {}
  local paths = {}

  if ROOT and ROOT ~= "" then
    paths[#paths + 1] = ROOT .. "/bin"
  end

  paths[#paths + 1] = "/bin"

  for _, path in ipairs(paths) do
    if fs.exists(path) and fs.isDir(path) then
      for _, file in ipairs(fs.list(path)) do
        local full = fs.combine(path, file)
        if fs.exists(full) and not fs.isDir(full) then
          local isExecutable = file:match("%.[lL][uU][aA]$")
              or file:match("%.[eE][xX][eE]$")
              or file:match("%.[dD][lL][lL]$")
              or not file:match("%.")

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

local function tokenize(line)
  local words = {}
  local word = {}
  local quoted = false
  local singleQuoted = false
  local escape = false

  for i = 1, #line do
    local c = line:sub(i, i)

    if escape then
      word[#word + 1] = c
      escape = false
    elseif c == "\\" and not singleQuoted then
      escape = true
    elseif c == '"' and not singleQuoted then
      quoted = not quoted
    elseif c == "'" and not quoted then
      singleQuoted = not singleQuoted
    elseif not quoted and c:match("%s") then
      if #word > 0 then
        words[#words + 1] = table.concat(word)
        word = {}
      end
    else
      word[#word + 1] = c
    end
  end

  if #word > 0 then
    words[#words + 1] = table.concat(word)
  end

  return words
end

-- Expand environment variables like $VAR and ~
local function expandToken(tok)
  if not tok or tok == "" then return tok end
  -- Tilde expansion at start
  if tok:sub(1, 1) == "~" then
    local home = shellEnv.HOME or ROOT or "/"
    if tok == "~" then
      tok = home
    elseif tok:sub(2, 2) == '/' then
      tok = home .. tok:sub(2)
    end
  end

  -- Variable expansion: ${VAR} or $VAR
  local function repl(var)
    local name = var:match("^%${(.-)}$") or var:match("^%$(.-)$")
    if not name then return var end
    return tostring(shellEnv[name] or "")
  end

  -- Replace ${VAR}
  tok = tok:gsub("%${(.-)}", function(n) return tostring(shellEnv[n] or "") end)
  -- Replace $VAR (simple)
  tok = tok:gsub("%$(%w+)", function(n) return tostring(shellEnv[n] or "") end)

  return tok
end

local function startsWith(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function resolveAlias(name)
  return aliases[name] or name
end

local function registerCompletion(command, fn)
  completionInfo[command] = fn
end

local function completePrograms(prefix)
  local commands = listCommands()
  local results = {}
  local seen = {}

  for aliasName in pairs(aliases) do
    if startsWith(aliasName, prefix) then
      local suffix = aliasName:sub(#prefix + 1)
      if not seen[suffix] then
        seen[suffix] = true
        results[#results + 1] = suffix
      end
    end
  end

  for name in pairs(commands) do
    if startsWith(name, prefix) then
      local suffix = name:sub(#prefix + 1)
      if not seen[suffix] then
        seen[suffix] = true
        results[#results + 1] = suffix
      end
    end
  end

  table.sort(results)
  return results
end

local function completeLine(line)
  if not line or line == "" then
    return completePrograms("")
  end

  local words = tokenize(line)
  local endsWithSpace = line:sub(-1) == " "
  local index = #words

  if endsWithSpace then
    index = index + 1
  end

  if index <= 1 then
    local part = words[1] or ""
    local resolved = resolveAlias(part)

    if completionInfo[resolved] then
      return { " " }
    end

    local results = completePrograms(part)
    for i = 1, #results do
      local candidate = part .. results[i]
      local candidateResolved = resolveAlias(candidate)
      if completionInfo[candidateResolved] then
        results[i] = results[i] .. " "
      end
    end
    return results
  end

  local commandName = resolveAlias(words[1] or "")
  local fn = completionInfo[commandName]
  if fn then
    local current = words[index] or ""
    local previous = {}
    for i = 1, index - 1 do
      previous[i] = words[i]
    end
    return fn(index - 1, current, previous)
  end

  return nil
end

local function readLine(prompt, history)
  if type(read) == "function" then
    write(prompt)
    return read(nil, history, completeLine)
  end

  return readInput(prompt)
end

local function shellBuiltinHelp()
  Terminal.print("Available commands:")
  Terminal.print("  help")
  Terminal.print("  exit")
  Terminal.print("  shutdown")
  Terminal.print("  installer")
  Terminal.print("  run <command>")

  local commands = listCommands()
  local names = {}
  for name in pairs(commands) do
    names[#names + 1] = name
  end
  table.sort(names)

  for _, name in ipairs(names) do
    Terminal.print("  " .. name)
  end
end

local function shellBuiltinSettings()
  Terminal.print("CloverOS v1.0.0")
  Terminal.print("Author: CloverOS Team")
end

registerCompletion("help", function()
  local items = { "exit", "shutdown", "installer", "run" }
  local commands = listCommands()
  for name in pairs(commands) do
    items[#items + 1] = name
  end
  table.sort(items)
  return items
end)

registerCompletion("run", function(index, current)
  if index ~= 1 then
    return nil
  end

  local commands = listCommands()
  local items = {}
  local seen = {}

  for name in pairs(commands) do
    if startsWith(name, current) and not seen[name] then
      seen[name] = true
      items[#items + 1] = name:sub(#current + 1)
    end
  end

  for aliasName in pairs(aliases) do
    if startsWith(aliasName, current) and not seen[aliasName] then
      seen[aliasName] = true
      items[#items + 1] = aliasName:sub(#current + 1)
    end
  end

  table.sort(items)
  return items
end)
local commandHistory = {}
local shellEnv = {}
local function shellUsage(cmd, usage)
  Terminal.print("Usage: " .. cmd .. (usage and (" " .. usage) or ""))
end

local function resolvePath(path)
  if not path or path == "" then
    return shell.dir()
  end
  return shell.resolve(path)
end

local function printFile(path)
  local h = fs.open(path, "r")
  if not h then
    Terminal.print("Unable to open file: " .. tostring(path))
    return
  end

  while true do
    local line = h.readLine()
    if line == nil then break end
    Terminal.print(line)
  end

  h.close()
end

local function countLines(path)
  local h = fs.open(path, "r")
  if not h then
    return nil
  end

  local n = 0
  while h.readLine() do
    n = n + 1
  end
  h.close()
  return n
end

local function tailFile(path, n)
  n = tonumber(n) or 10
  local h = fs.open(path, "r")
  if not h then
    Terminal.print("Unable to open file: " .. tostring(path))
    return
  end

  local lines = {}
  while true do
    local line = h.readLine()
    if line == nil then break end
    lines[#lines + 1] = line
  end
  h.close()

  local start = math.max(1, #lines - n + 1)
  for i = start, #lines do
    Terminal.print(lines[i])
  end
end

local builtins = {
  help = function()
    Terminal.print("Available commands:")
    Terminal.print("  help")
    Terminal.print("  man <command>")
    Terminal.print("  exit")
    Terminal.print("  shutdown")
    Terminal.print("  reboot")
    Terminal.print("  installer")
    Terminal.print("  run <command>")
    Terminal.print("  cd <dir>")
    Terminal.print("  pwd")
    Terminal.print("  clear")
    Terminal.print("  echo <text>")
    Terminal.print("  sleep <seconds>")
    Terminal.print("  history")
    Terminal.print("  alias [name value]")
    Terminal.print("  unalias <name>")
    Terminal.print("  which <command>")
    Terminal.print("  touch <file>")
    Terminal.print("  cat <file>")
    Terminal.print("  head <file> [n]")
    Terminal.print("  tail <file> [n]")
    Terminal.print("  mkdir <dir>")
    Terminal.print("  rmdir <dir>")
    Terminal.print("  rm <path>")
    Terminal.print("  cp <src> <dst>")
    Terminal.print("  mv <src> <dst>")
    Terminal.print("  stat <path>")
    Terminal.print("  date")
    Terminal.print("  time")
    Terminal.print("  whoami")
    Terminal.print("  hostname")

    local commands = listCommands()
    local names = {}
    for name in pairs(commands) do
      names[#names + 1] = name
    end
    table.sort(names)

    Terminal.print("")
    Terminal.print("Programs:")
    for _, name in ipairs(names) do
      Terminal.print("  " .. name)
    end
  end,

  exit = function()
    return true
  end,

  shutdown = function()
    os.shutdown()
  end,

  reboot = function()
    os.reboot()
  end,

  installer = function()
    if _G.CloverOS and type(_G.CloverOS.runInstaller) == "function" then
      _G.CloverOS.runInstaller()
    else
      shell.run("wget", "run", "https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua")
    end
  end,

  run = function(...)
    local args = { ... }
    if #args == 0 then
      Terminal.print("Usage: run <command>")
      return
    end

    local target = table.remove(args, 1)
    local commands = listCommands()
    local targetPath = commands[resolveAlias(target)]

    if not targetPath then
      Terminal.print("No such program")
      return
    end

    shell.run(targetPath, table.unpack(args))
  end,

  cd = function(path)
    if not path or path == "" then
      shell.setDir(ROOT)
      return
    end

    local target = resolvePath(path)
    if fs.isDir(target) then
      shell.setDir(target)
      -- keep shellEnv in sync so child processes see correct PWD
      shellEnv.PWD = shell.dir()
    else
      Terminal.print("Not a directory: " .. tostring(path))
    end
  end,

  pwd = function()
    Terminal.print(shell.dir())
  end,

  clear = function()
    Terminal.clear()
  end,

  echo = function(...)
    Terminal.print(table.concat({ ... }, " "))
  end,

  sleep = function(sec)
    sec = tonumber(sec) or 0
    if sec > 0 then
      os.sleep(sec)
    end
  end,

  history = function()
    for i, line in ipairs(commandHistory) do
      Terminal.print(string.format("%4d  %s", i, line))
    end
  end,

  alias = function(name, ...)
    if not name or name == "" then
      local keys = {}
      for k in pairs(aliases) do
        keys[#keys + 1] = k
      end
      table.sort(keys)
      for _, k in ipairs(keys) do
        Terminal.print(k .. "=" .. aliases[k])
      end
      return
    end

    local value = table.concat({ ... }, " ")
    if value == "" then
      Terminal.print("Usage: alias <name> <command>")
      return
    end

    aliases[name] = value
  end,

  unalias = function(name)
    if not name or name == "" then
      Terminal.print("Usage: unalias <name>")
      return
    end
    aliases[name] = nil
  end,

  which = function(cmd)
    if not cmd or cmd == "" then
      Terminal.print("Usage: which <command>")
      return
    end
    local resolved = resolveAlias(cmd)
    if builtins[resolved] then
      Terminal.print(resolved .. " is a builtin")
      return
    end

    local commands = listCommands()
    if commands[resolved] then
      Terminal.print(commands[resolved])
      return
    end

    -- search PATH
    local pathEnv = shellEnv.PATH or shell.path and shell.path() or "/bin"
    for p in pathEnv:gmatch("[^:]+") do
      local candidate = fs.combine(p, resolved)
      if fs.exists(candidate) and not fs.isDir(candidate) then
        Terminal.print(candidate)
        return
      end
    end

    Terminal.print("Not found")
  end,

  export = function(name, value)
    if not name or name == "" then
      -- print all
      for k, v in pairs(shellEnv) do
        Terminal.print(k .. "=" .. tostring(v))
      end
      return
    end
    shellEnv[name] = tostring(value or "")
  end,

  man = function(cmd)
    if not cmd or cmd == "" then
      Terminal.print("Usage: man <command>")
      return
    end
    -- check builtin help usage and command metadata
    if builtins[cmd] and debug and type(builtins[cmd]) == "function" then
      Terminal.print("No manual entry for builtin: " .. cmd)
      return
    end
    local commands = listCommands()
    local path = commands[cmd]
    if not path then
      Terminal.print("No manual entry for: " .. cmd)
      return
    end
    -- try to read header comments as manual
    local header = readCommandHeader(path, 200)
    if header and #header > 0 then
      for _, line in ipairs(header) do
        Terminal.print(line)
      end
      return
    end
    Terminal.print("No manual entry for: " .. cmd)
  end,

  touch = function(path)
    if not path or path == "" then
      Terminal.print("Usage: touch <file>")
      return
    end

    local target = resolvePath(path)
    if fs.exists(target) then
      return
    end

    local h = fs.open(target, "w")
    if h then
      h.close()
    end
  end,

  cat = function(...)
    local args = { ... }
    if #args == 0 then
      Terminal.print("Usage: cat <file> [file...]")
      return
    end

    for _, p in ipairs(args) do
      local target = resolvePath(p)
      if not fs.exists(target) then
        Terminal.print("File not found: " .. tostring(p))
      elseif fs.isDir(target) then
        Terminal.print("Is a directory: " .. tostring(p))
      else
        printFile(target)
      end
    end
  end,

  head = function(path, n)
    if not path or path == "" then
      Terminal.print("Usage: head <file> [n]")
      return
    end

    local target = resolvePath(path)
    local count = tonumber(n) or 10
    local h = fs.open(target, "r")
    if not h then
      Terminal.print("Unable to open file: " .. tostring(path))
      return
    end

    local i = 0
    while i < count do
      local line = h.readLine()
      if not line then break end
      Terminal.print(line)
      i = i + 1
    end
    h.close()
  end,

  tail = function(path, n)
    if not path or path == "" then
      Terminal.print("Usage: tail <file> [n]")
      return
    end

    local target = resolvePath(path)
    tailFile(target, n)
  end,

  mkdir = function(path)
    if not path or path == "" then
      Terminal.print("Usage: mkdir <dir>")
      return
    end

    local target = resolvePath(path)
    if fs.exists(target) then
      Terminal.print("Path already exists: " .. tostring(path))
      return
    end

    fs.makeDir(target)
  end,

  rmdir = function(path)
    if not path or path == "" then
      Terminal.print("Usage: rmdir <dir>")
      return
    end

    local target = resolvePath(path)
    if not fs.exists(target) then
      Terminal.print("Not found: " .. tostring(path))
      return
    end

    if not fs.isDir(target) then
      Terminal.print("Not a directory: " .. tostring(path))
      return
    end

    fs.delete(target)
  end,

  rm = function(path)
    if not path or path == "" then
      Terminal.print("Usage: rm <path>")
      return
    end

    local target = resolvePath(path)
    if not fs.exists(target) then
      Terminal.print("Not found: " .. tostring(path))
      return
    end

    fs.delete(target)
  end,

  cp = function(src, dst)
    if not src or not dst then
      Terminal.print("Usage: cp <src> <dst>")
      return
    end

    local a = resolvePath(src)
    local b = resolvePath(dst)
    if not fs.exists(a) then
      Terminal.print("Source not found: " .. tostring(src))
      return
    end

    fs.copy(a, b)
  end,

  mv = function(src, dst)
    if not src or not dst then
      Terminal.print("Usage: mv <src> <dst>")
      return
    end

    local a = resolvePath(src)
    local b = resolvePath(dst)
    if not fs.exists(a) then
      Terminal.print("Source not found: " .. tostring(src))
      return
    end

    fs.move(a, b)
  end,

  stat = function(path)
    if not path or path == "" then
      Terminal.print("Usage: stat <path>")
      return
    end

    local target = resolvePath(path)
    if not fs.exists(target) then
      Terminal.print("Not found: " .. tostring(path))
      return
    end

    Terminal.print("Path: " .. target)
    Terminal.print("Type: " .. (fs.isDir(target) and "directory" or "file"))
    if not fs.isDir(target) then
      Terminal.print("Size: " .. tostring(fs.getSize(target)))
    end
  end,

  date = function()
    Terminal.print(textutils.formatTime(os.time(), true))
  end,

  time = function()
    Terminal.print(textutils.formatTime(os.time(), true))
  end,

  whoami = function()
    Terminal.print("root")
  end,

  hostname = function()
    Terminal.print("CloverOS")
  end,
}
local commandMeta = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function startsWith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

local function readCommandHeader(path, maxLines)
  local f = fs.open(path, "r")
  if not f then
    return nil
  end

  local lines = {}
  for _ = 1, maxLines do
    local line = f.readLine()
    if not line then break end
    lines[#lines + 1] = line
    if not startsWith(trim(line), "--") then
      break
    end
  end

  f.close()
  return lines
end

local function parseCommandMeta(path)
  local header = readCommandHeader(path, 40)
  if not header then
    return nil
  end

  local meta = {
    usage = nil,
    completes = {},
  }

  for _, line in ipairs(header) do
    local usage = line:match("^%-%-%s*@usage%s+(.+)$")
    if usage then
      meta.usage = trim(usage)
    end

    local index, kind, extra = line:match("^%-%-%s*@complete%s+(%d+)%s+(%S+)%s*(.*)$")
    if index and kind then
      meta.completes[tonumber(index)] = {
        kind = kind,
        extra = trim(extra or ""),
      }
    end
  end

  return meta
end

local function scanCommandMetadata()
  local commands = listCommands()
  for name, path in pairs(commands) do
    local meta = parseCommandMeta(path)
    if meta then
      commandMeta[name] = meta
    end
  end
end

local function completeFiles(prefix)
  local results = {}
  local seen = {}

  local paths = { "/bin" }
  local root = DISK_ROOT()
  if root then
    paths[#paths + 1] = root .. "/bin"
  end

  for _, path in ipairs(paths) do
    if fs.exists(path) and fs.isDir(path) then
      for _, file in ipairs(fs.list(path)) do
        if startsWith(file, prefix) and not seen[file] then
          seen[file] = true
          results[#results + 1] = file:sub(#prefix + 1)
        end
      end
    end
  end

  table.sort(results)
  return results
end

local function completeFromMeta(commandName, index, current, previous)
  local meta = commandMeta[commandName]
  if not meta then
    return nil
  end

  local rule = meta.completes[index]
  if not rule then
    return nil
  end

  if rule.kind == "file" then
    return completeFiles(current)
  end

  if rule.kind == "command" then
    local cmds = listCommands()
    local out = {}
    for name in pairs(cmds) do
      if startsWith(name, current) then
        out[#out + 1] = name:sub(#current + 1)
      end
    end
    table.sort(out)
    return out
  end

  if rule.kind == "list" and rule.extra ~= "" then
    local out = {}
    for item in rule.extra:gmatch("[^,%s]+") do
      if startsWith(item, current) then
        out[#out + 1] = item:sub(#current + 1)
      end
    end
    table.sort(out)
    return out
  end

  return nil
end

local function autoRegisterCompletions()
  scanCommandMetadata()

  local commands = listCommands()
  for name in pairs(commands) do
    if commandMeta[name] then
      registerCompletion(name, function(index, current, previous)
        return completeFromMeta(name, index, current, previous)
      end)
    end
  end
end
local function formatPrompt()
  local dir = shell.dir()

  if dir == "" or dir == "/" then
    return "root@CloverOS:~$ "
  end

  local root = ROOT
  if root == "/" then
    return "root@CloverOS:~" .. dir .. "$ "
  end

  if dir:sub(1, #root) == root then
    local rel = dir:sub(#root + 1)
    if rel == "" then
      rel = "/"
    end
    if rel:sub(1, 1) ~= "/" then
      rel = "/" .. rel
    end
    return "root@CloverOS:~" .. rel .. "$ "
  end

  return "root@CloverOS:" .. dir .. "$ "
end
local function runShell()
  -- Inlined CASH shell implementation (adapted/localised).
  -- This transplants the cash logic directly into runShell so the builtin shell
  -- behaves exactly like cash without executing the external cash.exe file.

  autoRegisterCompletions()
  Terminal.clear()
  Terminal.print("Welcome to CloverOS Shell. Type help for available commands.")

  -- Localise outer shell so we can provide a CASH-like environment without
  -- mutating globals for the rest of the OS.
  local topshell = shell
  local shell = {}
  local multishell = {}
  local pack = {}
  local start_time = os.epoch()
  local args = {}
  local running = true
  local shell_retval = 0
  local execCommand
  local shell_env = _ENV
  local pausedJob
  local CCKernel2 = kernel and users and kernel.getPID
  local OpusOS = kernel and kernel.hook

  local function trim(s) return string.match(s, '^()%s*$') and '' or string.match(s, '^%s*(.*%S)') end

  local HOME = "/"
  local SHELL = topshell and topshell.getRunningProgram and topshell.getRunningProgram() or "/usr/bin/cash"
  local PATH = topshell and topshell.path and string.gsub(topshell.path(), "%.:", "") or "/bin"
  local USER = CCKernel2 and users.getShortName(users.getuid()) or "root"
  local EDITOR = "edit"
  local OLDPWD = topshell and topshell.dir and topshell.dir() or "/"
  local PWD = topshell and topshell.dir and topshell.dir() or "/"
  local SHLVL = SHLVL and SHLVL + 1 or 1
  local TERM = "craftos"

  local vars = {
    PS1 = "\\s-\\v\\$ ",
    PS2 = "> ",
    IFS = "\n",
    CASH = SHELL,
    CASH_VERSION = "0.3",
    RANDOM = function() return math.random(0, 32767) end,
    SECONDS = function() return math.floor((os.epoch() - start_time) / 1000) end,
    HOSTNAME = os.getComputerLabel(),
    TERMINATE_QUIT = "no",
    ["*"] = table.concat(args, " "),
    ["@"] = function() return table.concat(args, " ") end,
    ["#"] = #args,
    ["?"] = 0,
    ["0"] = SHELL,
    _ = SHELL,
    ["$"] = CCKernel2 and kernel.getPID() or (OpusOS and kernel.getCurrent() or 0),
  }

  local aliases_local = aliases or {}
  local completion = completionInfo or {}
  local if_table, if_statement = {}, 0
  local while_table, while_statement = {}, 0
  local case_table, case_statement = {}, 0
  local function_name = nil
  local functions = {}
  local history = {}
  local historyfile
  local run_tokens
  local function_running = false
  local should_break = false
  local dirstack = {}
  local jobs = {}
  local completed_jobs = {}

  local builtins_local -- will populate next
  builtins_local = {
    [":"] = function() return 0 end,
    ["."] = function(path)
      path = fs.exists(path) and path or shell.resolve(path)
      local file = io.open(path, "r")
      if not file then return 1 end
      vars.LINENUM = 1
      for line in file:lines() do
        shell.run(line)
        vars.LINENUM = vars.LINENUM + 1
      end
      vars.LINENUM = nil
      file:close()
    end,
    echo = function(...)
      print(...); return 0
    end,
    builtin = function(name, ...) return builtins_local[name](...) end,
    cd = function(dir)
      if not fs.isDir(shell.resolve(dir or "/")) then
        printError("cash: cd: " .. dir .. ": No such file or directory")
        return 1
      end
      OLDPWD = PWD
      PWD = shell.resolve(dir or "/")
    end,
    command = function(...)
      no_funcs = true; shell.run(...); no_funcs = false; return vars["?"]
    end,
    exec = function(...)
      execCommand = table.concat({ ... }, ' '); running = false
    end,
    exit = function() running = false end,
    export = function(...) -- simplified export
      local e = { ... }
      if #e == 0 or e[1] == "-p" then
        for k, v in pairs(_ENV) do if type(v) == "string" or type(v) == "number" then print("export " .. k .. "=" .. v) end end
      else
        for k, v in ipairs(e) do
          local kk, vv = string.match(v, "(.+)=(.+)")
          if kk and vv then _ENV[kk] = vv end
        end
      end
    end,
    history = function(...) -- very small history
      for k, v in ipairs(history) do print(" " .. k .. " " .. v) end
    end,
    jobs = function() for k, v in pairs(jobs) do print("[" .. k .. "] " .. (v.cmd or "")) end end,
    pwd = function() print(PWD) end,
    read = function(var) vars[var] = read() end,
    set = function(...)
      local l = { ... }
      if #l == 0 then
        for k, v in pairs(vars) do
          print(k .. "=" .. v)
        end
      else
        for _, vv in ipairs(l) do
          local kk, vv2 = string.match(vv, "(.+)=(.+)")
          if kk then vars[kk] = vv2 end
        end
      end
    end,

    alias = function(...)
      local l = { ... }
      if #l == 0 then
        for k, v in pairs(aliases_local) do
          print("alias " .. k .. "=" .. v)
        end
      else
        for _, vv in ipairs(l) do
          local kk, vv2 = string.match(vv, "(.+)=(.+)")
          if kk then aliases_local[kk] = vv2 end
        end
      end
    end,

    sleep = function(t)
      os.sleep(tonumber(t))
    end,

    unalias = function(...)
      for _, v in ipairs({ ... }) do aliases_local[v] = nil end
    end,

    unset = function(...)
      for _, v in ipairs({ ... }) do vars[v] = nil end
    end,

    wait = function(job)
      if job then
        while jobs[tonumber(job)] ~= nil do os.sleep(0.1) end
      else
        while next(jobs) ~= nil do os.sleep(0.1) end
      end
    end,

    lua = function(...)
      if #({ ... }) > 0 then
        shell.run("/bin/lua", table.unpack({ ... }))
      else
        shell.run("/rom/programs/lua.lua")
      end
    end,

    cat = function(...)
      for _, v in ipairs({ ... }) do
        local f = fs.open(v, "r")
        if f then
          print(f.readAll())
          f.close()
        end
      end
    end,

    which = function(name)
      local p, localf = shell.resolveProgram(name)
      if not p and name then
        print(name)
      else
        print(p)
      end
    end,
  }

  -- Utility functions transplanted from cash
  local function splitSemicolons(cmdline)
    local escape = false
    local quoted = false
    local j = 1
    local retval = { "" }
    local lastc
    for c in string.gmatch(cmdline, ".") do
      local setescape = false
      if c == '"' or c == '\'' and not escape then
        quoted = not quoted
      elseif c == '\\' and not quoted and not escape then
        setescape = true
        escape = true
      end
      if c == ';' and not quoted and not escape then
        j = j + 1; retval[j] = ""
      elseif not (c == ' ' and retval[j] == "") then
        retval[j] = retval[j] .. c
      end
      if not setescape then escape = false end
      lastc = c
    end
    return retval
  end

  local function tokenize_cash(cmdline, noexpand)
    -- simplified adaptation of cash tokenize and expand logic
    local singleQuote = false
    local escape = false
    local expstr = ""
    if noexpand then
      expstr = cmdline
    else
      local i = 1
      while i <= #cmdline do
        local c = cmdline:sub(i, i)
        if c == '$' and not escape and not singleQuote then
          -- minimal var expand: use vars or _ENV
          local name = cmdline:sub(i + 1):match("^%{(.-)%}")
          if name then
            expstr = expstr .. tostring(_ENV[name] or vars[name] or ""); i = i + #name + 2
          else
            local name2 = cmdline:sub(i + 1):match("^(%w+)")
            if name2 then
              expstr = expstr .. tostring(_ENV[name2] or vars[name2] or ""); i = i + #name2 + 1
            else
              expstr = expstr .. c; i = i + 1
            end
          end
        else
          if c == '\'' and not escape then singleQuote = not singleQuote end
          escape = c == '\\' and not escape
          expstr = expstr .. c
          i = i + 1
        end
      end
    end
    -- now split into words respecting quotes
    local retval = { { [0] = "" } }
    local j = 1; local i = 0; local quoted = false; escape = false; local lastc
    for c in string.gmatch(expstr, ".") do
      if (c == '"' or c == "'") and not escape then
        quoted = not quoted
      elseif c == ' ' and not quoted and not escape then
        if #retval[j][i] > 0 then
          i = i + 1; retval[j][i] = ""
        end
      elseif c == ';' and not quoted and not escape then
        j = j + 1; i = 0; retval[j] = { [0] = "" }
      elseif not (c == '\\' and not quoted and not escape) then
        retval[j][i] = (retval[j][i] or "") .. c
      end
      escape = c == '\\' and not quoted and not escape
      lastc = c
    end
    for k, v in ipairs(retval) do
      if v[0] and v[0] ~= "" then
        local path, islocal
        if shell.resolveProgram then
          path, islocal = shell.resolveProgram(v[0])
        end
        path = path or v[0]
        if path then v[0] = path end
        v.vars = {}
      end
    end
    return retval
  end

  local function run_file(_tEnv, _sPath, ...)
    if type(_tEnv) ~= "table" then error("bad argument #1 (expected table, got " .. type(_tEnv) .. ")", 2) end
    if type(_sPath) ~= "string" then error("bad argument #2 (expected string, got " .. type(_sPath) .. ")", 2) end
    local tArgs = table.pack(...)
    local fnFile, err = loadfile(_sPath,
      setmetatable({ shell = shell, multishell = multishell, package = pack, require = require }, { __index = _ENV }))
    if fnFile then
      local ok, err = pcall(function()
        vars["?"] = fnFile(table.unpack(tArgs, 1, tArgs.n)); if vars["?"] == nil or vars["?"] == true then vars["?"] = 0 elseif vars["?"] == false then vars["?"] = 1 end
      end)
      if not ok then
        if err and err ~= "" then printError(err) end; vars["?"] = 1; return false
      end
      return true
    end
    if err and err ~= "" then printError(err) end
    vars["?"] = 1
    return false
  end

  local function execv(tokens)
    local path = tokens[0]
    if path == nil then return end
    if #tokens == 0 and string.find(path, "=") ~= nil then
      local k = string.sub(path, 1, string.find(path, "=") - 1)
      vars[k] = string.sub(path, string.find(path, "=") + 1)
      vars[k] = tonumber(vars[k]) or vars[k]
      return
    end
    local oldenv = {}
    for k, v in pairs(tokens.vars or {}) do
      oldenv[k] = _ENV[k]; _ENV[k] = v
    end
    if if_statement > 0 and not if_table[if_statement].cond and path ~= "else" and path ~= "elif" and path ~= "fi" then return end
    if builtins_local[path] ~= nil then
      vars["?"] = builtins_local[path](table.unpack(tokens))
      if vars["?"] == nil or vars["?"] == true then vars["?"] = 0 elseif vars["?"] == false then vars["?"] = 1 end
    elseif functions[path] ~= nil and not no_funcs then
      local oldargs = args
      args = tokens
      function_running = true
      for k, v in ipairs(functions[path]) do
        shell.run(v)
        if not function_running then break end
      end
      args = oldargs
    else
      if not fs.exists(path) then
        printError("cash: " .. path .. ": No such file or directory"); vars["?"] = -1; return
      end
      local _old = vars._
      vars._ = path
      run_file(
      setmetatable({ shell = shell, multishell = multishell, package = pack, require = require, arg = tokens },
        { __index = shell_env }), path, table.unpack(tokens))
      vars._ = _old
    end
    for k, v in pairs(tokens.vars or {}) do _ENV[k] = oldenv[k] end
  end

  run_tokens = function(tokens, isAsync)
    if tokens.async and not isAsync then
      local coro, pid
      if CCKernel2 then
        pid = kernel.fork("cash", function() run_tokens(tokens, true) end)
      else
        coro = coroutine.create(function() run_tokens(tokens, true) end)
      end
      local id = #jobs + 1
      jobs[id] = { cmd = tokens[1] and (tokens[1][0] .. " " .. table.concat(tokens[1], " ")) or "", coro = coro, pid =
      pid, isfg = false, start = true }
      print("[" .. (id) .. "] " .. (pid or ""))
    else
      for k, tok in ipairs(tokens) do
        if tok[0] then
          if trim(tok[0]) ~= "" and ((tok.last == 0 and vars["?"] == 0) or (tok.last == 1 and vars["?"] ~= 0) or tok.last == nil) then
            execv(tok)
          end
        else
          for kk, vv in pairs(tok.vars or {}) do vars[kk] = tonumber(vv) or vv end
        end
      end
    end
    return vars["?"] == 0
  end

  local run_tokens_async = function(tokens)
    local coro, pid
    if CCKernel2 then
      pid = kernel.fork("cash", function() run_tokens(tokens, true) end)
    else
      coro = coroutine.create(function() run_tokens(tokens, true) end)
    end
    local id = #jobs + 1
    jobs[id] = { cmd = tokens[1] and (tokens[1][0] .. " " .. table.concat(tokens[1], " ")) or "cash", coro = coro, pid =
    pid, isfg = not tokens.async, start = true }
    if tokens.async then print("[" .. (id) .. "] " .. (pid or "")) end
  end

  function shell.run(...)
    local cmd = table.concat({ ... }, " ")
    if cmd == "" or string.sub(cmd, 1, 1) == "#" then return end
    if function_name ~= nil then
      if string.find(cmd, "}") then function_name = nil else table.insert(functions[function_name], cmd) end; return true
    elseif while_statement > 0 then
      local tokens = splitSemicolons(cmd)
      for k, line in ipairs(tokens) do
        line = string.sub(line, #string.match(line, "^ *") + 1)
        if line == "do" or line == "done" or string.find(line, "^do ") or string.find(line, "^done ") then run_tokens(
          tokenize_cash(line)) end
        if while_statement > 0 then table.insert(while_table[1].lines, line) end
      end
      return true
    end
    local lines = splitSemicolons(cmd)
    for k, v in ipairs(lines) do run_tokens(tokenize_cash(v, string.sub(v, 1, 6) == "while ")) end
    return vars["?"] == 0
  end

  function shell.runAsync(...)
    local cmd = table.concat({ ... }, " ")
    if cmd == "" or string.sub(cmd, 1, 1) == "#" then return end
    if function_name ~= nil then
      if string.find(cmd, "}") then function_name = nil else table.insert(functions[function_name], cmd) end; return true
    elseif while_statement > 0 then
      local tokens = splitSemicolons(cmd)
      for k, line in ipairs(tokens) do
        line = string.sub(line, #string.match(line, "^ *") + 1)
        if line == "do" or line == "done" or string.find(line, "^do ") or string.find(line, "^done ") then run_tokens(
          tokenize_cash(line)) end
        if while_statement > 0 then table.insert(while_table[1].lines, line) end
      end
      return true
    end
    local lines = splitSemicolons(cmd)
    for k, v in ipairs(lines) do run_tokens_async(tokenize_cash(v, string.sub(v, 1, 6) == "while ")) end
    return vars["?"] == 0
  end

  -- minimal implementations of some shell helpers used by other parts
  function shell.resolve(localPath)
    if string.sub(localPath, 1, 1) == "/" then return fs.combine(localPath, "") else return fs.combine(PWD, localPath) end
  end

  function shell.resolveProgram(name)
    if builtins_local[name] ~= nil then return name end
    if aliases_local[name] ~= nil then name = aliases_local[name] end
    for path in string.gmatch(PATH, "[^:]+") do
      local candidate = fs.combine(shell.resolve(path), name)
      if fs.exists(candidate) and not fs.isDir(candidate) then return candidate end
      if fs.exists(candidate .. ".lua") and not fs.isDir(candidate .. ".lua") then return candidate .. ".lua" end
    end
    if fs.exists(shell.resolve(name)) and not fs.isDir(shell.resolve(name)) then return shell.resolve(name) end
    if fs.exists(shell.resolve(name .. ".lua")) and not fs.isDir(shell.resolve(name .. ".lua")) then return shell
      .resolve(name .. ".lua") end
    return nil
  end

  function shell.getRunningProgram() return vars._ end

  function shell.dir() return PWD end

  function shell.setDir(p)
    OLDPWD = PWD; PWD = p
  end

  function shell.path() return PATH end

  function shell.setPath(p) PATH = p end

  function shell.aliases() return aliases_local end

  function shell.setAlias(a, b) aliases_local[a] = b end

  function shell.clearAlias(a) aliases_local[a] = nil end

  function shell.completeProgram(prefix)
    if string.find(prefix, "/") then return fs.complete(prefix, PWD, true, false) else
      local retval = {}
      for path in string.gmatch(PATH, "[^:]+") do for _, v in ipairs(fs.complete(prefix, path, true, false)) do table
              .insert(retval, v) end end
      return retval
    end
  end

  -- readCommand and ansiWrite adapted to use Terminal/term
  local function ansiWrite(str)
    local seq = nil
    local bold = false
    local function getnum(d)
      if seq == "[" then
        return d or 1
      elseif seq and string.find(seq, ";") then
        local i = string.find(seq, ";")
        return tonumber(string.sub(seq, 2, i - 1)), tonumber(string.sub(seq, i + 1))
      elseif seq then
        return tonumber(string.sub(seq, 2))
      end
      return nil
    end
    for c in string.gmatch(str, ".") do
      if seq == "\27" then
        if c == "c" then
          term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.setCursorBlink(true)
        elseif c == "[" then
          seq = "["
        else
          seq = nil
        end
      elseif seq ~= nil and string.sub(seq, 1, 1) == "[" then
        if tonumber(c) ~= nil or c == ';' then
          seq = seq .. c
        else
          if c == 'm' then
            local n, m = getnum(0)
            if n == 0 then
              term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
            elseif n == 1 then bold = true elseif n >= 30 and n <= 37 then term.setTextColor(2 ^
              (15 - (n - 30) - (bold and 8 or 0))) end
            if m then end
          end
          seq = nil
        end
      elseif c == string.char(0x1b) then
        seq = "\27"
      else
        write(c)
      end
    end
  end

  local function readCommand()
    if term.getGraphicsMode and term.getGraphicsMode() then term.setGraphicsMode(false) end
    local prompt = (vars.PS1 or "\\$ ")
    ansiWrite(prompt)
    local str = readLine("", history) or ""
    return str
  end

  local function jobManager()
    while running do
      local e = { os.pullEventRaw() }
      local delete = {}
      for k, v in pairs(jobs) do
        if not v.paused and (v.filter == nil or v.filter == e[1]) and (v.isfg or v.start or not (
              e[1] == "key" or e[1] == "char" or e[1] == "key_up" or e[1] == "paste" or e[1] == "mouse_click" or e[1] == "mouse_up" or e[1] == "mouse_drag" or e[1] == "mouse_scroll" or e[1] == "monitor_touch")) then
          local oldterm = term.current()
          if v.term then term.redirect(v.term) end
          local ok, filter = coroutine.resume(v.coro, table.unpack(e))
          v.term = term.redirect(oldterm)
          if coroutine.status(v.coro) == "dead" then
            table.insert(delete, k); completed_jobs[k] = { err = "Done", cmd = v.cmd, isfg = v.isfg }; os.queueEvent(
            "job_complete", k)
          elseif not ok then
            table.insert(delete, k); completed_jobs[k] = { err = filter, cmd = v.cmd, isfg = v.isfg }; os.queueEvent(
            "job_complete", k)
          end
          v.filter = filter; v.start = false
        end
      end
      for _, v in ipairs(delete) do jobs[v] = nil end
    end
  end

  parallel.waitForAny(function()
    while running do
      for k, v in pairs(completed_jobs) do if not v.isfg then print("[" .. k .. "] " .. v.err .. "  " .. v.cmd) end end
      completed_jobs = {}
      shell.runAsync(readCommand())
      while next(jobs) ~= nil do
        local b = true
        for k, v in pairs(jobs) do if v.isfg and not v.paused then
            b = false; break
          end end
        if b then break end
        if os.pullEventRaw() == "terminate" then
          for k, v in pairs(jobs) do if v.isfg and not v.paused then
              jobs[k] = nil; print("^T"); b = true; break
            end end
        end
        if b then break end
      end
    end
  end, function()
    local ctrlHeld = false
    while running do
      local ev = { os.pullEventRaw() }
      if ev[1] == "key" and (ev[2] == keys.leftCtrl or ev[2] == keys.rightCtrl) then
        ctrlHeld = true
      elseif ev[1] == "key_up" and (ev[2] == keys.leftCtrl or ev[2] == keys.rightCtrl) then
        ctrlHeld = false
      elseif ctrlHeld and ev[1] == "key" and ev[2] == keys.z then
        print("^Z")
        for k, v in pairs(jobs) do if v.isfg and not v.paused then
            v.paused = true; pausedJob = k; print("[" .. k .. "]+  Paused  " .. v.cmd); os.queueEvent("job_paused"); break
          end end
      end
    end
  end, jobManager)

  if execCommand then
    shell.run(execCommand); return vars["?"]
  end
  return shell_retval
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
    { name = "Terminal",     run = runShell },
    { name = "File Manager", run = fileManager },
    {
      name = "About",
      run = function()
        Terminal.clear()
        Terminal.print("CloverOS v1.0.0")
        Terminal.print("Author: CloverOS Team")
        Terminal.print("")
        Terminal.print("Press Enter to return.")
        readInput("")
      end
    },
    {
      name = "Shutdown",
      run = function()
        Terminal.print("Shutting down...")
        os.sleep(1)
        os.shutdown()
      end
    }
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
