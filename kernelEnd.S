aviable_phys_mem_stack_index:	.long 0x0
	.align 0x1000
aviable_phys_mem_stack_bottom:	.space PHYS_PAGES_COUNT * 4
aviable_phys_mem_stack_top:

	.align 0x1000
boot_pgdir: .space 0x1000

	.align	0x1000
boot_pgtabels: .space 0x80000 * 4

	
end: .align 0x1000
	.byte 0x0
