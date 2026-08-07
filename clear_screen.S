	// ------------------------------------------------------
	// CLEAR THE SCREEN
	// ------------------------------------------------------
	// The VGA text buffer starts at 0xb8000. In the default
	// 80x25 mode it holds 80 * 25 = 2000 cells of 2 bytes each,
	// so 4000 bytes, ending at 0xb8fa0.
	// See docs/notes/07-vga-text.md.
clr_scr:
	BEGIN
	pushl	%edi

	movl	$0xb8000,%edi
	// 0x0000 blanks a cell: character 0, black on black.
	movw	$0x0,%ax

	// BUG (TODO.md): 0xf9e is a byte count, but stosw stores a
	// word per iteration - so this clears 0xf9e * 2 = 7996
	// bytes over a 4000-byte screen, running out to 0xb9f3c. It
	// goes unnoticed only because that region is still VGA
	// memory. The count should be 0x7d0, i.e. 2000 cells.
	//
	// The figure it came from was wrong too: the old note gave
	// the buffer end as 0xb8f9e, two bytes short of 0xb8fa0.
	movl	$0xf9e,%ecx
	rep	stosw

	popl	%edi
	END
