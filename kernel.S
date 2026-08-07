	// ------------------------------------------------------
	// CALLING CONVENTION
	// ------------------------------------------------------
	// Every routine in this kernel opens with BEGIN and closes
	// with END. Together they maintain the standard frame
	// pointer chain - EBP points at the caller's saved EBP - so
	// a debugger can walk the stack.
	//
	// There is no C here and no ABI to honour, so arguments and
	// return values travel in registers. The `// long(void)` or
	// `// void(eax)` comment above each label is that routine's
	// signature. These macros preserve only EBP; callers must
	// save anything else they care about.

	.macro BEGIN
	pushl	%ebp
	movl	%esp, %ebp
	.endm

	.macro END
	movl	%ebp, %esp
	popl	%ebp
	ret
	.endm
	/////////////////////////////////
	/////////////////////////////////
	/////////////////////////////////

	// 0x400 = 1024 pages = 4 MB handed to the allocator. A
	// fixed count because there is no memory map yet: nothing
	// has asked the BIOS (INT 15h AX=E820) how much RAM
	// actually exists.
	.set	PHYS_PAGES_COUNT, 0x400
	// The kernel lives in the top 2 GB of the virtual address
	// space. Subtracting this from a virtual address yields the
	// physical one, which is what any code running before
	// CR0.PG has to do by hand.
	.set	KERNEL_BASE, 0x80000000

	.code32
	.section .text
	.global main
main:
	// Entered by the boot sector's `jmp 0x100000` with paging
	// still off, so this is executing at its physical address
	// rather than the 0x80100000 it was linked for. boot_paging
	// builds the tables, turns paging on, and jumps back to
	// `relocated` below - at which point the two agree.
	// See docs/notes/05-paging.md.
	jmp boot_paging
relocated:
	// Paging is on; execution is now at the linked virtual
	// address.

	call create_phys_mem_list

	call mprint

	// Nothing to return to.
	hlt
elop:	jmp elop
