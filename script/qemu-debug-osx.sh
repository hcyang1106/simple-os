# This file is for MACOS
# -serial stdio is used to redirect the output to serial to standard output (terminal)
qemu-system-i386  -m 128M -s -S -serial stdio -drive file=disk1.dmg,index=0,media=disk,format=raw -drive file=disk2.dmg,index=1,media=disk,format=raw -d pcall,page,mmu,cpu_reset,guest_errors,page,trace:ps2_keyboard_set_translation


# About BIOS

# What does BIOS do exactly? (from ChatGPT)
# POST (Power-On Self-Test)
# Checks RAM, CPU, keyboard, display, etc.

# Initializes hardware
# Basic drivers for keyboard, video, disk, etc.

# Finds boot device
# (e.g. hard drive, USB, CD-ROM)

# Loads bootloader
# Reads first 512 bytes (MBR) from disk → jumps to it
# It follows the device order sets in BIOS, and examine each until 0x55 0xAA is found

# Hands off control
# to your bootloader (e.g., GRUB) → which then loads your OS

# Modern BIOS is stored in flash (instead of ROM), which can be updated


# If qemu starts from boot, it runs in a 16-bit mode
# If qemu uses -kernel option (which loads the kernel into memory in advance),
# 1. It parses the elf file and sets the EIP register
# 2. (My Guess) It is probably set to protected mode/long mode (64 bit) first,
#    depending on the data specified in elf file. => ELF indeed stores which mode it runs in 

# Intel i386 features
# 1. 32-bit CPU (regs, memory buses)
# 2. Supports multitasking using TSS
# 3. Supports protected mode, but also downward compats real mode (16-bit)
# 4. Support paging
# 5. Supports segmentation => segmentation = base & bounds + divide process mem into several sections

# Problem of base and bounds: 1. Hard to decide the memory for a process 2. process mem has to be cont.
# Problem of segmentation: external fragmentation (space released, but new segment couldn't fit in)

