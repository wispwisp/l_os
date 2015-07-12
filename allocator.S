	// void(void)
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

	// save index (top of phys mem stack):
	movl	$PHYS_PAGES_COUNT - 1, aviable_phys_mem_stack_index

	popl	%edi
	END


	// long(void)
allocate_page:	
	BEGIN

	movl	aviable_phys_mem_stack_index, %ecx		#// to mem
	test	%ecx, 0x0 #// нулевой индекс тоже старничка
	jnz	allocate_page_1
	xor	%eax,%eax		# // return zero - no mem aviable
	jmp	allocate_page_exit	# // optimization: todo simple ret without jump
allocate_page_1:
	//	leal	(%eax,%ecx,4), %edx
	movl	aviable_phys_mem_stack_bottom(,%ecx,4), %eax	#// to mem
	decl	%ecx
	movl	%ecx, aviable_phys_mem_stack_index		#// to mem
allocate_page_exit:
	// ret eax

	END


	// void(eax)
free_page:
	BEGIN

	movl	aviable_phys_mem_stack_index, %ecx		#// to mem
	incl	%ecx
	movl	%eax, aviable_phys_mem_stack_bottom(,%ecx,4)	#// to mem
	movl	%ecx, aviable_phys_mem_stack_index		#// to mem

	END

	//////////////////////////////
	//         processes        //
	//////////////////////////////

	//void(void)
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
	movl	%eax, %ecx
	call	allocate_page
	addl	$0x0,%eax
	movl	%eax, (%ecx)

	// 2) make kernell mapings:
	call	allocate_page
	addl	$0x0,%eax
	movl	%eax,512*4(%ebx)
	// todo movl (%eax), %esi; etc...


	popl	%ebx
	popl	%esi
	popl	%edi
	END



zero_page:
	BEGIN

	movl	$0x400, %ecx
	xorl	%eax,%eax
	rep	stosl

	END
	
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
