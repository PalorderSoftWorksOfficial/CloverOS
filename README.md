# CloverOS

GNU/Linux-style operating environment for **CC:Tweaked** and CraftOS-PC, built on the CloverOS kernel API.

---

## About

CloverOS runs inside Minecraft computers as a full Unix-like environment:

- FHS layout (`/bin`, `/etc`, `/home`, `/proc`, `/var`, …)
- `login` → interactive `/bin/sh` with POSIX-style builtins
- `apt`, `man`, `useradd`, `passwd`, `sudo`, `dmesg`, `journalctl`, and `/bin` programs
- Kernel API: `kernel.fs`, `kernel.process`, `kernel.input`, `kernel.boot`, …

Boot chain: `startup.lua` → `boot/kernel.lua` → `os/init.lua` → shell.

---

## Installation

CDN URL:

```text
https://endpoint.palorderhosting.net
```

On an Advanced Computer:

```lua
wget run https://endpoint.palorderhosting.net/netinstall.lua
```

**CC:Tweaked settings:** set Computer Space Limit and Floppy Space Limit to `1073741824` in the mod config.

Default login after install: `root` / `root` (change with `passwd`).

---

## Features

- Multi-user `/etc/passwd` and `/etc/group`
- Package manager under `/etc/apt/packages`
- `/proc` pseudo-files (`version`, `meminfo`, `cpuinfo`, `uptime`)
- Compatible with existing `bin/*.exe` command wrappers

---

## Contributing

1. Fork the repository  
2. Make your changes  
3. Open a pull request  

---

## License

GPL-3.0 — see [LICENSE](LICENSE).
