mesg:
	.string "Memory initialized"
mprint:
	BEGIN
	pushl	%edi
	pushl	%esi

	call	clr_scr

	cld
	movl	$0xb8000,%edi
	movl	$mesg,%esi
print_loop:
	lodsb
	testb	%al, %al
	jz	print_loop_exit
	stosb
	movb	$7,%al # symbol attribute (see vga mode)
	stosb
	jmp	print_loop

print_loop_exit:
	popl	%esi
	popl	%edi
	END
