# CloverOS "Ultimate" — Ubuntu-Inspired GNOME Desktop Depth

Date: 2026-09-30
Status: Approved (user reviewed the plan; scope locked to all four feature groups)

## Understanding

CloverOS 2.1 already has the GNOME-style shell (panel, Activities overview,
window manager, snapping), a bash-style shell, apt with verified remote
repositories, users/sudo with per-user isolation, a hardware layer, and the
cloverd text-session daemon. The user asked to make it "the ultimate
CC:Tweaked operating system that is Ubuntu inspired." Through the
brainstorming dialogue they chose **GNOME desktop depth** as the focus and
then selected **all four feature groups** in a single pass, declining
further questions. Success is the visible Ubuntu feel: notifications,
theming, quick settings, and a fuller app set.

## License constraint

`Phoenix/` is proprietary (JackMacWindows, EULA). **No code is copied from
it**; it remains an architecture reference only, as AGENTS.md mandates. All
new code is CloverOS-native. Ideas that may be borrowed later, documented
but out of scope here: per-file permission manifests for apt packages.

## Architecture

New modules are small, unit-testable runtimes wired into the existing
desktop, following the established panel/overview pattern (pure modules
constructed with dependency tables, the desktop owns the single event
loop, apps are callback objects):

- `runtime/theme.lua` — palettes and wallpaper state.
- `runtime/notifications.lua` — the notification queue and policy.
- `runtime/panel.lua` — extended with the notification bell, the
  notification center dropdown, and the Quick Settings menu.
- `runtime/desktop.lua` — consumes both, owns toasts, replaces the
  hardcoded `wallpaper = colors.purple` with theme-driven drawing.
- New apps in `apps/`, registered in the desktop APPS list and the app
  grid: Image Viewer, Clocks, Media Player, Calculator.

## Features

### A. Theming and wallpapers (`runtime/theme.lua`)
- Palettes: Ubuntu-inspired light and dark (aubergine/orange accents) plus
  an accent color list.
- Wallpapers: solid colors, procedural patterns drawn with paintutils, and
  bundled `.nfp` images under `etc/clover/wallpapers/`.
- Persistence per user in `~/.config/clover/desktop.cfg` with root
  defaults, using the defensive-fs cfg style of `runtime/system.lua`.
- Settings app: Appearance section (mode, accent, wallpaper grid).
- Files app: "Set as Wallpaper" action on `.nfp` images.

### B. Notification center (`runtime/notifications.lua`)
- Queue capped at 20 (oldest dropped), `notify{app, title, body}`, expiry,
  do-not-disturb flag, `list()`/`clear()`.
- GNOME-style toasts slide in top-center for ~4 seconds, suppressed while
  DND is on; the panel shows a bell with an unread count; activating it
  opens the notification center dropdown.
- Producers: desktop/panel, hardware hotplug via `runtime/system.lua`,
  apt install/remove results, cloverd alerts. The desktop exposes
  `notify` to apps as the single seam.

### C. Quick Settings menu
- A panel menu right of the clock: DND toggle, light/dark toggle, rednet/
  network/GPS toggles bound to real `runtime/system.lua` state, a volume
  slider shown only when a speaker peripheral is attached (duck-typed),
  brightness support hidden gracefully where the host lacks it.
- Toggles flip real state and persist where applicable.

### D. New apps
- **Image Viewer** — open and step through `.nfp` images; integrates with
  Set-as-Wallpaper.
- **Clocks** — clock, stopwatch, countdown timer.
- **Media Player** — tones/jingles through a duck-typed speaker peripheral
  via `runtime/system.lua`; degrades to a clear message without hardware.
- **Calculator** — GNOME Calculator style, keyboard-driven.

## Error handling

Every module degrades: missing wallpaper files fall back to palette
patterns, missing speaker or brightness hardware hides controls, the
notification queue evicts rather than grows, and all fs/term calls keep
the defensive checks AGENTS.md requires. Nothing here may break the boot
path; the GUI suite must stay green before and after.

## Testing

- Host suites (Node + fengari shim): new `notify` and `theme` suites
  (queue cap, DND, expiry, fitting; load/save, fallbacks, drawing),
  Quick Settings toggle wiring in the gnome suite, app smoke checks,
  plus the full existing 17-suite run.
- CraftOS-PC (`bash tests/run_tests.sh`): GUI suite extended with a toast
  and Quick Settings smoke test; all 7 suites must pass.
- Installer/manifest sync: new files added to `install.lua` FILES,
  `tests/syntax_check.lua`, and the manifest suite; wallpapers under
  `etc/clover/wallpapers/`.

## Out of scope (next architectural cycles)

Init/service units, SSH-style remote shell, central apt repo server,
package-manifest permissions — the other three focus areas from the
brainstorm.
