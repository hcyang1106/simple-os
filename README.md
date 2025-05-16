
# SimpleOS

SimpleOS is an OS implementation that is used to enhance my understanding of OS concepts.

  

---

  

## Toolchain Setup

  

To build and run the OS on MacOS, you’ll need the following:

  

| Tool | Purpose |

| `qemu-system-i386` | Emulates an x86 PC |

| `cmake` | Build configuration |

| `x86_64-elf-gcc` | Cross-compiler for x86 ELF |

| `x86_64-elf-gdb` | Cross-debugger to connect to QEMU (used for remote debugging) |

| `ld`, `as`, `objcopy`, `objdump`, `readelf` | Tools for ELF analysis and binary conversion |

  

> Installing `x86_64-elf-gcc` typically includes the full toolchain: assembler, linker, and ELF utilities.

  

---

  

## Disk Image Setup

  

### Disk 1 (Bootable)

  

- Created using `dd`

- Uses precise sector control for:

  - Boot (first 512 bytes)

  - Loader (second stage bootloader)

  - Kernel

  

### Write Script: `script/img-write-os`

  

This script automates writing contents into the disk images (using `dd`)

---

  

## Running QEMU (script/qemu-debug-osx.sh)

  

### Basic System Configuration

  

-  `qemu-system-i386`: Launches QEMU emulating a 32-bit x86 machine.

-  `-m 128M`: Allocates 128MB of memory to the virtual machine.

-  `-serial stdio`: Redirects the virtual machine's serial output to the host terminal.

- Useful for printing messages from OS.

---

  

### Attaching Disk Images

  

-  `-drive file=disk1.dmg,index=0,media=disk,format=raw`

Attaches the first virtual disk (containing the boot, loader, and kernel).

  

-  `-drive file=disk2.dmg,index=1,media=disk,format=raw`

Attaches a second virtual disk (for file system or user programs).

  

---

  

### Debug Mode

  

-  `-s`: Starts a GDB server on TCP port `1234`. Equivalent to `-gdb tcp::1234`.

-  `-S`: Pauses the CPU immediately after boot. Execution will not start until GDB sends a `continue` command.

  

> This is why the system will not automatically run bootloader when QEMU starts. You must connect with GDB and manually start execution.

  

---

  

## Debugging with GDB and VSCode

  

### Overview

  

- VSCode uses `x86_64-elf-gdb` as a cross-debugger.

- It connects to QEMU's GDB server at `localhost:1234`.

- ELF files are loaded to provide:

  - Symbol information

  - Debug info (DWARF sections)

  

---

  

### Debugging Launch Flow

  

1. Write disk images and run QEMU.

2. Press the **Debug** button in VSCode.

3. VSCode launches `x86_64-elf-gdb` and connects to QEMU.

4. GDB pauses at `0x7C00` (bootloader entry point).

5. GDB loads ELF files and debug info using `program` and `add-symbol-file`.

6. You can now:

- Step through source or assembly

- Inspect memory, registers, and stack

- Set and hit breakpoints

  

---

  

## Boot

  

![Boot Image](images/boot.jpeg)

  

The **Boot** code resides in the very first sector of the disk (sector 0) and is loaded by the BIOS to memory address `0x7C00` when the QEMU starts. This is the beginning of the OS boot sequence, running in **real mode (16-bit)**.

  

Since the CPU starts in real mode, the boot code uses `.code16` and `__asm__(".code16gcc")` (for c file) to tell the assembler to generate 16-bit instructions compatible with the initial CPU state.

  

The Boot stage performs two main tasks:

  

1.  **Loads the Loader from disk**

The boot code uses BIOS interrupts (e.g., `INT 13h`) to read sectors from disk into memory. Specifically, it loads the "Loader" program into physical memory at address `0x8000`.

  

2.  **Jumps to the Loader**

After loading, Boot uses a **function pointer** technique in C to jump to the Loader's entry point. For example:

  

````c

#define LOADER_START_ADDR 0x8000

  

void  boot_entry(void) {

((void (*)(void))LOADER_START_ADDR)(); // jump to loader code

}
````

---

### Ends with 0x55 and 0xAA

  

The final two bytes of the boot sector must be `0x55` followed by `0xAA`. This is a **BIOS requirement** to identify a valid boot sector.

  

BIOS will:

  

- Scan devices (e.g., hard disk, USB) looking for a bootable sector.

- Read the **first 512 bytes** of each device (the boot sector).

- Check the **last two bytes** of that sector:

- If they are `0x55AA`, BIOS considers it a valid boot sector and executes it.

- If not, BIOS skips the device and tries the next one.

  

Therefore, every boot sector must explicitly reserve space for this signature, as we can see in boot/start.S :

````asm

.byte 0x55, 0xAA
````

---  

### Build System Notes

  

