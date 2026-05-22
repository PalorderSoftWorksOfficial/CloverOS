-- Linux FHS layout for CloverOS on CC:T
local M = {}

function M.findInstallRoot(fs)
  if fs.exists("/CloverOS_OS.lua") and fs.exists("/boot/kernel.lua") then
    return "/"
  end
  for i = 0, 99 do
    local root = "/disk" .. (i == 0 and "" or tostring(i))
    if fs.exists(root .. "/CloverOS_OS.lua") and fs.exists(root .. "/boot/kernel.lua") then
      return root
    end
  end
  return "/"
end

function M.ensureDir(fs, path)
  if not fs.exists(path) then
    fs.makeDir(path)
  end
end

function M.setup(fs, root, kernel)
  local dirs = {
    root .. "/bin",
    root .. "/sbin",
    root .. "/usr/bin",
    root .. "/usr/sbin",
    root .. "/usr/local/bin",
    root .. "/etc",
    root .. "/etc/apt",
    root .. "/etc/apt/packages",
    root .. "/etc/man",
    root .. "/etc/skel",
    root .. "/var",
    root .. "/var/log",
    root .. "/var/run",
    root .. "/var/tmp",
    root .. "/tmp",
    root .. "/home",
    root .. "/root",
    root .. "/proc",
    root .. "/sys",
    root .. "/dev",
    root .. "/mnt",
    root .. "/opt",
  }
  for _, d in ipairs(dirs) do
    M.ensureDir(fs, d)
  end

  local host = kernel.system.hostname()
  local osRelease = table.concat({
    "NAME=\"CloverOS\"",
    "PRETTY_NAME=\"CloverOS GNU/Linux\"",
    "ID=cloveros",
    "ID_LIKE=debian ubuntu",
    "VERSION=\"2.0\"",
    "VERSION_ID=\"2.0\"",
    "HOME_URL=\"https://github.com/PalorderSoftWorksOfficial/CloverOS\"",
  }, "\n") .. "\n"

  kernel.fs.writeIfMissing(root .. "/etc/os-release", osRelease)
  kernel.fs.writeIfMissing(root .. "/etc/hostname", host .. "\n")
  kernel.fs.writeIfMissing(root .. "/etc/hosts", "127.0.0.1\tlocalhost\n127.0.1.1\t" .. host .. "\n")
  kernel.fs.writeIfMissing(root .. "/etc/fstab", "# CloverOS fstab\n/dev/root\t/\text4\tdefaults\t0 1\n")
  kernel.fs.writeIfMissing(root .. "/etc/motd",
    "CloverOS GNU/Linux 2.0 — CC:Tweaked\nType 'help' or 'man <cmd>' for documentation.\n")
  kernel.fs.writeIfMissing(root .. "/etc/profile",
    'export PATH="' .. root .. '/bin:' .. root .. '/usr/bin:/bin:/usr/bin"\nexport PS1="%u@%h:%w$ "\nexport MANPATH="' .. root .. '/etc/man"\n')
  kernel.fs.writeIfMissing(root .. "/etc/passwd", "root:root:0:0:root:/root:/bin/sh\n")
  kernel.fs.writeIfMissing(root .. "/etc/group", "root:x:0:root\nusers:x:1000:\n")

  -- Virtual /proc entries (read via shell builtins)
  kernel.fs.writeIfMissing(root .. "/proc/version",
    "Linux version 2.0.0-cloveros (CloverOS) #1 CC:Tweaked\n")
  kernel.fs.writeIfMissing(root .. "/proc/cpuinfo", "processor\t: 0\nmodel name\t: ComputerCraft CPU\n")
  local free = fs.getFreeSpace and fs.getFreeSpace("/") or 65536
  kernel.fs.writeIfMissing(root .. "/proc/meminfo",
    "MemTotal:       1024 kB\nMemFree:        " .. tostring(math.floor(free / 1024)) .. " kB\n")
  kernel.fs.writeIfMissing(root .. "/proc/uptime", tostring(kernel.uptime()) .. " 0.00\n")
end

return M
