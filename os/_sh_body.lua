local function DISK_ROOT()
  for i = 0, 99 do
    local r = "/disk" .. (i == 0 and "" or tostring(i))
    if fs.exists(r .. "/CloverOS_API.lua") and fs.exists(r .. "/boot/kernel.lua") then
      return r
    end
  end
  if fs.exists("/CloverOS_API.lua") then
    return ""
  end
  return nil
end

local completionInfo = {}
local aliases = {}
local shellEnv = {}
local function getCommandDirs()
  local dirs = {}
  local seen = {}

  local function add(dir)
    if dir and dir ~= "" and not seen[dir] then
      seen[dir] = true
      dirs[#dirs + 1] = dir
    end
  end

  add("/bin")
  add("/usr/bin")

  if ROOT and ROOT ~= "" then
    add(ROOT .. "/bin")
    add(ROOT .. "/usr/bin")
  end

  local diskRoot = DISK_ROOT()
  if diskRoot and diskRoot ~= "" then
    add(diskRoot .. "/bin")
    add(diskRoot .. "/usr/bin")
  end

  return dirs
end
local function listCommands()
  local commands = {}
  local seen = {}

  for _, dir in ipairs(getCommandDirs()) do
    if fs.exists(dir) and fs.isDir(dir) then
      for _, file in ipairs(fs.list(dir)) do
        local full = fs.combine(dir, file)

        if fs.exists(full) and not fs.isDir(full) then
          local isExecutable = file:match("%.[lL][uU][aA]$")
            or file:match("%.[eE][xX][eE]$")
            or file:match("%.[dD][lL][lL]$")
            or not file:match("%.")

          if isExecutable then
            local name = file:gsub("%..+$", "")
            if not seen[name] then
              seen[name] = true
              commands[name] = full
            end
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
  if not tok or tok == "" then
    return tok
  end
  -- Tilde expansion at start
  if tok:sub(1, 1) == "~" then
    local home = shellEnv.HOME or ROOT or "/"
    if tok == "~" then
      tok = home
    elseif tok:sub(2, 2) == "/" then
      tok = home .. tok:sub(2)
    end
  end

  -- Variable expansion: ${VAR} or $VAR
  local function repl(var)
    local name = var:match("^%${(.-)}$") or var:match("^%$(.-)$")
    if not name then
      return var
    end
    return tostring(shellEnv[name] or "")
  end

  -- Replace ${VAR}
  tok = tok:gsub("%${(.-)}", function(n)
    return tostring(shellEnv[n] or "")
  end)
  -- Replace $VAR (simple)
  tok = tok:gsub("%$(%w+)", function(n)
    return tostring(shellEnv[n] or "")
  end)

  return tok
end

local function parseEnvLine(line)
  if not line or line == "" then
    return nil, nil
  end
  line = trim(line)
  if line == "" or line:sub(1, 1) == "#" then
    return nil, nil
  end
  local name, value = line:match("^([%w_]+)%s*=%s*(.*)$")
  if not name then
    name, value = line:match("^export%s+([%w_]+)%s*=%s*(.*)$")
  end
  if name then
    value = value or ""
    if value:sub(1, 1) == '"' and value:sub(-1) == '"' then
      value = value:sub(2, -2)
    end
    return name, value
  end
  return nil, nil
end

local function loadProfile(path)
  if not fs.exists(path) or fs.isDir(path) then
    return
  end
  local handle = fs.open(path, "r")
  if not handle then
    return
  end
  while true do
    local line = handle.readLine()
    if line == nil then break end
    local name, value = parseEnvLine(line)
    if name then
      shellEnv[name] = value
    end
  end
  handle.close()
end

local function loadShellProfiles()
  loadProfile("/etc/profile")
  local home = shellEnv.HOME or ROOT or "/"
  local userProfile = home .. "/.profile"
  loadProfile(userProfile)
end

local function readPackageMetadata(pkg)
  if not pkg or pkg == "" then
    return nil
  end
  local pkgPath = fs.combine(APT_DIR, pkg)
  local pkgFile = fs.combine(pkgPath, "package.json")
  if not fs.exists(pkgFile) or fs.isDir(pkgFile) then
    return nil
  end
  local h = fs.open(pkgFile, "r")
  if not h then
    return nil
  end
  local content = h.readAll()
  h.close()
  if textutils and textutils.unserializeJSON then
    local metadata = textutils.unserializeJSON(content)
    if type(metadata) == "table" then
      return metadata
    end
  end
  return nil
end

local function listAvailablePackages()
  local packages = {}
  if not fs.exists(APT_DIR) or not fs.isDir(APT_DIR) then
    return packages
  end
  for _, name in ipairs(fs.list(APT_DIR)) do
    local path = fs.combine(APT_DIR, name)
    if fs.isDir(path) then
      table.insert(packages, name)
    end
  end
  table.sort(packages)
  return packages
end

local function getInstalledPackages()
  local installed = {}
  if not fs.exists(APT_INSTALLED_FILE) then
    return installed
  end
  local h = fs.open(APT_INSTALLED_FILE, "r")
  if not h then
    return installed
  end
  while true do
    local line = h.readLine()
    if not line then
      break
    end
    line = trim(line)
    if line ~= "" then
      installed[#installed + 1] = line
    end
  end
  h.close()
  return installed
end

local function isPackageInstalled(pkg)
  if not pkg or pkg == "" then
    return false
  end
  local installed = {}
  for _, name in ipairs(getInstalledPackages()) do
    installed[name] = true
  end
  return installed[pkg] == true
end

local function saveInstalledPackages(installed)
  local h = fs.open(APT_INSTALLED_FILE, "w")
  if not h then
    return false
  end
  for _, name in ipairs(installed) do
    if name and name ~= "" then
      h.write(name .. "\n")
    end
  end
  h.close()
  return true
end

local function installPackage(pkg)
  local metadata = readPackageMetadata(pkg)
  if not metadata then
    return false, "apt: package not found: " .. tostring(pkg)
  end
  if not metadata.files or type(metadata.files) ~= "table" then
    return false, "apt: invalid package metadata for " .. tostring(pkg)
  end
  local installDir = ROOT .. "/usr/bin"
  if not fs.exists(installDir) then
    fs.makeDir(installDir)
  end
  for _, file in ipairs(metadata.files) do
    local src = fs.combine(fs.combine(APT_DIR, pkg), file)
    local dst = fs.combine(installDir, file)
    if not fs.exists(src) or fs.isDir(src) then
      return false, "apt: package file missing: " .. tostring(file)
    end
    if fs.exists(dst) then
      return false, "apt: target already exists: " .. tostring(file)
    end
    fs.copy(src, dst)
  end
  local installed = getInstalledPackages()
  table.insert(installed, pkg)
  saveInstalledPackages(installed)
  return true
end

local function removePackage(pkg)
  if not isPackageInstalled(pkg) then
    return false, "apt: package not installed: " .. tostring(pkg)
  end
  local metadata = readPackageMetadata(pkg)
  if not metadata or type(metadata.files) ~= "table" then
    return false, "apt: invalid package metadata for " .. tostring(pkg)
  end
  local installDir = ROOT .. "/usr/bin"
  for _, file in ipairs(metadata.files) do
    local dst = fs.combine(installDir, file)
    if fs.exists(dst) and not fs.isDir(dst) then
      fs.delete(dst)
    end
  end
  local installed = {}
  for _, name in ipairs(getInstalledPackages()) do
    if name ~= pkg then
      installed[#installed + 1] = name
    end
  end
  saveInstalledPackages(installed)
  return true
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
  return kernel.input.readline(prompt, history, completeLine)
end

local function shellBuiltinHelp()
  Terminal.print("Available commands:")
  Terminal.print("  help")
  Terminal.print("  exit")
  Terminal.print("  shutdown")
  Terminal.print("  reboot")
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
  local items = { "exit", "shutdown", "reboot", "installer", "run" }
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
local function shellUsage(cmd, usage)
  Terminal.print("Usage: " .. cmd .. (usage and (" " .. usage) or ""))
end

local function resolvePath(p)
  if not p or p == "" then
    return process.dir()
  end

  return path.resolve(p)
end

local function printFile(path)
  local h = fs.open(path, "r")
  if not h then
    Terminal.print("Unable to open file: " .. tostring(path))
    return
  end

  while true do
    local line = h.readLine()
    if line == nil then
      break
    end
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
    if line == nil then
      break
    end
    lines[#lines + 1] = line
  end
  h.close()

  local start = math.max(1, #lines - n + 1)
  for i = start, #lines do
    Terminal.print(lines[i])
  end
end

table.contains = function(t, v)
  for _, val in ipairs(t) do
    if val == v then return true end
  end
  return false
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
    Terminal.print("  ls [options] [path]")
    Terminal.print("  history")
    Terminal.print("  alias [name value]")
    Terminal.print("  unalias <name>")
    Terminal.print("  env")
    Terminal.print("  set")
    Terminal.print("  uname [option]")
    Terminal.print("  grep <pattern> <file> [file...]")
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
    Terminal.print("  status")
    Terminal.print("  ps")
    Terminal.print("  kill <pid>")
    Terminal.print("  chmod <mode> <file>")
    Terminal.print("  chown <user> <file>")
    Terminal.print("  df")
    Terminal.print("  du [path]")
    Terminal.print("  find <dir> -name <pattern>")
    Terminal.print("  wget <url>")
    Terminal.print("  ping <host>")
    Terminal.print("  useradd <username>")
    Terminal.print("  userdel <username>")
    Terminal.print("  passwd [username]")
    Terminal.print("  su [username]")
    Terminal.print("  sudo <command>")
    Terminal.print("  nano <file>")
    Terminal.print("  vim <file>")
    Terminal.print("  id [username]")
    Terminal.print("  groups [username]")
    Terminal.print("  who")
    Terminal.print("  w")
    Terminal.print("  top")
    Terminal.print("  free")
    Terminal.print("  uptime")
    Terminal.print("  ifconfig")
    Terminal.print("  netstat")
    Terminal.print("  mount")
    Terminal.print("  umount <target>")
    Terminal.print("  dmesg")
    Terminal.print("  journalctl")
    Terminal.print("  systemctl <action> <service>")
    Terminal.print("  apt <list|search|info|install|remove>")

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
    kernel.shutdown()
  end,

  reboot = function()
    kernel.reboot()
  end,

  installer = function()
    if _G.CloverOS and type(_G.CloverOS.runInstaller) == "function" then
      _G.CloverOS.runInstaller()
    else
      process.run("wget", "run", "https://palordersoftworksofficial.github.io/CloverOS/netinstall.lua")
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

    process.run(targetPath, table.unpack(args))
  end,

  cd = function(path)
    if not path or path == "" then
      process.setDir(ROOT)
      shellEnv.PWD = process.dir()
      return
    end

    local target = resolvePath(path)
    if fs.isDir(target) then
      process.setDir(target)
      shellEnv.PWD = process.dir()
    else
      Terminal.print("Not a directory: " .. tostring(path))
    end
  end,

  pwd = function()
    Terminal.print(process.dir())
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
      kernel.sleep(sec)
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
    local pathEnv = shellEnv.PATH or process.path() or "/bin"
    for p in pathEnv:gmatch("[^:]+") do
      local candidate = fs.combine(p, resolved)
      if fs.exists(candidate) and not fs.isDir(candidate) then
        Terminal.print(candidate)
        return
      end
    end

    Terminal.print("Not found")
  end,

  ls = function(...)
    local args = { ... }
    local showAll = false
    local longFormat = false
    local target = "."
    for _, arg in ipairs(args) do
      if arg == "-a" then
        showAll = true
      elseif arg == "-l" then
        longFormat = true
      elseif arg:sub(1, 1) == "-" then
        -- ignore unknown option
      else
        target = arg
      end
    end
    local path = resolvePath(target)
    if not fs.exists(path) then
      Terminal.print("No such file or directory: " .. tostring(target))
      return
    end
    if fs.isDir(path) then
      local entries = fs.list(path)
      table.sort(entries)
      for _, name in ipairs(entries) do
        if showAll or name:sub(1, 1) ~= "." then
          if longFormat then
            local full = fs.combine(path, name)
            local info = fs.isDir(full) and "d" or "-"
            local size = fs.isDir(full) and "" or tostring(fs.getSize(full))
            Terminal.print(string.format("%s %s %s", info, name, size))
          else
            Terminal.print(name)
          end
        end
      end
    else
      Terminal.print(target)
    end
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
    if builtins[cmd] and type(builtins[cmd]) == "function" then
      Terminal.print("No manual entry for builtin: " .. cmd)
      return
    end
    local commands = listCommands()
    local path = commands[cmd]
    local manPath = shellEnv.MANPATH or "/etc/man"
    local manFile = fs.combine(manPath, cmd .. ".man")
    if fs.exists(manFile) and not fs.isDir(manFile) then
      printFile(manFile)
      return
    end
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

  source = function(file)
    if not file or file == "" then
      Terminal.print("Usage: source <file>")
      return
    end
    local target = resolvePath(file)
    if not fs.exists(target) then
      Terminal.print("No such file: " .. tostring(file))
      return
    end
    local handle = fs.open(target, "r")
    if not handle then
      Terminal.print("Unable to open file: " .. tostring(file))
      return
    end
    while true do
      local line = handle.readLine()
      if not line then break end
      local name, value = parseEnvLine(line)
      if name then
        shellEnv[name] = value
      end
    end
    handle.close()
  end,

  env = function()
    for k, v in pairs(shellEnv) do
      Terminal.print(k .. "=" .. tostring(v))
    end
  end,

  set = function()
    local keys = {}
    for k in pairs(shellEnv) do
      table.insert(keys, k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      Terminal.print(k .. "=" .. tostring(shellEnv[k]))
    end
  end,

  grep = function(pattern, ...)
    if not pattern or pattern == "" then
      Terminal.print("Usage: grep <pattern> <file> [file...]")
      return
    end
    local args = { ... }
    if #args == 0 then
      Terminal.print("Usage: grep <pattern> <file> [file...]")
      return
    end
    for _, p in ipairs(args) do
      local target = resolvePath(p)
      local h = fs.open(target, "r")
      if not h then
        Terminal.print("Unable to open file: " .. tostring(p))
        goto continue_grep
      end
      local lineno = 0
      while true do
        local line = h.readLine()
        if not line then break end
        lineno = lineno + 1
        if line:find(pattern) then
          Terminal.print(string.format("%s:%d:%s", p, lineno, line))
        end
      end
      h.close()
      ::continue_grep::
    end
  end,

  uname = function(option)
    local sysname = "CloverOS"
    local nodename = shellEnv.HOSTNAME or "CloverOS"
    local release = "1.0"
    local version = "GNU/Linux CloverOS 2.0"
    local machine = "cc"
    if option == "-a" then
      Terminal.print(sysname .. " " .. nodename .. " " .. release .. " " .. version .. " " .. machine)
    elseif option == "-s" then
      Terminal.print(sysname)
    elseif option == "-n" then
      Terminal.print(nodename)
    elseif option == "-r" then
      Terminal.print(release)
    elseif option == "-v" then
      Terminal.print(version)
    else
      Terminal.print(sysname)
    end
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
      if not line then
        break
      end
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
    Terminal.print(kernel.date("%c"))
  end,

  time = function()
    Terminal.print(kernel.date("%X"))
  end,

  whoami = function()
    Terminal.print(currentUser or "root")
  end,

  hostname = function()
    if settingsLoaded and editionSettings.envType == "craftos" then
      Terminal.print("CloverOS-CraftOS")
    else
      Terminal.print("CloverOS")
    end
  end,

  status = function()
    local s = kernel.status()
    Terminal.print("Name: " .. s.name)
    Terminal.print("Version: " .. s.version)
    Terminal.print("Build: " .. s.build)
    Terminal.print("Uptime: " .. tostring(kernel.date("%H:%M:%S", os.time())))
    Terminal.print("Booted: " .. tostring(s.booted))
    Terminal.print("Shutdown requested: " .. tostring(s.shutdownRequested))
    Terminal.print("Reboot requested: " .. tostring(s.rebootRequested))
    Terminal.print("User: " .. tostring(currentUser or "root"))
  end,

  ps = function()
    Terminal.print("PID TTY TIME CMD")
    Terminal.print("1 ? 00:00:00 init")
  end,

  kill = function(pid)
    if not pid then
      Terminal.print("Usage: kill <pid>")
      return
    end
    Terminal.print("kill: " .. pid .. ": operation not permitted")
  end,

  chmod = function(mode, file)
    if not mode or not file then
      Terminal.print("Usage: chmod <mode> <file>")
      return
    end
    Terminal.print("chmod: operation not supported")
  end,

  chown = function(user, file)
    if not user or not file then
      Terminal.print("Usage: chown <user> <file>")
      return
    end
    Terminal.print("chown: operation not supported")
  end,

  df = function()
    Terminal.print("Filesystem 1K-blocks Used Available Use% Mounted on")
    Terminal.print("rootfs 1024 512 512 50% /")
  end,

  du = function(path)
    path = path or "."
    Terminal.print("4 " .. path)
  end,

  find = function(dir, name)
    if not dir or not name then
      Terminal.print("Usage: find <dir> -name <pattern>")
      return
    end

    local target = resolvePath(dir)
    if not fs.exists(target) then
      Terminal.print("No such directory: " .. tostring(dir))
      return
    end
    if not fs.isDir(target) then
      Terminal.print("Not a directory: " .. tostring(dir))
      return
    end

    local pattern = name
    if pattern:sub(1, 1) == [[" ]] or pattern:sub(1, 1) == "'" then
      pattern = pattern:sub(2, -2)
    end
    local luaPattern = pattern:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
    luaPattern = "^" .. luaPattern:gsub("\\%*", ".*") .. "$"

    local function scan(path)
      for _, entry in ipairs(fs.list(path)) do
        local full = fs.combine(path, entry)
        if entry:match(luaPattern) then
          Terminal.print(full)
        end
        if fs.isDir(full) then
          scan(full)
        end
      end
    end

    scan(target)
  end,

  wget = function(url)
    if not url then
      Terminal.print("Usage: wget <url>")
      return
    end
    local downloader = process.resolve("wget")
    if downloader then
      return process.run(downloader, url)
    end
    Terminal.print("wget: command not available")
  end,

  ping = function(host)
    if not host then
      Terminal.print("Usage: ping <host>")
      return
    end
    local pingCmd = process.resolve("ping")
    if pingCmd then
      return process.run(pingCmd, host)
    end
    Terminal.print("ping: command not available")
  end,

  useradd = function(user)
    if not user then
      Terminal.print("Usage: useradd <username>")
      return
    end
    if users[user] then
      Terminal.print("useradd: user '" .. user .. "' already exists")
      return
    end
    users[user] = { uid = 1000, gid = 1000, home = "/home/" .. user, shell = "/bin/sh", password = "x" }
    saveUsers()
    ensureDirectory(users[user].home)
    Terminal.print("useradd: user '" .. user .. "' added")
  end,

  userdel = function(user)
    if not user then
      Terminal.print("Usage: userdel <username>")
      return
    end
    if not users[user] then
      Terminal.print("userdel: user '" .. user .. "' does not exist")
      return
    end
    users[user] = nil
    saveUsers()
    Terminal.print("userdel: user '" .. user .. "' deleted")
  end,

  passwd = function(user)
    user = user or currentUser
    if not users[user] then
      Terminal.print("passwd: user '" .. user .. "' does not exist")
      return
    end
    Terminal.print("Changing password for " .. user)
    local newpass = readInput("New password: ", true)
    users[user].password = newpass
    saveUsers()
    Terminal.print("passwd: password updated successfully")
  end,

  su = function(user)
    user = user or "root"
    if not users[user] then
      Terminal.print("su: user '" .. user .. "' does not exist")
      return
    end
    local pass = readInput("Password: ", true)
    if pass == users[user].password then
      currentUser = user
      Terminal.print("su: switched to " .. user)
    else
      Terminal.print("su: incorrect password")
    end
  end,

  sudo = function(...)
    local args = {...}
    if #args == 0 then
      Terminal.print("Usage: sudo <command>")
      return
    end
    -- for simplicity, just run as root
    local cmd = table.remove(args, 1)
    if builtins[cmd] then
      builtins[cmd](table.unpack(args))
    else
      Terminal.print("sudo: " .. cmd .. ": command not found")
    end
  end,

  nano = function(file)
    if not file then
      Terminal.print("Usage: nano <file>")
      return
    end
    local editor = process.resolve("edit")
    if editor then
      return process.run(editor, file)
    end
    Terminal.print("nano: editor not available")
  end,

  vim = function(file)
    if not file then
      Terminal.print("Usage: vim <file>")
      return
    end
    local editor = process.resolve("edit")
    if editor then
      return process.run(editor, file)
    end
    Terminal.print("vim: editor not available")
  end,

  id = function(user)
    user = user or currentUser
    if not users[user] then
      Terminal.print("id: '" .. user .. "': no such user")
      return
    end
    Terminal.print("uid=" .. users[user].uid .. "(" .. user .. ") gid=" .. users[user].gid .. "(" .. user .. ")")
  end,

  groups = function(user)
    user = user or currentUser
    if not users[user] then
      Terminal.print("groups: '" .. user .. "': no such user")
      return
    end
    local glist = {}
    for gname, ginfo in pairs(groups) do
      if table.contains(ginfo.members, user) then
        table.insert(glist, gname)
      end
    end
    Terminal.print(table.concat(glist, " "))
  end,

  who = function()
    Terminal.print(currentUser .. " tty1 " .. kernel.date("%Y-%m-%d %H:%M"))
  end,

  w = function()
    Terminal.print("USER TTY FROM LOGIN@ IDLE JCPU PCPU WHAT")
    Terminal.print(currentUser .. " tty1 - " .. kernel.date("%H:%M") .. " 0.00s 0.00s -")
  end,

  top = function()
    Terminal.print("top - " .. kernel.date("%H:%M:%S"))
    Terminal.print("Tasks: 1 total, 1 running, 0 sleeping, 0 stopped, 0 zombie")
    Terminal.print("%Cpu(s): 0.0 us, 0.0 sy, 0.0 ni, 100.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st")
    Terminal.print("KiB Mem : 1024 total, 512 free, 512 used, 0 buff/cache")
    Terminal.print("KiB Swap: 0 total, 0 free, 0 used. 512 avail Mem")
    Terminal.print("PID USER PR NI VIRT RES SHR S %CPU %MEM TIME+ COMMAND")
    Terminal.print("1 root 20 0 1024 512 256 R 0.0 50.0 0:00.00 init")
  end,

  free = function()
    Terminal.print("              total        used        free      shared  buff/cache   available")
    Terminal.print("Mem:          1024         512         512           0         0         512")
    Terminal.print("Swap:             0           0           0")
  end,

  uptime = function()
    Terminal.print(" " .. kernel.date("%H:%M:%S") .. " up 0 min, 1 user, load average: 0.00, 0.00, 0.00")
  end,

  ifconfig = function()
    Terminal.print("eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500")
    Terminal.print("        inet 192.168.1.100 netmask 255.255.255.0 broadcast 192.168.1.255")
    Terminal.print("        ether 00:00:00:00:00:00 txqueuelen 1000 (Ethernet)")
  end,

  netstat = function()
    Terminal.print("Active Internet connections (w/o servers)")
    Terminal.print("Proto Recv-Q Send-Q Local Address Foreign Address State")
  end,

  mount = function()
    Terminal.print("/dev/root on / type ext4 (rw)")
  end,

  umount = function(target)
    if not target then
      Terminal.print("Usage: umount <target>")
      return
    end
    Terminal.print("umount: " .. target .. ": not mounted")
  end,

  dmesg = function()
    for _, line in ipairs(kernel.journal()) do
      Terminal.print(line)
    end
  end,

  journalctl = function()
    local lines = kernel.journal()
    Terminal.print("-- Logs begin at " .. kernel.date("%Y-%m-%d %H:%M:%S") .. ", end at " .. kernel.date("%Y-%m-%d %H:%M:%S") .. " --")
    for _, line in ipairs(lines) do
      Terminal.print(line)
    end
  end,

  systemctl = function(action, service)
    if not action then
      Terminal.print("Usage: systemctl <action> <service>")
      return
    end
    action = action:lower()
    if action == "list" then
      Terminal.print("UNIT LOAD ACTIVE SUB DESCRIPTION")
      Terminal.print("- no services loaded -")
      return
    elseif action == "status" then
      if not service then
        Terminal.print("Usage: systemctl status <service>")
        return
      end
      Terminal.print(service .. ": service not found")
      return
    end
    Terminal.print("systemctl: " .. action .. " " .. (service or "") .. ": not implemented")
  end,

  apt = function(command, pkg)
    if not command or command == "list" then
      local installedOnly = false
      if pkg == "--installed" or pkg == "installed" then
        installedOnly = true
      end
      if installedOnly then
        local installed = getInstalledPackages()
        if #installed == 0 then
          Terminal.print("No packages installed.")
          return
        end
        for _, name in ipairs(installed) do
          Terminal.print(name)
        end
        return
      end
      local names = listAvailablePackages()
      if #names == 0 then
        Terminal.print("No packages available.")
        return
      end
      for _, name in ipairs(names) do
        Terminal.print(name)
      end
      return
    end
    local subcmd = command:lower()
    if subcmd == "search" then
      if not pkg then
        Terminal.print("Usage: apt search <term>")
        return
      end
      local termLower = pkg:lower()
      local found = false
      for _, name in ipairs(listAvailablePackages()) do
        local metadata = readPackageMetadata(name)
        if metadata then
          local desc = tostring(metadata.description or "")
          if name:lower():find(termLower, 1, true) or desc:lower():find(termLower, 1, true) then
            Terminal.print(name .. " - " .. desc)
            found = true
          end
        end
      end
      if not found then
        Terminal.print("No packages matched: " .. pkg)
      end
      return
    end
    if subcmd == "info" then
      if not pkg then
        Terminal.print("Usage: apt info <package>")
        return
      end
      local metadata = readPackageMetadata(pkg)
      if not metadata then
        Terminal.print("apt: package not found: " .. pkg)
        return
      end
      for k, v in pairs(metadata) do
        Terminal.print(tostring(k) .. ": " .. tostring(v))
      end
      Terminal.print("Installed: " .. tostring(isPackageInstalled(pkg)))
      return
    end
    if subcmd == "install" then
      if not pkg then
        Terminal.print("Usage: apt install <package>")
        return
      end
      local ok, err = installPackage(pkg)
      if not ok then
        Terminal.print(err)
      else
        Terminal.print("Installed " .. pkg)
      end
      return
    end
    if subcmd == "remove" or subcmd == "uninstall" then
      if not pkg then
        Terminal.print("Usage: apt remove <package>")
        return
      end
      local ok, err = removePackage(pkg)
      if not ok then
        Terminal.print(err)
      else
        Terminal.print("Removed " .. pkg)
      end
      return
    end
    Terminal.print("apt: unknown command")
  end,
  screenfetch = function()
	local fs = kernel.fs
	local term = kernel.term
	local computer = kernel.computer
	local system = kernel.system

	local logo = {
		"\x1b[30;40m                \x1b[0m",
		"\x1b[30;40m  \x1b[33;106m\x88\x1b[96;43m\x8F\x1b[96;40m\x90 \x1b[30;106m\x9F\x1b[96;40m\x90   \x1b[30;106m\x9F\x1b[96;43m\x8F\x1b[33;106m\x84\x1b[30;40m  \x1b[0m",
		"\x1b[96;40m \x9A\x1b[33;106m\x89\x84\x1b[33;41m\x82\x1b[33;40m\x94\x1b[30;106m\x95 \x1b[96;40m\x90 \x1b[30;43m\x97\x1b[33;41m\x81\x1b[33;106m\x88\x86\x1b[30;106m\x9A\x1b[30;40m \x1b[0m",
		"\x1b[30;106m\x9F\x1b[96;43m\x9B\x8C\x1b[96;41m\x95 \x1b[33;40m\x95\x1b[30;106m\x95 \x96\x1b[30;40m \x1b[30;43m\x95\x1b[96;41m \x1b[31;106m\x95\x1b[96;43m\x8C\x1b[33;106m\x98\x1b[96;40m\x90\x1b[0m",
		"\x1b[30;106m\x95\x1b[33;106m\x8C\x84\x1b[96;41m\x95 \x1b[30;43m\x8A\x1b[30;106m\x95\x1b[96;100m\x8F\x8F\x1b[96;40m\x95\x1b[30;43m\x85\x1b[96;41m \x1b[31;106m\x95\x1b[33;106m\x88\x8C\x1b[96;40m\x95\x1b[0m",
		"\x1b[96;40m\x8A\x1b[96;43m\x9C\x8E\x1b[31;106m\x82\x1b[33;41m \x82\x1b[90;106m\x95\x1b[33;106m\x90\x1b[96;43m\x9F\x1b[96;100m\x95\x1b[33;41m\x81 \x1b[31;106m\x81\x1b[96;43m\x8D\x1b[33;106m\x93\x1b[96;40m\x85\x1b[0m",
		"\x1b[30;40m \x1b[96;43m\x9E\x1b[33;106m\x8C\x1b[96;43m\x9B\x1b[31;106m\x82\x1b[96;41m\x90\x1b[90;106m\x95\x1b[33;106m\x85\x8A\x1b[96;100m\x95\x1b[31;106m\x9F\x81\x1b[33;106m\x98\x8C\x92\x1b[30;40m \x1b[0m",
		"\x1b[96;40m \x82\x1b[33;106m\x86\x99\x99\x1b[96;100m\x95\x1b[33;106m\x8A\x88\x81\x85\x1b[90;106m\x95\x1b[96;43m\x99\x99\x1b[33;106m\x89\x1b[106;40m\x81 \x1b[0m",
		"\x1b[33;40m  \x82\x8B\x1b[90;106m \x96 \x1b[33;106m\x95\x1b[96;43m\x95\x1b[96;106m \x1b[96;100m\x96\x1b[96;106m \x1b[33;40m\x87\x81  \x1b[0m",
		"\x1b[96;40m     \x83\x8B\x8F\x8F\x87\x83     \x1b[0m",
		"\x1b[30;40m                \x1b[0m",
	}

	local function formatTime(seconds)
		local h = math.floor(seconds / 3600)
		local m = math.floor(seconds / 60) % 60
		local s = seconds % 60

		local out = s .. "s"
		if m > 0 or h > 0 then
			out = m .. "m " .. out
		end
		if h > 0 then
			out = h .. "h " .. out
		end
		return out
	end

	local function formatBytes(bytes)
		if bytes >= 1073741824 then
			return ("%.3g GiB"):format(bytes / 1073741824)
		elseif bytes >= 1048576 then
			return ("%.3g MiB"):format(bytes / 1048576)
		elseif bytes >= 1024 then
			return ("%.3g kiB"):format(bytes / 1024)
		else
			return ("%.3g B"):format(bytes)
		end
	end

	local function trimAnsi(text, maxVisible)
		local visible = 0
		local inEscape = false

		for ch, idx in text:gmatch("(.)()") do
			if inEscape then
				if ch == "m" then
					inEscape = false
				end
			elseif ch == "\x1b" then
				inEscape = true
			else
				visible = visible + 1
				if visible == maxVisible then
					return text:sub(1, idx)
				end
			end
		end

		return text
	end

	local leftName = system.hostname() or ("Computer " .. tostring(computer.id()))
	local rightName = computer.label() or ("Computer " .. tostring(computer.id()))

	local lines = {
		"\x1b[96m" .. leftName .. "\x1b[0m@\x1b[96m" .. rightName,
		("-%s"):format(("-"):rep(math.max(0, #leftName + #rightName - 1))),
	}

	local function addLine(name, value)
		lines[#lines + 1] = "\x1b[96m" .. name .. "\x1b[0m: " .. value
	end

	addLine("OS", "CloverOS " .. tostring(system.versionString()))
	addLine("Uptime", formatTime(math.floor(system.uptime() or 0)))
	addLine("Runtime", "CraftOS " .. tostring(kernel.computer.version()))
	addLine("Lua", _VERSION)
	addLine("CC Version", tostring(kernel.computer.version()))
	addLine("Resolution", table.concat({ term.getSize() }, "x"))

	local stat = fs.stat and fs.stat("/") or nil
	if stat then
		addLine("Disk Space", formatBytes(stat.freeSpace) .. " / " .. formatBytes(stat.capacity))
	end

	if collectgarbage then
		addLine("Memory", formatBytes(collectgarbage("count") * 1024))
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "\x1b[40m   \x1b[41m   \x1b[42m   \x1b[43m   \x1b[44m   \x1b[45m   \x1b[46m   \x1b[47m   \x1b[0m"
	lines[#lines + 1] = "\x1b[100m   \x1b[101m   \x1b[102m   \x1b[103m   \x1b[104m   \x1b[105m   \x1b[106m   \x1b[107m   \x1b[0m"
	lines[#lines + 1] = ""

	local width = term.getSize() - 18
	for i = 1, math.max(#logo, #lines) do
		local right = trimAnsi(lines[i] or "", width)
		local row = (logo[i] or "                ") .. "  " .. right
		if i == 1 then
			io.write(row)
		else
			print(row)
		end
	end
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
    if not line then
      break
    end
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
  local dir = process.dir()
  local user = shellEnv.USER or "root"
  local host = shellEnv.HOSTNAME or "CloverOS"
  local cwd = dir
  if cwd == "" or cwd == "/" then
    cwd = "/"
  elseif ROOT and ROOT ~= "/" and cwd:sub(1, #ROOT) == ROOT then
    cwd = cwd:sub(#ROOT + 1)
    if cwd == "" then
      cwd = "/"
    end
  end
  local prompt = shellEnv.PS1 or "%u@%h:%w$ "
  prompt = prompt:gsub("%%u", user):gsub("%%h", host):gsub("%%w", cwd)
  return prompt
end
local function isKernelShutdownOrReboot()
  local status = kernel.status()
  return status.shutdownRequested or status.rebootRequested
end
