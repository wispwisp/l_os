# 01 - Real-Mode Boot

## Why 0x7c00

On power-on the BIOS runs POST (power-on self-test), then looks for a
bootable disk: one whose first sector ends with the signature `0x55AA`.
If it finds one, it loads that sector - 512 bytes, sector 0 - to physical
address `0x7c00` and jumps there in 16-bit real mode. That is the whole
contract between the BIOS and `boot.S`: be 512 bytes, end in `0x55AA`,
and be ready to run at `0x7c00`.

`0x7c00` itself is not chosen for any property of the code that lands
there - it is convention inherited from the IBM PC 5150. Early PCs
guaranteed only 32 KB of RAM, and the BIOS needed somewhere to put the
boot sector that would not collide with anything else it was using.
`0x7c00` was the address that left the largest contiguous free block
below that 32 KB minimum, so it stuck, and every BIOS since has kept
loading there for compatibility.

## Real mode

The CPU starts in 16-bit real mode, the same mode the original 8086
ran in. Addresses are formed as `segment * 16 + offset`: a 16-bit
segment register shifted left four bits and added to a 16-bit offset,
giving a 20-bit address space - 1 MB total, no more. There is no paging
and no privilege separation; any code can touch any address or port.
The BIOS's interrupt vector table is still installed, so `int` calls
into BIOS services (disk, video, keyboard) still work - a convenience
that disappears the moment the CPU leaves real mode.

## Masking interrupts and fixing string direction

The first two instructions that run are `cli` and `cld`, and both are
defensive rather than functional.

`cli` masks interrupts. No IDT (interrupt descriptor table) has been
set up yet - the BIOS's own IDT is still technically in place, but the
code that its handlers assume is present is about to be overwritten or
made invalid. An interrupt firing here would vector through a table
pointing at code that can no longer be trusted, so interrupts stay
masked until the kernel installs its own handlers, much later.

`cld` clears the direction flag. String instructions (`movs`, `stos`,
`ins`, and the like) step their pointers forward or backward depending
on this flag, and the BIOS makes no promise about its state on entry.
Every string instruction used later - the `insw` in `load_kernel`, the
`rep stosl` in `boot_paging` - assumes it counts upward, so `cld` has
to run before any of them, and running it up front means it never has
to be revisited.

## Zeroing the segment registers

Real-mode addresses are `segment * 16 + offset`, so the same linear
address can be reached through many different segment:offset pairs.
`boot.S` deals with this by fixing the segment registers at zero -
`%ds`, `%es`, and `%ss` are all set to `0x0` - so that from this point
on, offset alone equals the physical address.

That is what makes `link.ld`'s `. = 0x7c00` sufficient on its own.
The linker only has to place labels starting at `0x7c00`; it does not
need to know or encode anything about segments, because every segment
register is zero. An offset of `0x7c00` and a physical address of
`0x7c00` are the same number.

## The stack

Memory below `0x7c00` is free - nothing the BIOS relies on lives there
- so the boot sector uses it for its stack. `%esp` is set to `start`
(`0x7c00` itself) once the CPU reaches protected mode, and the stack
grows downward from there into that free region. That setup is covered
in more detail in chapter 03.

## In the code

| Location | What |
|---|---|
| `boot.S:4-5` | `start:`, `.code16` |
| `boot.S:7-8` | `cli` / `cld` |
| `boot.S:10-13` | Segment register zeroing |
| `link.ld:5` | `. = 0x7c00` |
