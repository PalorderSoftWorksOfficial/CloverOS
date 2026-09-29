# CloverOS

An operating system environment for CC:Tweaked and CraftOS, with a real
shell, user system, package manager, and graphical desktop.

Current release: **2.1 "Numbat"** (see `etc/version.lua`).

---

## Quick start

In Minecraft on an Advanced Computer (HTTP enabled):

```
wget run https://raw.githubusercontent.com/PalorderSoftWorksOfficial/CloverOS/main/install.lua
```

or offline, from a repository checkout on a disk drive:

```
install
```

The installer verifies every file it copies, writes an install status file,
and reboots into CloverOS. CloverOS then starts automatically on every boot.

## First boot

1. First-run setup: create your user (and optionally a root password).
2. Log in.
3. The GNOME-style desktop starts: a top bar with Activities, the clock and
   your user menu, a window list, and an application grid.

If the GUI cannot start, CloverOS falls back to a full text-mode shell
automatically — nothing is lost.

## The desktop

From the graphical login the desktop starts on its own. From the text shell,
type `cloveros`:

```
cloveros            start the desktop
cloveros --apps     list the desktop applications
cloveros --version  print the version
cloveros --help     the full option list
```

`cloveros` starts exactly the same session the graphical login does, so a
text-mode machine can drop into the desktop at any time. It refuses to run
when the shell is captured or piped, because a desktop needs the whole
terminal.

| Key | Action |
| --- | --- |
| `F1`–`F4` | terminal, files, settings, system information |
| `F5` | Activities overview (app grid, window switcher, search) |
| `F6` / `F7` | snap the focused window left or right |
| `F8` | maximise or restore the focused window |
| `F10` | log out |
| `alt+tab` | cycle between open windows |
| `ctrl+alt+t` | open a terminal window |
| `escape` | close a menu or the overview |

The top bar menus open applications, the session and system actions; the
status area shows the peripherals the kernel found.

The GUI is built on the vendored MC-ImGui (MIT) layer. Windows support
minimize/close, focus, live edge-snapping while dragging (top = maximize,
sides = half-tile) and double-click the title bar to maximize/restore.

## Shell

A bash-style shell with pipes (`|`), redirection (`>`, `>>`, `<`),
sequencing (`;`, `&&`, `||`), variables (`$NAME`, `${NAME}`, `$?`),
tilde and glob expansion (`*`, `?`, `[..]`), aliases, history (`!N`),
and tab completion.

Builtins: `help exit logout clear pwd cd ls cat echo history whoami id
groups hostname date time uptime touch mkdir rm cp mv chmod chown grep
head tail wc sort which sleep stat export unset env neofetch man edit
useradd userdel passwd su sudo apt alias unalias run shutdown reboot dmesg
service versions`.

External commands live in `bin/`. Package operations use the apt-style
interface: `apt list`, `apt search`, `apt info <pkg>`, `apt depends <pkg>`,
`apt install <pkg>`, `apt remove <pkg>`, `apt update`, `apt upgrade`,
`apt autoremove`, `apt verify`.

## Users, sudo, and permissions

- Users live in `/etc/clover/users.db`; passwords are stored as salted
  SHA-256 digests (legacy digests are upgraded on successful login).
- The first user created during first-run setup joins the `sudo` group.
- `sudo <cmd>` elevates for five minutes (password on stdin via `sudo -S`,
  like the real thing); `groups`, `useradd`, `userdel`, `passwd`, and
  `chmod` manage accounts and file modes.
- `/etc` is root-owned: unprivileged writes are denied.

## Installing

The installer is a Linux-style program: it builds a plan, asks for anything
missing, copies and verifies the files, writes the configuration an
installed system needs, and logs everything it did.

```
install                          guided installation
install /disk                    install to a mounted disk
install --local                  install from local repository files
install --net                    install from GitHub (requires HTTP)
install --no-prompt              unattended, with defaults
install --taskset fun            also install fortune, cowsay and trains
install verify /cloveros         check installed files against the manifest
install status /cloveros         print what is installed
install disks                    list installation targets
install tasks                    list the available task sets
install --help                   every option
```

Task sets are `minimal`, `terminal`, `utilities`, `desktop`, `fun` and
`development`. An installation of type `erase` needs `--erase-data`, and
`--dry-run` prints the plan without writing anything.

What an installation writes:

```
etc/fstab                          filesystem table
etc/clover/mounts.cfg              mount layout
etc/clover/install.cfg             installation record
var/lib/install-manifest.sha256    integrity manifest
var/lib/install-status.txt         status of the last installation
var/log/install.log                installation log
```

`install verify` compares every installed file against the manifest and
reports what is missing or changed.

## Architecture

```
startup.lua          CraftOS entrypoint; locates the installation
boot/loader.lua      bootloader: root discovery, kernel loading
boot/kernel.lua      kernel: logging, journal, services, config, apps
CloverOS_OS.lua      first-run setup, login, session/GUI orchestration
runtime/paths.lua    the filesystem layout
runtime/users.lua    accounts, groups, authentication
runtime/hash.lua     SHA-256, passwords, package checksums
runtime/shell.lua    the shell, builtins and the `cloveros` command
runtime/packages.lua apt-style package manager
runtime/textui.lua   text-mode UI toolkit (login screen, menus)
runtime/gui.lua      window manager over MC-ImGui
runtime/panel.lua    the GNOME top bar
runtime/overview.lua Activities overview and the app grid
runtime/launcher.lua shared desktop session entry point
runtime/desktop.lua  the GNOME shell: panel + overview + windows
libs/mc-imgui.lua    vendored MC-ImGui (MIT) behind runtime/gui.lua
apps/                desktop applications
bin/                 command-line programs
etc/                 motd, man pages, package catalog
tests/               CraftOS-PC test suites
experimental/        x86/RISC-V/CC-X86 experiments (not part of native boot)
```

`runtime/launcher.lua` is the single entry point to a desktop session: the
graphical login, the `cloveros` shell command and the settings app all go
through it, so there is exactly one way a desktop can start.

The experimental x86/amd64/RISC-V work is fully isolated from the native
boot path and is never loaded by `startup.lua`.

## Testing

CraftOS-PC is the primary test environment. With CraftOS-PC installed,
run from the repository root (Git Bash on Windows):

```
bash tests/run_tests.sh
```

Seven suites run headless: installer completeness, syntax validation of the
whole boot dependency tree, runtime modules (paths/users/packages/shell),
the real boot path with scripted setup+login+desktop, reboot persistence,
text-mode boot, and a GUI smoke test (window manager, focus, apps).

There is also a host-side harness (`tests/host/`) that runs the same suites
under Node + fengari with an in-memory CraftOS shim — no Minecraft or
CraftOS-PC needed:

```
npm install --prefix /tmp/luatool fengari
NODE_PATH=/tmp/luatool/node_modules node tests/host/run.js all
```

Suites: `all hash manifest syntax install install_tasks module shell2 gnome
gui boot boot_text`. The `manifest` suite keeps the installer's file lists in
step with the repository, and the runner enforces a Lua 5.2 syntax gate over
every repo `.lua` file (CC:Tweaked compatibility).
