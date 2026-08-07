# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This is educational little operating system. We will learn topics and then generate the code.

## Files to ignore
Ignore those files completely, as they are not your concern.
- build_claudecode_isolation_container.sh
- run_claudecode_isolation_container.sh
- claudecode.dockerfile
- check_grammar.sh

## Git authority
- Author name: `wisp`
- Author email: `forworkandtravel@yandex.ru`
- Commit style: short imperative subject (≤ 72 chars), body wrapped at 72,
  explain *why* not *what*. No AI-attribution trailers.

---

# Build & Verify

```sh
make              # boot.o -> my_boot.bin (512 B), kernel.o -> kernel.bin, plus kernel.asm listing
make make_disk    # my_boot.img: boot sector at offset 0, kernel written from sector 1
make clean
./mk.sh           # clean + make + make_disk + hexdump -C my_boot.img
```

There is no test suite and no emulator checked in. `./mk.sh` runs end to end
(`hexdump` is installed). `qemu` is not available in this container — the image
is booted outside it — so in-container verification of a change is: build
cleanly, then read the generated `kernel.asm` listing (`as -al`) for the encoded
bytes, and `hexdump -C my_boot.img` for what actually lands on the disk.

To inspect addresses, relink as ELF — the shipped `--oformat binary` output has
no symbol table:

```sh
ld -T link_kernel.ld -o kernel.elf kernel.o && nm -n kernel.elf
```

The host is x86_64 and the Makefile calls plain `as`/`ld` with no `--32` /
`-m elf_i386`. This works because `.code16`/`.code32` drive code generation and
`--oformat binary` strips the ELF wrapper.

`make make_disk` grows `my_boot.img` to ~2.1 MB rather than the nominal 1440 KB
floppy, because `kernel.bin` is ~2 MB: the page-table storage in `kernelEnd.S`
lands in `.text` and is emitted into the image.

# Architecture

Two independently linked binaries. `link.ld` puts the boot sector at 0x7c00.
`link_kernel.ld` links the kernel at VMA 0x80100000 (= LMA 0x00100000 +
KERNEL_BASE 0x80000000) and exports `KERNEL_PHYS_END`, the physical end of the
kernel image, to the allocator.

## Boot path

1. `boot.S` (`.code16`, 512 B, `0x55AA` at offset 0x1fe): zero segments → A20 via
   keyboard controller (ports 0x64/0x60) → `lgdt` flat GDT (code selector 0x08,
   data 0x10) → set CR0.PE → `ljmp` into `.code32` → stack at `$start` (0x7c00).
2. `load_kernel`: ATA PIO on ports 0x1f0–0x1f7, reads **one** sector starting at
   sector 1 into physical 0x100000, then `jmp` there.
3. `kernel.S:main` → `jmp boot_paging` → `boot_paging.S` builds the tables,
   loads CR3, sets CR0.PG, and `jmp *%eax` lands on `relocated` back in
   `kernel.S` (now running at its virtual address) → `create_phys_mem_list` →
   `mprint`.

Hard constraint: only 512 bytes of the kernel are loaded. Kernel code currently
ends at 0x80100174 (~370 bytes), so it still fits. Growing past one sector means
raising the sector count written to port 0x1f2 **and** the `insw` counter
(`$0x100`) in `load_kernel` (boot.S:224, boot.S:258).

## One translation unit

The kernel is assembled by a single `as` invocation over all `.S` files in the
Makefile's prerequisite order (kernel.S first, kernelEnd.S last). So:

- The `BEGIN`/`END` macros and the `.set` constants (`PHYS_PAGES_COUNT`,
  `KERNEL_BASE`) at the top of `kernel.S` are visible in every other file.
- Only the two `ENTRY()` targets are declared `.global` — `start` in boot.S
  and `main` in kernel.S. Nothing else needs to be: it's all one
  translation unit, so labels resolve across files directly.
- A new `.S` file must be added to the `$(KERN_NAME)` prerequisite list *before*
  `kernelEnd.S`, which holds all storage and must stay last.

Every routine is wrapped in `BEGIN`/`END` (ebp frame, `ret`). Arguments and
return values go in registers; the `// long(void)` / `// void(eax)` comment above
a label is that routine's signature. Comments are in English. Comment character
follows each file's existing style (`#` in `boot.S` and `hello.S`, `//`
elsewhere) — the codebase is deliberately not unified to one.

## Paging

Code that runs before CR0.PG is set executes at physical addresses, so it
references every symbol as `symbol - KERNEL_BASE`.

- `boot_pgdir` entry 0 identity-maps [0, 4 MB); entries 1–511 are zeroed;
  entries 512–1023 map [KERNEL_BASE, 4 GB) onto `boot_pgtabels`, which is what
  makes kernel VMA 0x80100000 resolve to physical 0x100000.
- `boot_pgtabels` is 0x80000 entries (2 GB) filled as `phys | 0x7`
  (present, writable, user).

## Physical page allocator — where work stopped

`allocator.S` implements a LIFO stack of free physical page addresses; its
storage lives in `kernelEnd.S` (`aviable_phys_mem_stack_bottom`, sized
`PHYS_PAGES_COUNT * 4`, plus `aviable_phys_mem_stack_index`).

- `create_phys_mem_list` pushes `PHYS_PAGES_COUNT` (0x400 = 1024 pages = 4 MB)
  addresses stepping 0x1000 from `KERNEL_PHYS_END`. That symbol is currently
  0x303001 — not page-aligned, because `end:` in `kernelEnd.S` emits a byte
  after its `.align 0x1000`.
- `allocate_page` returns a page in eax, or 0 when exhausted. `free_page` takes
  the page in eax. Index 0 is a valid page, which is what the empty-stack check
  has to distinguish; that check currently reads `test %ecx, 0x0`, which tests
  against absolute address 0 rather than the register.
- `allocate_process`, `zero_page` and `create_process_pages` are unfinished
  stubs — `allocate_process` allocates a page directory and a couple of tables
  with placeholder flags, and `create_process_pages` is comments only.

---

# Engineering Principles

## 1. Think Before Coding
- **Stop and ask** if requirements are ambiguous. Do not guess.
- **State assumptions explicitly** before writing any non-trivial code.
- **Present multiple interpretations** with tradeoffs if more than one valid approach exists.
- **Push back** if a requested change is over-engineered or adds unnecessary complexity.

## 2. Simplicity First
- Write the **minimum code** required to solve the task.
- Avoid speculative features, abstractions for single-use code, or "future-proofing."
- If a 200-line solution can be 50 lines, rewrite it.
- **Seniority Test**: If a senior engineer would call it "bloated," simplify it.

## 3. Surgical Changes
- **Touch only what is required.** Match existing code style perfectly.
- Do not "improve" adjacent code, refactor unrelated sections, or change formatting/quotes.
- **Preserve comments** you don't fully understand; do not delete them.
- Every line changed must trace directly to the current request.

## 4. Goal-Driven Execution
- Transform tasks into **verifiable goals** (e.g., "Write a failing test for [bug], then make it pass").
- Provide a brief plan for multi-step tasks before starting.
- **Loop until verified**: Do not declare success until you have run the relevant tests or verification steps.
