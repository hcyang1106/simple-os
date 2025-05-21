
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

![Subdirectory Image](images/4MB_paging.png)

Sets up a simple one-entry page directory that maps virtual memory directly to physical memory (**identity map**), so that loader is able to continue running:

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

## Kernel

The kernel is the core component that takes over control after the loader finishes its job. It is entered in **32-bit protected mode**, and is responsible for initializing essential subsystems.

The kernel is compiled as an **ELF file** with a well-defined entry point (`_start` in `start.S`) and loaded into memory by the loader.

---

### Passing `boot_info` to `kernel_init`

The loader passes a pointer to the `boot_info_t` structure to the kernel's entry function (`_start`). This structure contains usable memory information, and we will further pass this pointer into `kernel_init` function.

At the end of loader, we do:
````c
((void (*)(boot_info_t *))kernel_entry)(&boot_info);
````

From Intel calling conventions, we know parameters (boot_info) and return address are pushed into the stack in order, so the stack looks like:

````c
↑ Higher Address

[ boot_info pointer ]
[ return address ] <- esp
````

After entering _start, we follow the conventions as well, pushing ebp register to stack,
moving esp to ebp, and we can fetch the parameter (boot_info) pushed previously:

````c
↑ Higher Address

[ boot_info pointer ]
[ return address ]
[ prev ebp ] <- current ebp/esp
````

Finally, to pass the parameter (boot_info) to `kernel_init`, we push it again to the stack so that in `kernel_init` it can fetch it using the calling conventions:

````c
↑ Higher Address

[ boot_info pointer ]
[ return address ]
[ prev ebp ] <- current ebp
[ boot_info pointer (eax) ] <- current esp
````

(Optional) In the code, it doesn't return to the caller function so we don't have to handle that part. However, following the conventions a function should clear the stack frame, which moves **esp** to **current ebp** and update ebp by popping the stack.

````c
mov %ebp, %esp
pop %ebp 
````

---

### GDT Overview
The Global Descriptor Table (GDT) is a data structure used in protected mode on x86 to define memory segments and privilege levels.

Each entry in the GDT is called a segment descriptor, which tells the CPU:

What range of memory it describes (base + limit)

What kind of access is allowed (code/data, read/write)

What privilege level is required (ring 0–3)

The CPU uses segment selectors (like cs, ds) to index into the GDT and load the correct descriptor.
___

### GDT Initialization (`init_gdt`)
This function initializes a larger, more complete GDT table than the earlier boot-time minimal GDT. It prepares the to support separate code/data segments for kernel.

---

### (Not Used) LDT Overview

<img src="images/LDT.png" width="500">

The **Local Descriptor Table (LDT)** is a per-process table that holds segment descriptors (like code and data segments) specific to a single process.

- Each process can have its own LDT to define private memory segments.
- The CPU has a special register called **LDTR**, which stores a **selector** pointing to an entry in the **GDT**.
- That GDT entry describes the **base address and size of the LDT**.

- When a segment register (like `cs`, `ds`, or `ss`) contains a **selector with the TI (Table Indicator) bit set to 1**, it tells the CPU to look up the descriptor in the **LDT**, not the GDT.

- The **selector to the LDT entry in the GDT is saved in the TSS (Task State Segment)**.

---

### Exceptions vs. Interrupts
Interrupts and exceptions are special control transfers that redirect the CPU to handle unusual conditions.

Interrupts are triggered by external, asynchronous events (e.g., keyboard input, timer tick).

Exceptions are triggered internally by the CPU during instruction execution (e.g., divide-by-zero, page fault).

Both use the **IDT** to determine how to handle the event — by jumping to the corresponding handler function defined in the IDT entry.

---

### IDT Overview

The **Interrupt Descriptor Table (IDT)** is a data structure used in x86 protected mode to define how the CPU should respond to **interrupts** and **exceptions**.

Each entry in the IDT tells the CPU:

Which **segment selector** to use (usually pointing to a code segment in the GDT).

What type of gate it is (interrupt gate, trap gate).

What privilege level (DPL) is required to trigger it.

---

### IDT Together with GDT

