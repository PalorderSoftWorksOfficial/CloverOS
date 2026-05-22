-- /etc/passwd and login (Linux-style)
local M = {}

function M.load(fs, root)
  local users = {
    root = { uid = 0, gid = 0, home = "/root", shell = "/bin/sh", password = "root" },
  }
  local groups = {
    root = { gid = 0, members = { "root" } },
    users = { gid = 1000, members = {} },
  }

  local function parsePasswd()
    local path = root .. "/etc/passwd"
    if not fs.exists(path) then
      return
    end
    local h = fs.open(path, "r")
    if not h then
      return
    end
    users = {}
    while true do
      local line = h.readLine()
      if not line then
        break
      end
      local name, pass, uid, gid, _, home, shell =
        line:match("([^:]+):([^:]+):([^:]+):([^:]+):([^:]*):([^:]+):([^:]+)")
      if name then
        users[name] = {
          uid = tonumber(uid),
          gid = tonumber(gid),
          home = home,
          shell = shell or "/bin/sh",
          password = pass,
        }
      end
    end
    h.close()
  end

  local function parseGroup()
    local path = root .. "/etc/group"
    if not fs.exists(path) then
      return
    end
    local h = fs.open(path, "r")
    if not h then
      return
    end
    groups = {}
    while true do
      local line = h.readLine()
      if not line then
        break
      end
      local name, _, gid, members = line:match("([^:]+):([^:]+):([^:]+):(.*)")
      if name then
        groups[name] = { gid = tonumber(gid), members = {} }
        for m in (members or ""):gmatch("[^,]+") do
          table.insert(groups[name].members, m)
        end
      end
    end
    h.close()
  end

  local function savePasswd()
    local h = fs.open(root .. "/etc/passwd", "w")
    if not h then
      return
    end
    for name, u in pairs(users) do
      h.write(("%s:%s:%d:%d::%s:%s\n"):format(name, u.password, u.uid, u.gid, u.home, u.shell))
    end
    h.close()
  end

  local function saveGroup()
    local h = fs.open(root .. "/etc/group", "w")
    if not h then
      return
    end
    for name, g in pairs(groups) do
      h.write(name .. ":x:" .. g.gid .. ":" .. table.concat(g.members, ",") .. "\n")
    end
    h.close()
  end

  local function ensureDir(path)
    if not fs.exists(path) then
      fs.makeDir(path)
    end
  end

  parsePasswd()
  parseGroup()

  return {
    users = users,
    groups = groups,
    load = function()
      parsePasswd()
      parseGroup()
    end,
    saveUsers = savePasswd,
    saveGroups = saveGroup,
    ensureDirectory = ensureDir,
  }
end

function M.login(ctx)
  local fs, kernel, Terminal, colors, readInput = ctx.fs, ctx.kernel, ctx.Terminal, ctx.colors, ctx.readInput
  local acc, root = ctx.accounts, ctx.root
  acc.load()

  if not next(acc.users) then
    Terminal.clear()
    Terminal.centerText(2, "CloverOS first boot", colors.white, colors.blue)
    Terminal.print("")
    local username = readInput("New login name: ")
    local password = readInput("New password: ", true)
    acc.users[username] = {
      uid = 1000,
      gid = 1000,
      home = "/home/" .. username,
      shell = "/bin/sh",
      password = password,
    }
    acc.saveUsers()
    acc.groups.users = acc.groups.users or { gid = 1000, members = {} }
    acc.groups.users.members = { username }
    acc.saveGroups()
    ctx.currentUser = username
    acc.ensureDirectory(acc.users[username].home)
    kernel.info("Created user: " .. username)
    return username
  end

  while true do
    Terminal.clear()
    kernel.ui.centerText(2, kernel.system.hostname() .. " login:")
    Terminal.print("")
    local username = readInput("login: ")
    local password = readInput("Password: ", true)
    if acc.users[username] and acc.users[username].password == password then
      ctx.currentUser = username
      acc.ensureDirectory(acc.users[username].home)
      return username
    end
    Terminal.print("Login incorrect")
    kernel.sleep(0.8)
  end
end

return M