To ensure that the linker places the boot code at the correct physical memory address (**`0x7C00`**) and that the boot sector is exactly **512 bytes**, the following CMake configurations are used:

  

#### 1. Source Ordering

  

Place `start.S`  **first** in the source list to ensure it becomes the entry point of the final binary:

  

````cmake

file(GLOB C_LIST "*.c" "*.h")

add_executable(${PROJECT_NAME} start.S ${C_LIST})

````

  

This guarantees that the start.S (boot) code is linked first and becomes the first code to execute.

  

#### 2. Linker Address Configuration

  

Set linker flags so that:

  

- The boot code starts at `0x7C00`, where the BIOS expects to load it.

- The `boot_end` section aligns at `0x7DFE` (just before `0x7E00`), leaving space for the `0x55AA` signature at the last two bytes.

  

````cmake

set(CMAKE_EXE_LINKER_FLAGS "-m elf_i386 -Ttext=0x7c00 --section-start boot_end=0x7dfe")

````

---

  

## Loader

  

![Subdirectory Image](images/loader.png)

  
  

The loader is composed of the following files:

  

-  `start.S`

-  `loader_16.c`

-  `loader_32.c`

-  `loader.h`

  

The loader is built as an ELF file, then converted into a `.bin` by post-build commands. This binary is then written to the correct disk sector by an image creation script (using `script/img-write-os`).

---

### Execution Overview

  

The loader consists of two main parts:

  

-  `loader_16.c`: Runs in **real mode**, performs **memory detection** (using BIOS interrupt)

-  `loader_32.c`: Runs in **protected mode**, **enables paging**, and **loads the kernel**

  

It begins execution in 16-bit mode and switches to 32-bit protected mode after completing basic memory detection.

---

### loader_16.c (Real Mode)
  

#### 1. Show Startup Message

  

- Uses BIOS interrupt `INT 10h` to print a message to the screen

- Displays one character at a time using `INT 10h`

  

#### 2. Detect Usable Memory

  

- Calls BIOS interrupt `INT 15h`.

- Stores memory map entries into a `boot_info_t` structure

- Loops through all available entries, stopping when BIOS indicates completion

- 0 - Around 600KB, 1MB - 128MB are available memory

- Others parts of memory are reserve for video memory and BIOS

  

#### 3. Entering Protected Mode

  

The `enter_protect_mode()` function transitions the CPU from **real mode** to **protected mode**. This involves **enabling the A20 line**, **setting up the GDT**, **flipping the PE bit in `CR0`**, and **performing a far jump to 32-bit code**.

  

Below is the code:

  

````c

static  void  enter_protect_mode(void) {

// 1. Disable interrupts to prevent unexpected behavior
// during the mode switch

cli();

  

// 2. Enable the A20 line (allow addressing beyond 1MB)

// A20 address line wraparound occurs in x86 real-mode when the A20 line is disabled, 
// causing addresses above 1 MB (e.g., 0x100000) to wrap around to low memory (e.g., 0x00000)
// for 8086 compatibility (since there are only 20 address lines in 8086). 
// Enable A20 and switch to protected mode to access 1 MB–128 MB.

uint8_t v = inb(0x92);

outb(0x92, v | 0x2);

  

// 3. Load the Global Descriptor Table (GDT)
// The GDT defines memory segments for protected mode

lgdt((uint32_t)gdt_table, sizeof(gdt_table));

  

// 4. Enable protected mode
// Set the PE (Protection Enable) bit in control register CR0

uint32_t cr0 = read_cr0();

write_cr0(cr0 | (1 << 0));

  

// 5. Performs a far jump to clear the instruction pipeline
// This is necessary because enabling PE doesn't immediately switch to protected mode
// The far jump flushes the CPU pipeline and sets the new CS value
// Jump to assembly since we need to set segment registers

far_jump(8, (uint32_t)protect_mode_entry);

}

````
---
### GDT Table Definition

  

The Global Descriptor Table (GDT) is an array of **64-bit** segment descriptors used in **protected mode** to define memory segments.

  

In the loader, the GDT is defined as follows:

  

````c

uint16_t gdt_table[][4] = {

// Each descriptor is 64 bits = 4 × 16-bit words

{0, 0 , 0, 0}, // Null descriptor (mandatory)

{0xFFFF, 0x0000, 0x9A00, 0x00CF}, // Code segment: base=0x00000000, limit=0xFFFFF, DPL=0, exec/read

{0xFFFF, 0x0000, 0x9200, 0x00CF}, // Data segment: base=0x00000000, limit=0xFFFFF, DPL=0, read/write

};

````

---

### Segment Setup in Protected Mode

  

After enabling protected mode via CR0 and doing a far jump, the CPU switches to protected mode, but all **data segment registers (`ds`, `ss`, `es`, etc.) are still undefined or zero** unless explicitly initialized.

  

