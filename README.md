# SimpleOS
SimpleOS is an OS implementation that is used to enhance my understanding of OS concepts. The following explains how I implemented it.

---

## Toolchain Setup

To build and run the OS on MacOS, you’ll need the following:

| Tool                  | Purpose                                  |
|-----------------------|------------------------------------------|
| `qemu-system-i386`    | Emulates an x86 PC                       |
| `cmake`               | Build configuration                      |
| `x86_64-elf-gcc`      | Cross-compiler for x86 ELF               |
| `x86_64-elf-gdb`      | Cross-debugger to connect to QEMU (used for remote debugging)       |
| `ld`, `as`, `objcopy`, `objdump`, `readelf` | Tools for ELF analysis and binary conversion |

> 💡 Installing `x86_64-elf-gcc` typically includes the full toolchain: assembler, linker, and ELF utilities.

---

## Disk Image Setup

### Disk 1 (Bootable)

- Created using `dd`
- Uses precise sector control for:
  - MBR (first 512 bytes)
  - Loader (second stage bootloader)
  - Kernel

### Write Script: `img-write-os`

This script automates writing contents into the disk images:

- Uses `dd` for `disk1` to write:
  - MBR
  - Loader
  - Kernel

---

## Explanation of the QEMU Command

### Basic System Configuration

- `qemu-system-i386`: Launches QEMU emulating a 32-bit x86 machine.
- `-m 128M`: Allocates 128MB of memory to the virtual machine.
- `-serial stdio`: Redirects the virtual machine's serial output to the host terminal.
  - Useful for printing messages from your OS via `printf`, `putchar`, or low-level serial writes.

---

### Attaching Disk Images

- `-drive file=disk1.dmg,index=0,media=disk,format=raw`  
  Attaches the first virtual disk (usually containing the MBR, loader, and kernel).

- `-drive file=disk2.dmg,index=1,media=disk,format=raw`  
  Attaches a second virtual disk (typically used for file system or user programs).

---

### Debug Mode

- `-s`: Starts a GDB server on TCP port `1234`. Equivalent to `-gdb tcp::1234`.
- `-S`: Pauses the CPU immediately after boot. Execution will not start until GDB sends a `continue` command.

> ❗ This is why the system will not automatically run your bootloader when QEMU starts. You must connect with GDB and manually start execution.

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

## In Boot Sector
![Subdirectory Image](images/boot.jpeg)

The boot sector is the first sector on disk. Its job is to load the "Loader" to memory. After a computer is turned on, BIOS then loads the boot sector to memory address 0x7c00 and starts executing the code in it.

In the boot sector, we mainly do two things:
1. Loads the "Loader"  
2. Jumps to Loader address 0x8000

Q: Why do we put 0x55, 0xAA as the last two bytes in the boot sector?    

A: 0x55, 0xAA indicates that the boot sector is valid so that BIOS can proceed to load the code.

Q: How does boot load the Loader into memory?    

A: It uses BIOS interrupt to load the Loader from disk.

## In Loader
![Subdirectory Image](images/loader.png)

In loader, we do the following tasks:
1. Detect free memory spaces:  
    A BIOS interrupt is used to detect free memory spaces. The memory information is then passed to the Kernel for further usage.  

2. Enter the protected mode:  
    There are four steps to enter the protected mode.  
    a. Clear Interrupt  
    b. Open the A20 gate  
    c. Load GDT Table  
    d. Do a far jump (far jump is used to clear the pipelined instructions). 

3. Load the Kernel  
    We first load the elf file of Kernel to address 0x100000, and after that the code is extracted from the elf file and put at 0x10000.

Q: What is protected mode?    

A: Protected mode lets CPU access memory address higher than 1MB, and also provides protection, preventing programs from interfering with each other.

Q: Why do intel CPUs start from real mode first, and then enter protected mode later?    

A: Backward Compatibility. When CPUs with protected mode was released, there was already a significant base of software that ran in real mode. Starting in real mode ensures that older operating systems and software can still run on newer processors.

Q: Why don't we just load the kernel directly from disk?    

A: Sometimes there are spaces between sections (code, data, etc.). Therefore, the binary file could be large. If we load such a large file directly from disk, it may take a long time.

## Mutex
1. Initialization: The mutex is set to be unlocked with no owner, and a list is created to hold tasks that might have to wait for the lock.

2. Locking: When a task tries to lock the mutex, if no one owns it, the task becomes the owner. If someone else already owns the mutex, the task is put on a waiting list until the mutex becomes available.

3. Unlocking: When the owner releases the mutex, if other tasks are waiting, the first one in line is given ownership of the mutex and allowed to continue.

## Semaphore
1. Initialization: The semaphore is initialized with a specific count value, which represents the number of tasks that can proceed without waiting. A list is created to hold tasks that may need to wait.

2. Waiting (sem_wait): When a task wants to proceed, it checks if the semaphore count is greater than zero. If it is, the task decreases the count and continues. If the count is zero, the task is put on a waiting list, meaning it has to wait until it’s notified (when resources become available).

3. Notifying (sem_notify): When a resource is freed or made available, the first task in the waiting list is notified and allowed to proceed. If no tasks are waiting, the semaphore count is increased, allowing future tasks to continue without waiting.

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