<img src="images/IDT_with_GDT.png" width="500">

The **Interrupt Descriptor Table (IDT)** doesn't work in isolation — it relies on the **Global Descriptor Table (GDT)** to define what memory segment the CPU should switch to when handling an interrupt or exception.

Each **IDT entry** includes a **segment selector**, which refers to an entry in the **GDT**, typically the **kernel code segment**:

````c
gate_desc_set(..., KERNEL_SELECTOR_CS, handler_addr, ...);
// KERNEL_SELECTOR_CS = 0x08 → points to the code segment in the GDT
````
- When an interrupt or exception occurs, the CPU:

  - Looks up the handler address in the IDT

  - Loads the CS register using the segment selector from the IDT entry

  - Sets EIP to the handler’s offset

  - Switches to kernel mode (if privilege level allows)

  - Starts executing the interrupt handler

---

### Commonly Seen x86 Exceptions
| Vector | Name                      | Description                                                   |
|--------|---------------------------|---------------------------------------------------------------|
| 0      | #DE – Divide Error        | Divide by zero
| 1      | #DB – Debug               | Hardware triggered breakpoints                               |
| 3      | #BP – Breakpoint          | Triggered by int3, used for debugging                         |
| 4      | #OF – Overflow            | Detects and reports arithmetic overflows                         |
| 6      | #UD – Invalid Opcode      | CPU cannot decode the instruction                             |
| 13     | #GP – General Protection  | Generic protection violation (e.g., segment fault) |
| 14     | #PF – Page Fault          | Invalid memory access (e.g., page not present)   |


---

### Exception Handler Overview

In x86 protected mode, exception and interrupt handlers **must** end with `iret` to properly restore the CPU’s execution context (EIP, CS, EFLAGS). A C `ret` cannot do this, so handlers are written in assembly using a reusable macro:

````asm
.macro exception_handler name num with_error_code
````

---

### Macro

Generates an exception handler labeled `exception_handler_<name>` that:

1. **Saves CPU state**  
   - **Hardware-pushed** by the CPU on entry:  
     - `EIP`, `CS`, `EFLAGS`, and _optional_ `Error Code`  
   - **`pusha`** (all general-purpose registers):  
     ````
     EAX, ECX, EDX, EBX, ESP (old), EBP, ESI, EDI
     ````
   - **Manually** saved segment registers:  
     ````
     DS, ES, FS, GS
     ````

3. **Passes the saved frame to a C handler**  
   - Pushes the current `ESP` (which now points to the saved registers)  
   - Calls `do_handler_<name>(exception_frame_t *frame)`

4. **Kills process or halt**  
   - Kills if generated by process
   - Halt if generated by kernel 
5. **Restores CPU state**  
   - Cleans up the stack parameter  
   - Pops segment registers, then registers saved by `pusha`

6. **Returns with `iret`**  
   - Restores `EIP`, `CS`, and `EFLAGS`  
---

### PIC Initialization

The x86 platform uses **two cascaded 8259 PIC (Programmable Interrupt Controller) chips** to manage hardware interrupts:

- **Master PIC (PIC0)** handles IRQ 0–7  
- **Slave PIC (PIC1)** handles IRQ 8–15 and connects to IRQ2 of PIC0  

---

### Key Points from `init_pic()`

1. **Two PIC Chips Are Connected**  
   - PIC1 is connected to PIC0’s IRQ2 line  
   - This cascade setup expands the number of IRQs from 8 to 16  

2. **Interrupt Numbers Can Be Remapped**  
   - PIC0 is configured to start at interrupt vector `0x20`  
   - PIC1 is configured to start at `0x28`  
   - This avoids overlapping with CPU exception vectors (which use 0x00–0x1F)

3. **Each IRQ Line Can Be Masked or Enabled**  
   - The **IMR (Interrupt Mask Register)** is used to disable specific IRQ lines  
   - In this setup:
     - PIC0 masks all IRQs except IRQ2 (used to reach PIC1)  
     - PIC1 masks all its IRQs until drivers enable them later

````c
outb(PIC0_IMR, 0xFF & ~(1 << 2));  // Unmask only IRQ2
outb(PIC1_IMR, 0xFF);              // Mask all slave IRQs
````