In `protect_mode_entry`, the goal is to initialize all relevant segment registers to use a proper **data segment descriptor** from the GDT.

  

````asm

protect_mode_entry:

// Set all data segment registers to use selector 0x10

mov $16, %ax ; 0x10 = selector for data segment in GDT (index 2 × 8)

mov %ax, %ds ; Set data segment

mov %ax, %ss ; Set stack segment

mov %ax, %es ; Extra segment (used in string ops)

mov %ax, %fs ; FS/GS available for user/kernel-specific storage

mov %ax, %gs

  

// Far jump to reload CS with 0x08 (code segment selector) and start loading kernel

jmp $8, $load_kernel ; 0x08 = code segment selector (index 1 × 8)

````

---

###  loader_32.c — Load and Start the Kernel

  

This file represents the 32-bit stage of the loader, which is entered after switching into protected mode. It is responsible for:

  

- Reading the kernel from disk

- Parsing the ELF file

- Setting up temporary paging

- Jumping to the kernel entry point

#### 1. `read_disk(sector, sector_count, buf)`

  

Reads sectors from disk into memory using **LBA mode**:

  

- This reads the kernel binary from disk sector 100 into memory at `SYS_KERNEL_LOAD_ADDR`.

  

#### 2. `reload_elf_file(file_buffer)`

  

Parses the kernel ELF file and loads each segment defined in the **Program Header Table**:

  

- Validates the ELF magic number (`0x7F 'E' 'L' 'F'`)

- Iterates through program headers

- For each `PT_LOAD` segment:

- Copies file contents from `p_offset` to `p_paddr`

- Zeroes out `.bss` using `p_memsz - p_filesz`

  

Returns the **entry point address** from the ELF header.

  

> This is how the loader finds the correct entry address, instead of assuming `0x10000` (set by kernel.lds).

  

#### 3. `enable_page_mode()`

  

Sets up a simple one-entry page directory that maps virtual memory directly to physical memory (identity map):

  

- Uses **4MB pages**

- Sets CR3 to the aligned page directory (note that page directory is aligned to 4096)

- Enables `CR0.PG` to activate paging

  

> This is a minimal paging setup used only in the loader; the kernel will later create its own page tables, and use 4KB pages as well.

  

#### 4. `Jumps to kernel`

  

Jumps to the kernel entry point with `boot_info` as argument:

  

````c

((void (*)(boot_info_t *))kernel_entry)(&boot_info);

````

  

---

  

## Mutex

1. Initialization: The mutex is set to be unlocked with no owner, and a list is created to hold tasks that might have to wait for the lock.

  

2. Locking: When a task tries to lock the mutex, if no one owns it, the task becomes the owner. If someone else already owns the mutex, the task is put on a waiting list until the mutex becomes available.

  

3. Unlocking: When the owner releases the mutex, if other tasks are waiting, the first one in line is given ownership of the mutex and allowed to continue.

  

---

  

## Semaphore

1. Initialization: The semaphore is initialized with a specific count value, which represents the number of tasks that can proceed without waiting. A list is created to hold tasks that may need to wait.

  

2. Waiting (sem_wait): When a task wants to proceed, it checks if the semaphore count is greater than zero. If it is, the task decreases the count and continues. If the count is zero, the task is put on a waiting list, meaning it has to wait until it’s notified (when resources become available).

  

3. Notifying (sem_notify): When a resource is freed or made available, the first task in the waiting list is notified and allowed to proceed. If no tasks are waiting, the semaphore count is increased, allowing future tasks to continue without waiting.

  

---

  

## Task Structure

1. state: This enumerates the different states a task can be in, such as TASK_CREATED, TASK_RUNNING, TASK_SLEEP, etc. It tracks the current state of the task.

  

2. status: This holds a status value for the task, representing exit code.

  

3. pid: A unique identifier for the task, often called the process ID.

  

4. name[TASK_NAME_SIZE]: A character array that stores the task’s name, making it easier to identify or debug.

  

5. parent: A pointer to the parent task structure. This establishes a parent-child relationship between tasks.

  

6. tss: The Task State Segment (TSS) is a structure used by hardware for task switching. It holds various CPU register values for a task.

  

7. tss_sel: This is the TSS selector, used to switch between tasks relying on hardware-assisted task switching.

  

8. curr_tick: This is a countdown timer for the task. Once it reaches 0, it resets, triggering to reschedule.

  

9. sleep_tick: Used to track how long the task should remain in a sleep state. When the counter reaches zero, the task can wake up.

  

10. all_node: A list node that links this task to a global list of all tasks, making task management easier.

  

11. run_node: A list node used to manage the task in different lists (e.g., ready list, sleep list). This allows the task to move between states like "ready" or "sleeping."

  

---