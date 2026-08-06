# TODO

Found while documenting the code; none are fixed yet.

- [ ] **Empty-stack check in `allocate_page` tests the wrong operand**
  (allocator.S:27). `test %ecx, 0x0` assembles to a test against absolute
  address 0, not against `%ecx`, so the "no memory available" branch is decided
  by whatever sits at physical 0. Index 0 is itself a valid page, so the fix has
  to keep that case allocatable.

- [ ] **`KERNEL_PHYS_END` is not page-aligned** (kernelEnd.S:13, link_kernel.ld:15).
  `end:` emits a `.byte` *after* its `.align 0x1000`, so the symbol is currently
  0x303001 and every address `create_phys_mem_list` pushes is one byte past a
  page boundary.

- [ ] **Bootloader loads only one 512-byte sector of a ~2 MB kernel**
  (boot.S:80, boot.S:111). Kernel code ends at 0x80100174 (~370 bytes) so it
  fits today, but the next routine can silently run off the end of what was
  loaded. The sector count written to port 0x1f2 and the `insw` counter
  (`$0x100`) have to grow together.
