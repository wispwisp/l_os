	// ------------------------------------------------------
	// KERNEL STORAGE
	// ------------------------------------------------------
	// All the writable memory the kernel needs. This file must
	// stay LAST in the Makefile's prerequisite list: every .S
	// file is assembled as one translation unit, so the `end`
	// marker below only marks the true end of the image if
	// nothing follows it.
	//
	// None of this is in .bss, so all of it is emitted into
	// kernel.bin - 2 MB of mostly zeros, which is why the disk
	// image comes out at 2.1 MB rather than a 1440 KB floppy.
	// See docs/notes/06-phys-allocator.md.

aviable_phys_mem_stack_index:	.long 0x0
	.align 0x1000
aviable_phys_mem_stack_bottom:	.space PHYS_PAGES_COUNT * 4
	// NOTE: this label and boot_pgdir below both resolve to
	// 0x80102000 - the stack ends exactly where the page
	// directory starts. Since free_page has no bounds check,
	// overflowing the stack writes straight into the page
	// directory.
aviable_phys_mem_stack_top:

	.align 0x1000
	// 1024 entries x 4 bytes = exactly one 4 KB page.
boot_pgdir: .space 0x1000

	.align	0x1000
	// 0x80000 entries x 4 bytes = 2 MB = 512 page tables,
	// covering 2 GB. Filled by boot_paging.S.
boot_pgtabels: .space 0x80000 * 4

	
	// BUG (TODO.md): the .byte lands AFTER the .align, so while
	// `end` itself sits at 0x80303000 the location counter
	// finishes at 0x80303001 - and link_kernel.ld computes
	// KERNEL_PHYS_END from the counter, giving 0x303001. Every
	// page address create_phys_mem_list pushes inherits that
	// one-byte skew.
end: .align 0x1000
	.byte 0x0
