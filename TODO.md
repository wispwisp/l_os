# TODO

Found while documenting the code; none are fixed yet.

- [ ] **Empty-stack check in `allocate_page` tests the wrong operand**
  (allocator.S:68, `test	%ecx, 0x0`). `test %ecx, 0x0` assembles to a test
  against absolute address 0, not against `%ecx`, so the "no memory available"
  branch is decided by whatever sits at physical 0. Index 0 is itself a valid
  page, so the fix has to keep that case allocatable - and it isn't as simple
  as `test %ecx, %ecx`, since that would classify index 0 itself as empty; the
  check has to test the sign, not equality with zero.

- [ ] **`KERNEL_PHYS_END` is not page-aligned** (kernelEnd.S:42, `.byte 0x0`;
  link_kernel.ld:30, `KERNEL_PHYS_END = . - VIRTUAL_KERNEL_BASE;`).
  `end:` emits a `.byte` *after* its `.align`, but that only moves the
  location counter - the `end` symbol itself lands page-aligned, at
  `0x80303000`. `KERNEL_PHYS_END` is taken from the location counter, not
  from `end`, so `KERNEL_PHYS_END` is currently `0x303001`, and every address
  `create_phys_mem_list` pushes is one byte past a page boundary.

- [ ] **Bootloader loads only one 512-byte sector of a ~2 MB kernel**
  (boot.S:224, `movb	$0x1, %al # sector count = 1`; boot.S:258,
  `movl	$0x100, %ecx`). Kernel code ends at 0x80100174 (~370 bytes) so it
  fits today, but the next routine can silently run off the end of what was
  loaded. The sector count written to port 0x1f2 and the `insw` counter
  (`$0x100`) have to grow together.

- [ ] **`seta20_2` re-sends the command byte instead of re-polling**
  (boot.S:84, `jnz	seta20_1`). The busy-wait after the `0xd1` command write
  branches back to `seta20_1`, so a controller that is still busy repeats the
  command write rather than just re-reading status. Should be `jnz seta20_2`.
  Harmless in practice - the `outb` just above genuinely can leave the input
  buffer full at that point, but re-issuing `0xd1` is idempotent, so the loop
  just takes a longer path and still converges once the buffer drains.

- [ ] **`clr_scr` clears twice the screen** (clear_screen.S:24,
  `movl	$0xf9e,%ecx`). `$0xf9e` is the buffer size in bytes, but
  `rep stosw` writes a word per iteration, so it zeroes 7996 bytes over a
  4000-byte screen and runs out to 0xb9f3c. Invisible only because that is
  still VGA memory. The count should be `$0x7d0` — 2000 cells of 80 × 25.

- [ ] **`allocate_process` dereferences a clobbered `%ecx`**
  (allocator.S:130-133, `movl	%eax, %ecx`). `movl %eax, %ecx` saves a page,
  then `call allocate_page` overwrites `%ecx` with the stack index before
  `movl %eax, (%ecx)` writes through it. The saved value has to survive the
  call, on the stack or in a callee-saved register.

- [ ] **`zero_page` has no destination** (allocator.S:159-164,
  `zero_page:`). Neither `%edi` nor the direction flag is set, so it zeroes
  4 KB from wherever `%edi` happened to point, in whichever direction DF
  happened to select. The count is correct: `0x400` dwords is exactly one
  page.
