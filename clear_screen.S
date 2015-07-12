	// 0xb8000 - begin of bios memory
	// 0xb8f9e - end. (0xb8000 - b8f9e = 0xf9e)
clr_scr:
	BEGIN
	pushl	%edi

	movl	$0xb8000,%edi
	movw	$0x0,%ax

	movl	$0xf9e,%ecx
	rep	stosw

	popl	%edi
	END
