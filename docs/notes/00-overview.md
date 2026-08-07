# 00 - Overview

## What this is

This is an educational little operating system: a kernel that boots a
real machine (or an image booted outside this container) from a cold
BIOS handoff up through 32-bit protected mode with paging enabled and a
working physical page allocator, then stops. There is no process
scheduler yet, no user mode, and no interrupt handling beyond keeping
interrupts masked. The code is small enough to read end to end in one
sitting, and these notes exist to explain *why* each piece is built the
way it is, not just what it does.

## How to read these notes

The chapters run in boot order, 01 through 08, each covering the
subsystem that comes next as execution proceeds: real-mode entry, the
A20 gate and GDT, the switch to protected mode, the ATA disk read,
paging, the physical page allocator, VGA text output, and the build
system that ties it all together. Read them in order for the full
story, or jump straight to chapter 08 if all you want is to build the
image.

Every `.S` and `.ld` file carries a comment pointing at the chapter
that explains it, so you can also start from the code and follow the
reference out to the relevant chapter.

## The boot path

1. BIOS loads sector 0 to `0x7c00`, real mode.
2. `boot.S`: zero segments, A20, `lgdt`, `CR0.PE`, `ljmp` to 32-bit,
   stack at `0x7c00`.
3. `load_kernel`: ATA PIO, one sector from LBA 1 to physical
   `0x100000`, then `jmp` there.
4. `kernel.S:main` → `boot_paging` → tables, `CR3`, `CR0.PG`, indirect
   jump to `relocated`.
5. `create_phys_mem_list`, then `mprint`, then `hlt`.

See chapters 01-04 for the first three steps and chapter 05 for the
fourth. Chapter 06 covers `create_phys_mem_list`; chapter 07 covers
`mprint`.

## The memory map

| Region | Address | What |
|---|---|---|
| Boot sector | `0x7c00` | 512 bytes, loaded by BIOS |
| Boot stack | below `0x7c00` | Grows down; ~30 KB free above the IVT/BDA |
| Kernel load address | `0x00100000` | LMA |
| Kernel run address | `0x80100000` | VMA = LMA + `KERNEL_BASE` |
| Kernel code end | `0x80100174` | 372 bytes of code |
| Free page stack | `0x80101000`-`0x80102000` | 1024 entries x 4 bytes |
| `boot_pgdir` | `0x80102000` | 4 KB (same address as the stack top) |
| `boot_pgtabels` | `0x80103000` | 2 MB, 512 tables, 2 GB mapped |
| Image end | `0x80303000` | `end`; `KERNEL_PHYS_END` = `0x303001` |
| VGA text buffer | `0xb8000`-`0xb8fa0` | 80 x 25 x 2 bytes |

Chapter 05 explains the higher-half split between load and run
addresses; chapter 06 explains why the free page stack's top and
`boot_pgdir` share an address; chapter 08 explains where `end` and
`KERNEL_PHYS_END` diverge.

## Build and verify

```sh
make              # boot.o -> my_boot.bin (512 B), kernel.o -> kernel.bin, plus kernel.asm listing
make make_disk    # my_boot.img: boot sector at offset 0, kernel written from sector 1
make clean
./mk.sh           # clean + make + make_disk + hexdump -C my_boot.img
```

There is no test suite and no emulator checked in. `qemu` is not
available in this container - the image is booted outside it - so
in-container verification of a change is: build cleanly, then read the
generated `kernel.asm` listing (`as -al`) for the encoded bytes, and
`hexdump -C my_boot.img` for what actually lands on the disk. Chapter
08 covers the build system in full, including how to relink the kernel
as ELF to get a symbol table back.

## What is unfinished

- `allocate_process` allocates a page directory and a couple of page
  tables but returns nothing to its caller, and every flags field is a
  placeholder rather than a real `P|RW|US` mask.
- `create_process_pages` is comments only - a design sketch of a
  process address space with no implementation behind it.
- There is no IDT and no fault handler; interrupts have been masked
  since `boot.S`'s first instruction and never re-enabled.
- There is no user mode - nothing runs at ring 3 yet.
- There is no memory map query. `PHYS_PAGES_COUNT` (4 MB) is a
  hardcoded guess; nothing has asked the BIOS (`INT 15h, AX=E820h`)
  what memory actually exists.

## Known bugs

All seven are tracked in `TODO.md`, which keeps the `file:line` form.
The anchors below are symbolic, pointing at the label or instruction
each bug lives in.

| Bug | Location | Summary |
|---|---|---|
| Stray jump target in the A20 poll | `boot.S` — `seta20_2` | The busy-wait after the `0xd1` command write branches to `seta20_1` instead of `seta20_2`, re-issuing the command instead of just re-polling status. Harmless today because the controller is idle by then. |
| Only one sector of the kernel is loaded | `boot.S` — `load_kernel` | The sector count written to port `0x1f2` and the `insw` counter both request just 512 bytes, for a kernel image that is ~2 MB. Works only because kernel code currently ends within that first sector. |
| Empty-stack check tests the wrong operand | `allocator.S` — `allocate_page` | `test %ecx, 0x0` assembles to a test against absolute address 0, not against `%ecx`, so the "stack empty" branch is decided by whatever sits at physical page 0. |
| `%ecx` is clobbered before it's used | `allocator.S` — `allocate_process` | A page address saved into `%ecx` is overwritten by the following `allocate_page` call, which loads the stack index into the same register, before the saved value is written through. |
| `zero_page` has no destination | `allocator.S` — `zero_page` | `rep stosl` runs with neither `%edi` nor the direction flag set, so it zeroes 4 KB starting from wherever `%edi` already happened to point. |
| `clr_scr` clears twice the screen | `clear_screen.S` — `clr_scr` | `$0xf9e` is a byte count but feeds a word-at-a-time `rep stosw`, writing 7996 bytes over a 4000-byte screen. Invisible because the overrun still lands in VGA memory. |
| `KERNEL_PHYS_END` is not page-aligned | `kernelEnd.S` — `end:` | A `.byte` is emitted after the `.align 0x1000` that precedes it. That only moves the location counter - the symbol `end` itself stays page-aligned - but `link_kernel.ld` takes `KERNEL_PHYS_END` from the location counter, so it lands one byte past the boundary. |

## Chapter index

- [01 - Real-Mode Boot](01-real-mode-boot.md)
- [02 - The A20 Gate and the GDT](02-a20-and-gdt.md)
- [03 - The Protected-Mode Switch](03-protected-mode.md)
- [04 - The ATA PIO Disk Read](04-ata-pio.md)
- [05 - Kernel Entry and Paging](05-paging.md)
- [06 - The Physical Page Allocator](06-phys-allocator.md)
- [07 - VGA Text Output](07-vga-text.md)
- [08 - The Build System](08-build-system.md)
