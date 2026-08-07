	// ------------------------------------------------------
	// BOOT PAGE TABLES
	// ------------------------------------------------------
	// Runs with paging still off, executing near physical
	// 0x100000 while every symbol here was linked at
	// 0x80100000. That is why each one is written as
	// `symbol - KERNEL_BASE`: the assembler resolves the symbol
	// to its virtual address and the subtraction converts it
	// back to the physical one.
	//
	// 32-bit x86 paging is two levels. A linear address splits
	// 10 / 10 / 12: the top 10 bits index the page directory,
	// the next 10 index a page table, the last 12 are the byte
	// offset inside a 4 KB page. Directory and table entries
	// both hold a page-aligned physical address in their top 20
	// bits and flags in the low 12.
	//
	// Flag 0x7 = P | RW | US: present, writable, and reachable
	// from ring 3. US is set on everything here, which is wrong
	// for kernel memory but harmless while there is no user
	// mode to protect against.
	// See docs/notes/05-paging.md.
boot_paging:
	// 0) PAGE DIRECTORY
	// Two windows onto the same physical memory:
	//   entry 0         -> [0, 4 MB)            identity
	//   entries 512-1023 -> [KERNEL_BASE, 4 GB)  kernel
	// The identity map exists purely so the instruction after
	// CR0.PG is set is still fetchable: execution is at a
	// physical address at that moment, and without entry 0 the
	// very next fetch would page fault.
	movl	$boot_pgtabels - KERNEL_BASE + 0x7, %ebx	# (+ 0x7 is the P|RW|US mask) to the 4 KB-aligned address of the page tables
	movl	$boot_pgdir - KERNEL_BASE, %edi
	// 0.1) entry 0: [0, 4 MB)
	movl	%ebx,%eax
	stosl
	// 0.2) entries 1-511 zeroed. The whole user half is left
	// unmapped, so a stray access below KERNEL_BASE faults
	// instead of quietly succeeding.
	xorl	%eax,%eax
	movl	$0x1ff, %ecx
	rep	stosl
	// 0.3) entries 512-1023: [KERNEL_BASE, 4 GB). Entry 512
	// points at the same first page table as entry 0, which is
	// exactly what makes virtual 0x80100000 resolve to physical
	// 0x100000. Each following entry steps one 4 KB table on.
	movl    $0x200,%ecx
	movl	%ebx,%eax
boot_paging_loop1:
	stosl
	addl    $0x1000, %eax
	loop    boot_paging_loop1

	// 1) PAGE TABLE ENTRIES
	// 0x80000 entries x 4 KB = 2 GB, mapped straight through:
	// entry N covers physical N * 4 KB. Filling all of it up
	// front means there is no page fault handler to write and
	// no lazy mapping to get right - at the cost of 2 MB of
	// tables, which is most of why kernel.bin is 2 MB.
	movl	$boot_pgtabels - KERNEL_BASE, %edi
	movl	$0x7, %eax
	movl	$0x80000, %ecx
loop_pgtbl_entry:
	stosl
	addl	$0x1000, %eax
	loop	loop_pgtbl_entry

	// 2) POINT CR3 AT THE DIRECTORY
	// CR3 takes the physical address - the MMU is not yet
	// translating anything, and could not translate this even
	// if it were.
	movl	$boot_pgdir - KERNEL_BASE, %eax
	movl	%eax, %cr3

	// CR0 bit 31 (PG). From the next instruction on, every
	// address goes through the MMU. This survives only because
	// of the identity map installed above.
	movl	%cr0, %eax
	orl	$0x80000000, %eax
	movl	%eax, %cr0

	// An indirect jump through a register, not a near relative
	// one. A relative jump would keep executing down in the
	// identity map; loading the absolute virtual address of
	// `relocated` and jumping through it is what actually moves
	// execution into the kernel window. The identity map is
	// dead weight from here and could be torn down.
	mov     $relocated, %eax
	jmp     *%eax
