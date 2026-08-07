# 05 - Kernel Entry and Paging

## The two-level walk: 10 / 10 / 12

32-bit x86 paging with 4 KB pages is a two-level table walk. A 32-bit
linear address splits into three fields:

| Bits | Width | Selects |
|---|---|---|
| 31:22 | 10 | index into the page directory (1024 entries) |
| 21:12 | 10 | index into a page table (1024 entries) |
| 11:0 | 12 | byte offset inside the 4 KB page |

The top 10 bits pick one of 1024 entries in the page directory; that
entry points at a page table. The next 10 bits pick one of 1024
entries in that table; that entry points at the physical 4 KB page.
The bottom 12 bits are the offset within the page and never go
through translation at all - a page is exactly `2^12 = 4096` bytes,
one for each value those 12 bits can take.

## PDE / PTE layout: frame number and flags

Page directory entries (PDEs) and page table entries (PTEs) share the
same 32-bit layout: the top 20 bits (31:12) hold a page-aligned
physical frame number, and the low 12 bits (11:0) hold flags. Because
a frame is 4 KB-aligned, its low 12 address bits are always zero
anyway, which is exactly the room the flags occupy.

`boot_paging.S` only ever sets `0x7`:

| Bit | Name | Meaning |
|---|---|---|
| 0 | P | present - entry is valid |
| 1 | RW | writable |
| 2 | US | accessible from ring 3 (user), not just ring 0 |

`0x7 = P | RW | US`. The other flag bits this code leaves at zero
still have names worth knowing:

| Bit | Name | Meaning |
|---|---|---|
| 3 | PWT | page write-through (caching policy) |
| 4 | PCD | page cache disable |
| 5 | A | accessed - set by the CPU on first reference |
| 6 | D | dirty - set by the CPU on first write (PTEs only) |
| 7 | PS | page size - 4 MB pages at the directory level, unused here |

## Why `boot_pgdir` is `0x1000` bytes

The page directory has exactly 1024 entries, and each entry is 4
bytes, so the whole directory is `1024 * 4 = 0x1000` bytes - one page,
which is also why it comes out naturally page-aligned.

## The higher-half trick

The kernel is linked to run at `0x80100000` but the boot sector loads
it at physical `0x00100000` - 2 GB below where every symbol in it was
linked. `KERNEL_BASE` is `0x80000000`, so `0x80100000 - KERNEL_BASE =
0x00100000`: subtracting `KERNEL_BASE` from any linked address in this
range gives back the physical address it actually occupies. Every
address `boot_paging.S` writes into a table entry goes through this
subtraction, because the code computing them is still running
unpaged, at a physical address, and cannot dereference a virtual one
that paging hasn't made real yet.

The reconciliation is `boot_pgdir` entry 512. A page directory index
is bits 31:22 of the linear address, so `0x80000000 >> 22 = 512`:
virtual address `0x80000000` and everything above it is routed through
directory entries 512-1023. Entry 512 is filled with the same
physical page table address as entry 0. That means the single block
of tables built by `loop_pgtbl_entry` is visible at two different
virtual addresses at once - `[0, 4 MB)` and `[KERNEL_BASE, KERNEL_BASE
+ 4 MB)` - which is exactly what makes virtual `0x80100000` resolve to
physical `0x00100000`.

## Why the identity map is mandatory, and only briefly

The moment `CR0.PG` is set, the very next instruction fetch goes
through the MMU - but execution at that instant is still at its
physical address, because the jump to the virtual address hasn't
happened yet. Without a mapping that sends that physical address to
itself, that very next fetch page-faults before there is an IDT or a
fault handler to catch it.

Directory entry 0 is that mapping: `[0, 4 MB)` maps to physical `[0, 4
MB)`, identity. It only has to survive for the handful of instructions
between `movl %eax, %cr0` and the indirect jump that lands on
`relocated`. After that, execution is at the virtual address and the
identity map is dead weight - the comment in `boot_paging.S` notes it
could be torn down, though nothing here does so yet.

## Why the final jump is indirect, not near/relative

A near jump encodes its target as an offset from the current `EIP`. If
`jmp *%eax` were replaced with a near relative jump to `relocated`,
the CPU would still be fetching from the identity-mapped low address
at the moment the jump executed, so a relative displacement would
land it right back in the identity map's address range - not at the
linked, virtual location. Loading the absolute virtual address of
`relocated` into `%eax` and jumping through the register is what
actually crosses over: the target address is `0x80100000`-plus,
resolved through the newly-live page tables, landing execution in the
kernel's linked window for the first time.

## The pre-built 2 GB of page tables

`loop_pgtbl_entry` fills `0x80000` page table entries, each 4 bytes:
`0x80000 * 4 = 0x200000` bytes = 2 MB of tables, covering `0x80000 *
0x1000` = 2 GB of address space split across 512 individual 4 KB
tables (`0x80000` entries / 1024 entries-per-table). Laid out right
after the kernel's own code and data, that block spans physical
`0x103000`-`0x303000` - which lands exactly on `end`, the symbol
`kernelEnd.S` marks the end of the kernel image with.

The tradeoff is explicit: filling every entry up front means there is
no page-fault handler to write and no lazy-mapping logic to get right,
at the cost of shipping 2 MB of mostly-mechanical table data inside
`kernel.bin` - which is most of why that file is about 2 MB instead of
a few hundred bytes.

## `US` is set on kernel pages - a latent problem

Every entry `boot_paging.S` writes, PDE and PTE alike, carries `US`
(bit 2), meaning ring 3 code can reach it. That is wrong for memory
that belongs to the kernel: user code should not be able to read or
write kernel structures at all. It is harmless for now only because
there is no ring 3 yet - nothing capable of exploiting the hole
exists. The moment user-mode processes are introduced, this flag has
to be revisited, or every kernel page is trivially accessible from
user code.

## In the code

| Location | What |
|---|---|
| `kernel.S` — `// CALLING CONVENTION` block | `BEGIN` / `END` |
| `kernel.S` — `main:` | `jmp boot_paging`, still unpaged |
| `kernel.S` — `relocated:` | First code at the virtual address |
| `boot_paging.S` — `// BOOT PAGE TABLES` block | The `- KERNEL_BASE` idiom |
| `boot_paging.S` — `// 0.1) entry 0` | PDE 0, identity map |
| `boot_paging.S` — `// 0.2)` | PDEs 1–511 zeroed |
| `boot_paging.S` — `boot_paging_loop1` | PDEs 512–1023, the kernel window |
| `boot_paging.S` — `loop_pgtbl_entry` | 2 GB of PTEs |
| `boot_paging.S` — `movl	%eax, %cr3` | Directory address |
| `boot_paging.S` — `orl	$0x80000000, %eax` | `CR0.PG` |
| `boot_paging.S` — `jmp     *%eax` | The indirect jump to the virtual address |
