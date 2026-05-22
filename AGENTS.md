# AGENTS.md — CloverOS

## Project scope

CloverOS is a Lua-based operating system for CC:Tweaked and CraftOS. The repository contains the boot flow, shell/runtime code, installer, commands, apps, configs, and platform-specific assets.

## Repository map

- `startup.lua` — entry point that locates the CloverOS root, loads `CloverOS_API.lua`, and starts boot flow.
- `CloverOS_API.lua` — shared API expected to be available to the kernel and runtime.
- `CloverOS_OS.lua` — main OS/shell runtime.
- `boot/` — boot and kernel code.
- `bin/` — command executables.
- `apps/` — user-facing applications.
- `etc/` — configuration, man pages, package metadata, and related runtime files.
- `netinstall.lua` — network installer used to deploy CloverOS files.
- `files.manifest` — file list used by the installer for full installs.
- `craftos_env_test.lua` — environment compatibility check.
- `Phoenix/` — Phoenix OS reference material used as a shell and boot architecture guide.
- `CC-tweaked/`, `CraftOS-PC/`, `CraftOS-PC-Accelerated/` — platform-specific assets or integrations.
- `sync.sh` — repository sync helper.

## Working rules

### Keep CC:Tweaked / CraftOS compatibility
- Prefer APIs and patterns available in CC:Tweaked / CraftOS.
- Avoid assumptions about native OS features that do not exist in the target runtime.
- Use Phoenix OS as a reference for shell and boot architecture while preserving CloverOS-specific boot discovery and runtime behavior.
- Treat filesystem paths, drives, and mounts as part of the runtime contract.

### Preserve boot and install behavior
- Do not break `startup.lua` root discovery.
- Do not rename or move boot-critical files without updating every reference.
- If a new file must be installed, update the installer and any manifest or edition-specific file lists.
- Keep the installer paths working for both CDN and raw GitHub sources.

### Lua style
- Keep code small and explicit.
- Use defensive checks around `fs`, `shell`, `http`, `settings`, `term`, and peripheral calls.
- Prefer readable local helper functions over deeply nested logic.
- When editing existing files, match the surrounding style rather than rewriting the whole file.

### File changes
- If a file is consumed by the installer, make sure the manifest and edition lists stay in sync.
- If a change affects startup, boot, login, package loading, or shell initialization, test the full path from launch to UI.
- Keep new assets in the established directory structure instead of scattering files at the root.

## Validation checklist

Before considering a change complete:

1. Confirm the project still boots through `startup.lua`.
2. Confirm the kernel and shell can load from the expected CloverOS root.
3. Run the CraftOS compatibility check if the change touches environment setup.
4. Test installer paths if files, editions, or manifests changed.
5. Verify new commands or apps are reachable from the expected directory and naming scheme.

## Practical notes

- This project is not a generic Lua library; runtime expectations matter.
- Keep error messages clear and actionable.
- Do not introduce external dependencies unless the project already relies on them.
- Do not remove legacy paths unless the repo has been updated everywhere they are referenced.

## When in doubt

- Inspect the existing file that is closest to the change.
- Preserve behavior first, then improve structure.
- Make the smallest change that solves the problem.
