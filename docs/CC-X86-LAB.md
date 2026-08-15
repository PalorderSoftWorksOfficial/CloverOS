# CC-X86 Lab

CloverOS and CC-X86 are companion projects.

CloverOS provides the operating-system environment and user-facing tools. CC-X86 provides the low-level 32-bit x86 machine, firmware boundary, virtual devices, and debugging environment.

## Install CC-X86

Place the CC-X86 repository at `/ccx86` on the ComputerCraft computer.

The project can then be launched from its own directory with:

```text
main.lua examples/add.bin
```

## CloverOS workflow

Use the CC-X86 Lab launcher from the CloverOS applications directory to open the emulator with the example guest program.

The launcher is intentionally a thin wrapper. It does not copy emulator internals into CloverOS and it does not make CloverOS depend on the emulator being installed.

## Why this exists

The long-term goal is to make CloverOS usable as an experimental 32-bit operating-system target. CC-X86 is the machine used to develop and test that target.

The separation keeps both projects useful independently:

- CloverOS can continue improving as a native CC:Tweaked operating system.
- CC-X86 can continue improving as an emulator and virtual hardware project.

## Future integration

The current custom CPUID hypervisor leaf identifies the machine as `CLOVEROS-X86`.

Future work can add boot media, disk devices, interrupt delivery, protected mode, paging, and an actual CloverOS x86 bootstrap without requiring the emulator to know CloverOS application internals.
