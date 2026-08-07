	# ------------------------------------------------------
	# VGA TEXT OUTPUT
	# ------------------------------------------------------
	# NOTE: this string sits in .text, ahead of the code that
	# reads it. Safe only because nothing ever jumps to mesg -
	# execution always enters at mprint. .rodata would be the
	# conventional home, and link_kernel.ld already declares
	# one.
	# See docs/notes/07-vga-text.md.
mesg:
	.string "Memory initialized"

	# void(void)
	# Writes mesg to the top-left of the screen.
mprint:
	BEGIN
	pushl	%edi
	pushl	%esi

	call	clr_scr

	# VGA text mode maps the screen into memory at 0xb8000, two
	# bytes per cell: the character code, then its attribute. So
	# the loop stores one byte from the string and one byte of
	# attribute, and EDI lands on the next cell by itself.
	cld
	movl	$0xb8000,%edi
	movl	$mesg,%esi
print_loop:
	lodsb
	testb	%al, %al
	jz	print_loop_exit
	stosb
	# 0x07 = light grey on black. Bits 0-3 are foreground, bits
	# 4-6 are background, and bit 7 is either blink or
	# bright-background, depending on how the adapter is
	# configured.
	movb	$7,%al
	stosb
	jmp	print_loop

print_loop_exit:
	popl	%esi
	popl	%edi
	END
