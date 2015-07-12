boot_paging:
	// 0) PAGE DIRECTORY:
	movl	$boot_pgtabels - KERNEL_BASE + 0x7, %ebx	# (+ 0x7 is mask) to 2^12  aligned addres of pgtables
	movl	$boot_pgdir - KERNEL_BASE, %edi
	// 0.1) first entry [0,4mb)
	movl	%ebx,%eax
	stosl
	// 0.2) zeroing [4mb, KERNBASE]
	xorl	%eax,%eax
	movl	$0x1ff, %ecx
	rep	stosl
	// 0.3) 512 entry: [KERNBASE, PHYS_MEM_TOP)
	movl    $0x200,%ecx
	movl	%ebx,%eax
boot_paging_loop1:
	stosl
	addl    $0x1000, %eax
	loop    boot_paging_loop1

	// 1) MAKE PAGETABLE ENTRYS
	movl	$boot_pgtabels - KERNEL_BASE, %edi
	movl	$0x7, %eax
	movl	$0x80000, %ecx
loop_pgtbl_entry:
	stosl
	addl	$0x1000, %eax
	loop	loop_pgtbl_entry

	// 2) PUT ADDRESS:
	movl	$boot_pgdir - KERNEL_BASE, %eax
	movl	%eax, %cr3

	// enable pagging:
	movl	%cr0, %eax
	orl	$0x80000000, %eax
	movl	%eax, %cr0

	mov     $relocated, %eax
	jmp     *%eax
