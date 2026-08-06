# Educational comments for the l_os sources

**Date:** 2026-08-06
**Status:** approved, not yet implemented

## Goal

Annotate every section of the l_os sources so a reader who is fluent in x86
assembly but new to OS development can follow what the code does and why.
Annotation happens in two places: block comments in the sources, and a
narrative walkthrough under `docs/notes/`.

No instruction is changed. Build output must come out byte-identical.

## Audience

The reader can read AT&T syntax and knows what `stosl`, `rep`, `%edi`, and the
direction flag do. Notes therefore spend no words on instruction mechanics.
They spend them on hardware protocols, on why a step must happen in the order
it does, and on the OS concepts behind each routine.

Concretely: explain that the 8042 gates A20 and how the command sequence works;
do not explain that `inb` reads a port.

## Language and rewrite authority

All comments end up in English. Existing comments are rewritten rather than
preserved — their typos are corrected and their wording improved. The two
Russian notes are translated:

| Location | Existing | Disposition |
|---|---|---|
| `boot.S:50` | `# инициализируем стек 0x7c00 (тк как растет вниз - пох)` | Translate: the stack goes at 0x7c00 and grows down, so it does not collide with the boot sector above it |
| `allocator.S:27` | `#// нулевой индекс тоже старничка` | Translate: index 0 is a valid page too |

This supersedes the `CLAUDE.md` line stating that Russian comments are to be
kept; that line is updated in the same change.

## Inline comment convention

**Comment character follows each file's existing style.** `#` in `boot.S` and
`hello.S`; `//` in `kernel.S`, `boot_paging.S`, `allocator.S`, and
`clear_screen.S`. The codebase is not unified to one style.

Two syntax constraints outside the `.S` files, both of which would break the
build silently if ignored:

- Linker scripts take `/* */` only. `//` is not a comment to `ld` and `#` is
  not either.
- `Makefile` comments must sit at column 0, outside recipe bodies. A `#` on a
  tab-indented recipe line is handed to the shell rather than stripped by
  `make`.

**One block per section, placed above the code it describes**, opening with a
ruled header so sections are scannable:

```
	####################
	# ATA PIO: WAIT FOR THE DRIVE
	####################
```

Body is roughly 4–10 lines. Dense bit layouts (GDT descriptor, PDE/PTE flags,
ATA status register) get a small aligned table inside the block. Each block
ends with a pointer to its `docs/notes/` chapter.

**Two marker prefixes** distinguish tone:

- `BUG:` — a defect, with the mechanism and the intended form. Seven of these.
- `NOTE:` — a deliberate simplification worth knowing about. Applies to the
  single-sector load, the absent page-fault path, `wait_disk` having no
  timeout, `free_page` having no overflow check, and the unfinished process
  routines.

## Bugs to annotate

All seven are annotated in place. **No instruction is changed.** Fixing them is
separate work, tracked in `TODO.md`.

Already in `TODO.md`:

| Location | Defect |
|---|---|
| `allocator.S:27` | `test %ecx, 0x0` tests `%ecx` against the dword at absolute address 0, not against zero. The out-of-memory branch is decided by whatever physical page 0 holds. Intended form is `test %ecx, %ecx`. |
| `kernelEnd.S:13` | `end:` emits a `.byte` *after* its `.align 0x1000`, so `KERNEL_PHYS_END` is 0x303001. Every address `create_phys_mem_list` pushes is one byte past a page boundary. |
| `boot.S:80,111` | The bootloader loads one 512-byte sector of a ~2 MB kernel. Kernel code ends at 0x80100174 so it fits today; the next routine can silently run off the end. The port 0x1f2 count and the `insw` counter must grow together. |

Found during this pass, to be appended to `TODO.md`:

| Location | Defect |
|---|---|
| `boot.S:25` | `seta20_2` polls, then `jnz seta20_1` — a busy controller re-sends the `0xd1` command instead of re-polling. Should be `jnz seta20_2`. |
| `clear_screen.S:10` | `$0xf9e` is the buffer size in *bytes*, used as a `stosw` *word* count. `clr_scr` writes 7996 bytes over a 4000-byte screen, reaching 0xb9f3c. Harmless only because that is still video RAM. Should be `$0x7d0` (2000 cells). |
| `allocator.S:75-78` | `movl %eax, %ecx` then `call allocate_page`, but `allocate_page` loads the stack index into `%ecx`. `%ecx` is clobbered before `movl %eax, (%ecx)` dereferences it. |
| `allocator.S:94-99` | `zero_page` never sets `%edi` or `cld`, so it zeroes 4 KB at whatever `%edi` happened to hold. |

