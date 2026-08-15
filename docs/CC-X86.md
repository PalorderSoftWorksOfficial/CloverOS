# CC:X86 integration

CC-X86 is a companion project for CloverOS: it provides a WIP 32-bit x86 machine that can run inside CC:Tweaked.

CloverOS is the user-facing operating-system environment, while CC-X86 is the low-level CPU and hardware laboratory. Keeping the projects separate lets either project evolve without turning the other into a hard dependency.

## Projects

- CC-X86: https://github.com/PalorderSoftWorksOfficial/CC-x86
- CloverOS: https://github.com/PalorderSoftWorksOfficial/CloverOS

## Running from CloverOS

A future CloverOS app should launch CC-X86 as an optional development tool when its files are installed locally. The CC-X86 repository remains independently runnable from CraftOS so it is also useful without CloverOS.

## Why this exists

The ComputerCraft community is interested in ambitious emulation and operating-system projects because they turn the tiny in-game computer into a platform for experiments. CC-X86 provides the CPU side; CloverOS provides a polished CC:Tweaked environment for presenting and managing those experiments.
