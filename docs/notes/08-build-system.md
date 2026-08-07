# 08 - The Build System

## Two binaries, two linker scripts

`boot.S` and the kernel are linked separately, by `link.ld` and
`link_kernel.ld`, because they are two different jobs with two
different constraints. The boot sector has to be exactly 512 bytes,
ending in the `0x55AA` signature, and has to sit at the one address
the BIOS will jump to: `0x7c00`. The kernel has no such size limit and
runs at a completely different address once paging is live. One
linker script per binary is simpler than trying to make a single
script describe two unrelated layouts, and it mirrors the two
independent `as`/`ld` invocations in the `Makefile`.

## VMA vs LMA

A linker script can give a section two different addresses: the LMA
(load memory address), where the bytes physically sit in the file/on
disk, and the VMA (virtual memory address), the address code is
linked to assume it's running at. When the two match, as in `link.ld`,
there's nothing to say. When they diverge, whatever puts the bytes in
memory has to place them at the LMA, and nothing may execute code that
assumes the VMA until something - here, paging - makes the VMA real.

`link_kernel.ld` is the divergent case: `LMA = 0x00100000` is where
`load_kernel` (`boot.S`) actually writes the kernel with `insw`, and
`VMA = LMA + VIRTUAL_KERNEL_BASE` (`VIRTUAL_KERNEL_BASE = 0x80000000`,
the same constant `kernel.S` calls `KERNEL_BASE`) is the address every
symbol in the kernel is linked against - `0x80100000`. Any kernel code
that runs before `CR0.PG` is set is executing at the LMA while every
address baked into it by the linker is a VMA, 2 GB higher. That's the
entire reason `boot_paging.S` writes every symbol it touches as
`symbol - KERNEL_BASE`: it's converting a linked (VMA) address back to
the physical (LMA) one it's actually running at, because paging hasn't
turned the VMA into a real address yet.

## One `as` invocation, one translation unit

The `Makefile`'s `$(KERN_NAME)` rule passes every kernel `.S` file to a
single `as` invocation, not one invocation per file. That has real
consequences, not just a shorter command line:

- The `BEGIN`/`END` macros and the `.set` constants (`PHYS_PAGES_COUNT`,
  `KERNEL_BASE`) defined near the top of `kernel.S` are visible in
  every file assembled after it, the same as if they'd all been
  written in one source file.
- Nothing needs to be declared `.global`. A label in one file resolves
  directly from any other file in the list, because there's no
  separate compilation and no linking-together of separate object
  files happening at the `as` step - it's all one object file already.
- The order files appear in the prerequisite list is therefore
  semantically significant, not cosmetic: a file that uses a macro or
  constant has to come after the file that defines it.
- `kernelEnd.S` holds the storage (the physical page stack, the page
  tables) and the `end` label marking the image's end, so it has to be
  last - anything after it would be storage the `end` label no longer
  marks the end of.

## `--oformat binary`, and why the missing `--32` doesn't matter

Both `ld` invocations pass `--oformat binary`. Normally `ld` produces
an ELF file: machine type, section headers, a symbol table, program
headers - all the structure a loader or debugger uses to make sense of
the bytes. `--oformat binary` strips every bit of that and writes out
only the raw contents of the loadable sections, concatenated. What's
left on disk is exactly what a bootloader needs and nothing else: bytes
at an address, no header to parse.

That's also why leaving off `--32` (or `-m elf_i386`) is harmless even
though `as` and `ld` are running on an x86_64 host and would otherwise
default to 64-bit output. `.code16` and `.code32` directives in the
source drive instruction encoding directly, regardless of what the
assembler's default machine width is - the actual bytes generated
don't depend on it. The one place a 64-bit default could leak through
is the ELF wrapper (a 64-bit `e_machine` field, 64-bit section
headers), and `--oformat binary` throws that wrapper away entirely
before it ever reaches disk.

## Getting a symbol table back

The shipped `kernel.bin` has no symbols - `--oformat binary` discarded
them - so inspecting an address means relinking the same object file
as ELF instead:

```sh
ld -T link_kernel.ld -o kernel.elf kernel.o && nm -n kernel.elf
```

This reuses `kernel.o` (already assembled) and `link_kernel.ld`
(already has the right addresses), just without `--oformat binary`, so
`ld` produces a normal ELF file that `nm` can read.

## `KERNEL_PHYS_END` and the one-byte skew

`KERNEL_PHYS_END = . - VIRTUAL_KERNEL_BASE` in `link_kernel.ld` is
computed from `.`, the location counter - wherever output has reached
by the end of the `SECTIONS` block - not from the `end` symbol that
`kernelEnd.S` defines. That distinction matters because `end` isn't
where the file's `.align 0x1000` left it: there's a `.byte` emitted
after the alignment directive, one byte past a page boundary. The
location counter and `end` normally agree, but the trailing `.byte`
means they don't here - `KERNEL_PHYS_END` should come out
page-aligned (`0x303000`) and instead lands one byte past it
(`0x303001`), because it inherits the location counter's position, not
a hand-computed round number.

## Why the disk image is ~2.1 MB, not 1440 KB

A 1440 KB image is what `make_disk`'s first `dd` lays down - the size
of a standard floppy. The final image ends up around 2.1 MB instead
because `kernel.bin` alone is about 2 MB: the page-table storage
`boot_paging.S` fills in (2 GB of address space worth of page table
entries) lives in `kernelEnd.S`, which assembles into `.text`, and
`--oformat binary` emits every byte of `.text` into the file. There's
no distinction at that point between code and this bulk data - both
are just bytes in the same output section.

## Verifying inside this container

There's no `qemu` in this container, so nothing here actually boots
the image to check it. What's available instead:

- Build cleanly (`make` / `./mk.sh`) and check `md5sum` or exit status.
- `hexdump -C my_boot.img` to read the actual bytes that landed on
  disk - the boot signature, the ATA read, whatever's expected at a
  given offset.
- `kernel.asm`, the listing `as -al` writes during the kernel build,
  to check what a given instruction encoded to.

That's the whole verification loop this task's checks rely on: build,
`md5sum`/`wc -c`, read the listing or the hexdump.

## In the code

| Location | What |
|---|---|
| `link.ld` — `. = 0x7c00` | The boot-sector origin |
| `link_kernel.ld` — `VMA = LMA + VIRTUAL_KERNEL_BASE` | The high/low split |
| `link_kernel.ld` — `KERNEL_PHYS_END` | Taken from the location counter |
| `Makefile` — `$(KERN_NAME) : kernel.S` | Prerequisite order = translation unit |
| `Makefile` — `as -al -o kernel.o` | The `kernel.asm` listing |
| `Makefile` — `seek=1` | Matches `load_kernel`'s LBA |