---

### Controlling Interrupts in x86

Interrupts in x86 can be managed at **two levels**:


1. Each 8259 PIC provides an **Interrupt Mask Register (IMR)**  
- **Mask** (disable) an IRQ by setting its bit in the IMR  
- **Unmask** (enable) an IRQ by clearing its bit  

2. **Global Enable/Disable (EFLAGS.IF)**
- The **IF (Interrupt Flag)** in the **EFLAGS** register gates all maskable interrupts
- **cli** — Clear the IF flag → disable all maskable interrupts
- **sti** — Set the IF flag → enable all maskable interrupts

---

### PIT (Programmable Interval Timer, 8253) Configuration

- The PIT oscillator runs at `PIT_OSC_FREQ` (≈ 1.193182 MHz).
- To generate an OS tick every `OS_TICK_MS` milliseconds, compute the reload value:
````c
reload_count = PIT_OSC_FREQ / (1000.0 / OS_TICK_MS);
````
- PIT is hardwired to **IRQ 0** (interrupt vector 0x20) on the master 8259 PIC.
- Each time the countdown reaches zero, the PIT sends an interrupt.

---

### `klib.c` Function List

The `klib.c` file provides basic kernel-level string and memory functions. It includes:

### String Functions
- `kernel_strcpy(char *dest, const char *src)`
- `kernel_strncpy(char *dest, const char *src, int n)`
- `kernel_strncmp(const char *s1, const char *s2, int n)`
- `kernel_strlen(const char *s)`

### Memory Functions
- `kernel_memcpy(void *dest, const void *src, int n)`
- `kernel_memset(void *dest, uint8_t v, int n)`
- `kernel_memcmp(const void *d1, const void *d2, int n)`

### Formatted Output & Number Conversion
- `kernel_vsprintf(char *buf, const char *fmt, va_list args)`
- `kernel_sprintf(char *buf, const char *fmt, ...)`
- `kernel_itoa(char *buf, int num, int base)`

---

### `kernel_vsprintf`: Formatted Output

This function mimics `vsprintf`, formatting a string using a format string and a `va_list` of arguments. It supports the following format specifiers:

- `%s` – string  
- `%d` – decimal integer  
- `%x` – hexadecimal integer  
- `%c` – character

The function processes the format string one character at a time. When it sees a `%`, it enters a state to parse the next format character and uses helper functions like:

- `kernel_strcpy()` and `kernel_strlen()` for `%s`
- `kernel_itoa()` for `%d` and `%x`
- direct character assignment for `%c`

No dynamic memory allocation is used; the buffer is filled directly.

---

### `kernel_itoa`: Integer to String Conversion

This function converts an integer `num` into a string representation in the given `base`. It supports bases 2, 8, 10, 16:

- If `num` is negative and base is 10, it handles the sign, otherwise use two's complement.
- Note that for negative base 10 numbers, we cannot simply do **num = -num** since there's an issue of **overflow**

___

### Task Switching with TSS

<img src="images/TSS.png" width="500">

This kernel uses **TSS (Task State Segment)** to support task switching.

When switching tasks, the CPU can automatically load new values for registers (including **general, segment, esp, eip, eflags, CR3**, etc.).

During initialization, we call `tss_init()` and pass in the **entry** and **kernel stack pointer** (`esp`) for the task:

---

## How TSS Works

**Each process has its own TSS (Task State Segment)**.
Therefore, for **every process**, a corresponding **TSS descriptor is placed in the GDT**.
These descriptors let the CPU locate and use the correct TSS when performing a task switch, and the corresponding selector (`tss_sel`) is stored in the **task structure**.

Note that TSS structures **cannot be dynamically allocated (e.g., via `malloc`)**. Instead, the kernel preallocates a fixed array of TSS entries globally.

To switch between tasks, the kernel performs a **far jump (ljmp)** to the TSS selector of the target task:

````c
ljmp $selector, $0
````
This causes the CPU to load the new task's TSS, restore all saved registers from the TSS, and begin execution from the eip stored in that TSS.

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