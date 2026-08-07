	// ------------------------------------------------------
	// PHYSICAL PAGE ALLOCATOR
	// ------------------------------------------------------
	// A LIFO stack of free physical page addresses: push to
	// free, pop to allocate. Constant time both ways and about
	// as simple as an allocator gets. What it cannot do is
	// satisfy a request for physically contiguous pages, which
	// anything driving DMA eventually needs.
	//
	// Storage lives in kernelEnd.S.
	// See docs/notes/06-phys-allocator.md.

	// void(void)
	// Fills the stack with PHYS_PAGES_COUNT (1024) page
	// addresses stepping 4 KB from the end of the kernel image,
	// so the allocator never hands out memory the kernel is
	// sitting on.
	//
	// BUG (TODO.md): KERNEL_PHYS_END is 0x303001, not 0x303000.
	// kernelEnd.S emits a .byte after its .align, so every
	// address pushed here is one byte past a page boundary.
	// Handing one of these to CR3 or storing it in a PDE would
	// put stray bits in the flag field.
create_phys_mem_list:
	BEGIN
	pushl	%edi

	cld
	movl	$aviable_phys_mem_stack_bottom, %edi
	movl	$KERNEL_PHYS_END, %eax
	movl	$PHYS_PAGES_COUNT, %ecx
loop_create_phys_mem_list:
	stosl
	addl	$0x1000, %eax
	loop	loop_create_phys_mem_list

	// The index points at the topmost occupied slot, so it
	// starts one below the count.
	movl	$PHYS_PAGES_COUNT - 1, aviable_phys_mem_stack_index

	popl	%edi
	END


	// long(void)
	// Returns a physical page address in EAX, or 0 when the
	// stack is empty. Clobbers ECX.
allocate_page:	
	BEGIN

	movl	aviable_phys_mem_stack_index, %ecx		#// to mem
	// The stack is empty when the index falls below zero.
	// Index 0 cannot double as the empty marker, because slot 0
	// holds a real, allocatable page.
	//
	// BUG (TODO.md): `test %ecx, 0x0` does not compare ECX
	// against zero. In AT&T syntax a bare 0x0 is a memory
	// operand, so this ANDs ECX with the dword at absolute
	// address 0 and sets flags from that. Which branch runs is
	// decided by whatever physical page 0 happens to hold.
	// The intended instruction is `test %ecx, %ecx`.
	test	%ecx, 0x0 #// index zero is a page too
	jnz	allocate_page_1
	xor	%eax,%eax		# // return zero - no memory available
	jmp	allocate_page_exit	# // TODO: could return directly instead of jumping to the exit
allocate_page_1:
	//	leal	(%eax,%ecx,4), %edx
	// Pop: read the top slot, then move the index down.
	movl	aviable_phys_mem_stack_bottom(,%ecx,4), %eax	#// to mem
	decl	%ecx
	movl	%ecx, aviable_phys_mem_stack_index		#// to mem
allocate_page_exit:
	// returns EAX

	END


	// void(eax)
	// Pushes the page in EAX back onto the free stack.
	// Clobbers ECX.
	//
	// NOTE: no bounds check. Freeing more pages than were ever
	// allocated walks the index past the top of the stack and
	// writes past it - and the next thing in kernelEnd.S is
	// boot_pgdir, at the very same address. An overflow here
	// corrupts the page directory.
free_page:
	BEGIN

	movl	aviable_phys_mem_stack_index, %ecx		#// to mem
	incl	%ecx
	movl	%eax, aviable_phys_mem_stack_bottom(,%ecx,4)	#// to mem
	movl	%ecx, aviable_phys_mem_stack_index		#// to mem

	END

	//void(void)
	// NOTE: unfinished. It allocates a page directory and a
	// couple of tables, but the flags are placeholders - every
	// `addl $0x0, %eax` is where a P|RW|US mask belongs - and
	// nothing is returned to the caller.
allocate_process:
	BEGIN
	pushl	%edi
	pushl	%esi
	pushl	%ebx

	// page for process page dir
	call	allocate_page
	movl	%eax, %ebx

	// page for page dir entry
	// 1) make first entry:
	call	allocate_page
	addl	$0x0,%eax
	movl	%eax,(%ebx)

	// lazy... do only one page
	// BUG (TODO.md): allocate_page clobbers ECX - it loads the
	// stack index into it - so by the time the dereference two
	// lines down runs, ECX no longer holds the page saved here.
	// The value has to survive the call, on the stack or in a
	// callee-saved register.
	movl	%eax, %ecx
	call	allocate_page
	addl	$0x0,%eax
	movl	%eax, (%ecx)

	// 2) make kernel mappings:
	// Entry 512 is the first PDE of the kernel window, the same
	// slot boot_paging.S fills for the boot directory.
	call	allocate_page
	addl	$0x0,%eax
	movl	%eax,512*4(%ebx)
	// todo movl (%eax), %esi; etc...


	popl	%ebx
	popl	%esi
	popl	%edi
	END



	// void(edi)
	// Zeroes one 4 KB page. The count is right: 0x400 dwords is
	// exactly 4096 bytes.
	//
	// BUG (TODO.md): neither EDI nor the direction flag is set
	// up, so this zeroes 4 KB starting wherever EDI happened to
	// point, running in whichever direction DF happened to
	// select. Unusable until the caller's contract is fixed.
zero_page:
	BEGIN

	movl	$0x400, %ecx
	xorl	%eax,%eax
	rep	stosl

	END
	
	// void(void)
	// NOTE: a design sketch, not code - the comments below are
	// the intended layout of a process address space and
	// nothing here is implemented. This is where the work
	// stopped.
create_process_pages:
	BEGIN

	// kernel mappings (KERNEL BASE AND UP)

	// kernel user top:
	// cpu(0...) kernel stack for process
	// cpu(...n) kernel stack for process
	
	// user system top:
	// map user page dir (top)
	// map user page tables (top)
	// map exeption stack (?)

	// user program top:
	// program stack
	// heap
	// code

	END
