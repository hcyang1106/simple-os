/*
 The boot sector is stored in the first sector of the disk.
 It is then loaded to memory address 0x7c00 after the computer starts.
 The boot sector is reponsible for loading the "loader".
 */
 
#include "boot.h"

.code16 // x86 CPU starts in real mode, which operates on 16 bits architecture
.text
.global _start // .global makes it accessible by other files
.extern boot_entry // function not belonging to this file
	
// program starts from here (specified in CMakeLists.txt)
_start: 
	// set segment registers to zero
	// cs register is set to the address where the BIOS loads the boot sector at
	// segment regs are actually set to zeros by default, so we can also remove this part
	mov $0, %ax
	mov %ax, %ds
	mov %ax, %ss
	mov %ax, %es
	mov %ax, %fs
	mov %ax, %gs

	// set the memory before 0x7c00 as stack space
	mov $_start, %esp // low 16 bits of esp is sp

read_loader:
	// uses BIOS interrupt to read from disk
	// BIOS interrupts can be used to read from disk, display...etc.
	// within 1KB address there's an interrupt vector table
	// it checks the table and goes to the function address saved in the table
	// GDB: -exec x /20xb 0x8000, can check if data is correct
	mov $0x8000, %bx // loader be placed at memory address 0x8000
	mov $0x2, %ah // fixed usage
	mov $0x0080, %dx // set head number to zero (dh), set dl to 0x80 to read from hard disk
	mov $0x0002, %cx // set cylinder number to zero (ch), set cl to 0x02 to read sectors starting from 2nd (1st is MBR)
	mov $64, %al // we want to read 64 sectors
	int $0x13
	jc read_loader // retry if it fails

	jmp boot_entry // jmp 0x8000 is also fine

	// jump to the same location, so it stucks here
	jmp .

// set the last two bytes to 0x55, 0xaa (boot_end is set to 0x7dfe in CMakeLists.txt)
// section is used to define a new segment
// a means allocatable (allocates memory for the segment), x means executable (TODO: can be removed?)
.section boot_end, "ax"
boot_sig: .byte 0x55, 0xaa
