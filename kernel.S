	// macros secion:
	.macro BEGIN
	pushl	%ebp
	movl	%esp, %ebp
	.endm

	.macro END
	movl	%ebp, %esp
	popl	%ebp
	ret
	.endm
	// macros section end
	/////////////////////////////////
	/////////////////////////////////
	/////////////////////////////////

	.set	PHYS_PAGES_COUNT, 0x400
	.set	KERNEL_BASE, 0x80000000

	.code32
	.section .text
	.global main
main:

	// boot paging directory for kernel
	// with [0..4mb) and [KERNBASE..4mb) to same phys.memory
	jmp boot_paging
relocated:

	call create_phys_mem_list

	call mprint

	// erro:
	hlt
elop:	jmp elop
