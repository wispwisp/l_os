/* The BIOS loads the boot sector to physical 0x7c00 and jumps
   there, so the code must be linked for that address: every
   absolute reference in boot.S - gdtdesc, $start, $protcseg -
   resolves against it.

   No output sections are declared because --oformat binary
   emits the raw bytes and discards the ELF structure that
   would have described them.
   See docs/notes/08-build-system.md. */

ENTRY(start)

SECTIONS
{
. = 0x7c00;
}
