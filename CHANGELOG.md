# CloverOS changelog

## 3.0 "Mandrill"

The networking and services release. CloverOS machines stop being islands:
they run services, talk to each other, and serve packages to one another.

### Init system

- `runtime/init.lua` manages session units the systemd way: dependencies
  (`after`), weak dependencies (`wants`), targets, and a default target
  (`multi-user.target`, `graphical.target`). A dependency cycle is reported,
  never hung; a failed `wants` never fails its target.
- `systemctl` controls units: list-units, status, start/stop/restart,
  enable/disable, is-active/is-enabled, set-default. Enable state persists
  in `/etc/clover/init.cfg`.
- `journalctl` queries the kernel journal with `--unit=`, `--level=` and
  `--lines=` filters.
- Text sessions bring their units up at boot through the default target.

### Networking

- `runtime/ssh.lua` is a rednet remote shell: `systemctl start sshd` serves
  authenticated sessions (salted SHA-256 through the real user database,
  failed logins journaled, five-minute idle timeout), and `ssh <id> <cmd>`
  runs one command remotely with output streamed back.
- `aptserver` publishes the local package catalog over rednet; clients add
  it with `apt add-source rednet <computer id>`. The same sha256 integrity
  rules apply as for GitHub sources.

### Desktop

- Notifications: toasts, a panel bell with an unread count, a notification
  center, do-not-disturb, hardware hotplug and apt results journaled.
- Quick Settings: DND, light/dark, accent, rednet/GPS/volume toggles.
- Per-user theming: light/dark, six accents, pattern and `.nfp` wallpapers.
- New apps: Image Viewer, Clocks, Media Player, Calculator, System Monitor,
  Notes (per-user, autosaves).

### Platform

- cloverd serves hardware events to text sessions, degrading gracefully on
  hosts without `os.queueEvents` (CraftOS-PC 1.9).
- The hardware layer (`runtime/system.lua`) binds the panel and commands to
  real peripherals, duck-typed, with persisted state.
- Per-user isolation (`runtime/access.lua`), apt remote repositories with
  digest verification, and the GNOME desktop rewrite landed across 2.x.

## 2.1 "Numbat"

- GNOME-style desktop: panel, Activities overview, window manager with
  snapping, graphical login, `cloveros` command.
- bash-style shell: pipes, redirection, sequencing, variables, globs,
  aliases, history, tab completion.
- apt-style package manager with task-set installation and verification.
- Users, sudo, octal file permissions.

## 2.0

- First Lua rewrite: boot loader, kernel with services and journal, user
  accounts, text shell, installer with local and network modes.
