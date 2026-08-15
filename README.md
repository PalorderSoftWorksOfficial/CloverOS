# CloverOS

An Operating System for CC:Tweaked and CraftOS

---

## About CloverOS

CloverOS is a custom Minecraft operating system designed for the CC:Tweaked mod and CraftOS.  
It draws inspiration from Minux and Windows 10/11, combining the lightweight structure of Minux with a modern and user-friendly design inspired by Windows.

CloverOS is a complete rewrite built to feel like a desktop environment inside Minecraft.  
Originally based on Minux concepts, it has since been redesigned and reimplemented independently.

---

## Features

- Windows-style interface and experience  
- Lightweight and optimized for in-game performance  
- Fully compatible with CC:Tweaked and CraftOS  
- Modular design allowing easy expansion and updates  
- Open for community feedback and contributions

---

## CC-X86 Lab

CloverOS has a companion low-level project: [CC:X86](https://github.com/PalorderSoftWorksOfficial/CC-x86).

CC:X86 is a WIP 32-bit x86 emulator for CC:Tweaked. It provides the virtual CPU, memory, firmware, port I/O, and debugging environment that can eventually be used to develop a CloverOS x86 target.

CloverOS stays useful as a native CC:Tweaked operating system, while CC:X86 stays useful as an independent emulator and virtual-hardware project. The two projects share an experimental target without becoming tightly coupled.

The CloverOS repository includes an `apps/ccx86_lab.lua` launcher and `docs/CC-X86-LAB.md` for the integration workflow.

---

## Installation
CDN URL:
```lua
https://endpoint.palorderhosting.net
```
To install CloverOS, open an Advanced Computer (or a CraftOS terminal) in Minecraft and enter the following command:

```lua
wget run https://endpoint.palorderhosting.net/netinstall.lua
```

The installer will automatically download and set up CloverOS, but you may need to modify the CC:Tweaked server configuration for large installations.

---

## Contributing

Contributions are welcome and encouraged!  
If you want to help improve CloverOS, follow these steps:

1. Fork the repository.  
2. Make your changes or improvements.  
3. Submit a pull request for review.

If you enjoy using CloverOS, consider giving the project a star to show your support.

---

## Credits and Inspiration

- Inspired by: Minux, Windows 10/11  
- Developed by: PalorderSoftworksOfficial, Comso and perplexed. (More contributors to be announced later.)

---

## Final Notes

CloverOS is an ongoing project and continues to evolve with new updates, improvements, and features.  
If you encounter bugs, have suggestions, or want to share feedback, please open an issue on GitHub.

Thank you for using CloverOS.