## Sections to annotate

Thirty sections across ten files, in boot order.

**`boot.S`** — file header and `KERNEL_PLACE`; `start:` (`cli`/`cld`, segment
zeroing); the A20 gate (`BUG`); GDT load, `CR0.PE`, and the far jump;
`protcseg:` selector reload; stack setup; `kernel_entry`; `wait_disk`
(`NOTE`: no timeout); `load_kernel`; the GDT table and `gdtdesc`; the `0x55AA`
signature and `.org`.

`load_kernel` counts as one section: it gets a single ruled header block
covering the ATA programming sequence as a whole, then short one- or two-line
comments on the individual register writes (sector count, LBA, drive/head,
command) and the `insw` transfer, where the `BUG` block also goes.

**`kernel.S`** — the `BEGIN`/`END` macros as the calling convention; the
`PHYS_PAGES_COUNT` and `KERNEL_BASE` constants and why they are visible
everywhere; `main:` and `relocated:`.

**`boot_paging.S`** — file header on why every symbol is referenced as
`symbol - KERNEL_BASE`; page directory construction (entry 0, the zeroed
range, entries 512–1023); page table fill; `CR3`, `CR0.PG`, and the indirect
jump that lands at the virtual address.

**`allocator.S`** — `create_phys_mem_list` (`BUG`); `allocate_page` (`BUG`);
`free_page` (`NOTE`); `allocate_process` (`BUG`, `NOTE`); `zero_page` (`BUG`);
`create_process_pages` (`NOTE`: comments-only design sketch).

**`hello.S`** — `mesg` and `mprint`, including that the string sits in `.text`
ahead of the code.

**`clear_screen.S`** — `clr_scr` (`BUG`).

**`kernelEnd.S`** — the storage layout and why this file must stay last in the
Makefile prerequisite list (`BUG`).

**`link.ld`, `link_kernel.ld`, `Makefile`** — the 0x7c00 origin; the VMA/LMA
split and `KERNEL_PHYS_END`; the single `as` invocation over all `.S` files,
and why `--oformat binary` makes the missing `--32` flag harmless.

## docs/notes/

Nine chapters, read front to back as the story of the machine starting up.

| Chapter | Covers |
|---|---|
| `00-overview.md` | Memory map, boot-to-kernel flow, how to build, what is unfinished |
| `01-real-mode-boot.md` | Why 0x7c00, why 512 bytes, `cli`/`cld`, zeroing the segment registers |
| `02-a20-and-gdt.md` | A20 history and the 8042 protocol; GDT descriptor bit layout |
| `03-protected-mode.md` | `CR0.PE`, why the far jump is required, selector reload, stack setup |
| `04-ata-pio.md` | The 0x1f0–0x1f7 port map, the BSY/DRQ handshake, LBA addressing |
| `05-paging.md` | PDE/PTE bits, the higher-half trick, why 2 GB of tables are pre-built |
| `06-phys-allocator.md` | The LIFO page stack, `KERNEL_PHYS_END`, the unfinished process work |
| `07-vga-text.md` | 0xb8000, the 2-byte cell, the attribute byte |
| `08-build-system.md` | Two linker scripts, one translation unit, `--oformat binary`, VMA/LMA |

Each chapter closes with an **In the code** table of `file:line` anchors. Each
inline block points back at its chapter. Prose carries the background and
history; inline blocks stay self-sufficient at the site, so neither has to be
read to understand the other.

## Scope

**In scope:** `boot.S`, `kernel.S`, `boot_paging.S`, `allocator.S`, `hello.S`,
`clear_screen.S`, `kernelEnd.S`, `link.ld`, `link_kernel.ld`, `Makefile`; the
nine `docs/notes/` chapters; four new `TODO.md` entries; the `CLAUDE.md` line
about Russian comments.

**Out of scope:** every instruction in the codebase. The container and grammar
scripts `CLAUDE.md` excludes. Fixing any of the seven bugs. Unifying comment
style across files.

## Verification

Comments are stripped by `as`, so annotating cannot change a single byte of
output. That makes the check exact.

Baseline, captured from a clean build before any edit:

```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin      512 bytes
c28428650b543a9046c9fcacc73feeb7  kernel.bin   2109441 bytes
```

After the change, `make clean && make` must reproduce both hashes exactly. A
differing byte means an instruction was edited by accident and the change is
wrong. Additionally confirm `my_boot.bin` is exactly 512 bytes with `55 aa` at
offset `0x1fe`.

`qemu` is not available in this container, so there is no boot test. None is
needed: byte-identical output is a stronger guarantee than a successful boot.
