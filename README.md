# CloverOS

An Operating System for CC:Tweaked and CraftOS

---

## About CloverOS

CloverOS is a custom Minecraft operating system designed for the CC:Tweaked mod and CraftOS.
It draws inspiration from Minux and Windows 10/11, combining a lightweight structure with a modern desktop-oriented experience.

CloverOS is a complete rewrite built to feel like a desktop environment inside Minecraft.

---

## Features

- Windows-style interface and experience
- Lightweight and optimized for in-game performance
- Fully compatible with CC:Tweaked and CraftOS
- Modular design allowing easy expansion and updates
- Open for community feedback and contributions

---

## CC:X86 hardware laboratory

CloverOS is also the user-facing companion to **CC:X86**, a separate WIP 32-bit x86 emulator that runs inside CC:Tweaked.

The relationship is intentionally simple:

- **CloverOS** provides the desktop environment, tooling, installers, and presentation layer.
- **CC:X86** provides the CPU, memory, firmware, debugging, and future virtual hardware experiments.

This lets people use CloverOS without installing an emulator while still giving systems programmers a serious low-level project to experiment with.

CC:X86 repository:
https://github.com/PalorderSoftWorksOfficial/CC-x86

CC:X86 documentation:
https://github.com/PalorderSoftWorksOfficial/CC-x86/blob/main/docs/REDDIT_PITCH.md

---

## Installation

CDN URL:
```lua
https://endpoint.palorderhosting.net
```

To install CloverOS, open an Advanced Computer or a CraftOS terminal in Minecraft and enter:

```lua
wget run https://endpoint.palorderhosting.net/netinstall.lua
```

The installer will automatically download and set up CloverOS.

For CC:Tweaked deployments, use the recommended configured mod settings and ensure the computer and floppy space limits are large enough for your installation.

---

## Contributing

Contributions are welcome and encouraged.

1. Fork the repository.
2. Make your changes.
3. Test them in CC:Tweaked or the applicable project environment.
4. Submit a pull request.

For emulator-oriented work, contribute to the CC:X86 repository directly so the CPU and OS projects keep clear ownership boundaries.

---

## Credits and Inspiration

- Inspired by Minux and Windows 10/11
- Developed by PalorderSoftworksOfficial, Comso and perplexed, with more contributors to be announced

---

## Final Notes

CloverOS is an ongoing project and continues to evolve with new updates, improvements, and community feedback.

If you encounter bugs or have suggestions, open an issue on GitHub.
