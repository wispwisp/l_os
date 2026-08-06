# Educational Comment Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Annotate every section of the l_os sources for a reader fluent in x86 assembly but new to OS development, and add a nine-chapter narrative walkthrough under `docs/notes/`.

**Architecture:** Two layers of documentation. Block comments in the sources explain each section at its site and stay self-sufficient. `docs/notes/` chapters carry the background and history, in boot order. Each inline block names its chapter; each chapter ends with a table of `file:line` anchors. Neither has to be read to understand the other.

**Tech Stack:** GNU `as` (AT&T syntax, x86 32-bit), GNU `ld` linker scripts, GNU `make`, Markdown.

## Global Constraints

- **No instruction is changed.** Not one. This is a comment pass. All seven known bugs are explained in place and left in the code.
- **Build output must be byte-identical.** `as` strips comments, so annotating cannot change a single emitted byte.
- **Baseline hashes**, from a clean build before any edit:
  - `my_boot.bin` — `79ca39bcd2c8254baff292f0fb7c7b1a`, 512 bytes
  - `kernel.bin` — `c28428650b543a9046c9fcacc73feeb7`, 2109441 bytes
- **Verify command**, run at the end of every task:
  ```sh
  make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
  ```
  Both hashes must match the baseline exactly. A differing byte means an instruction was edited — revert and redo the task.
- **Comment character follows each file's existing style.** `#` in `boot.S` and `hello.S`; `//` in `kernel.S`, `boot_paging.S`, `allocator.S`, `clear_screen.S`. Do not unify.
- **Linker scripts take `/* */` only.** `//` and `#` are not comments to `ld`.
- **Makefile comments sit at column 0, never on a tab-indented recipe line.** A `#` inside a recipe is passed to the shell instead of being stripped by `make`.
- **All comments are English.** Existing comments are rewritten and their typos corrected; the two Russian notes are translated.
  - **One exception, ruled by the author:** the design-sketch comments inside `create_process_pages` (`allocator.S:106-120`) are preserved exactly as written, `exeption` typo included. They are a record of design intent, not explanatory prose. Task 6 Step 3 is authoritative on this.
- **Marker prefixes:** `BUG:` for a defect (mechanism + intended form, no fix). `NOTE:` for a deliberate simplification.
- **Do not touch** `build_claudecode_isolation_container.sh`, `run_claudecode_isolation_container.sh`, `claudecode.dockerfile`, `check_grammar.sh`. `claudecode.dockerfile` has unrelated staged changes — leave them staged.
- **Commit authorship:** name `wisp`, email `forworkandtravel@yandex.ru`. Short imperative subject ≤72 chars, body wrapped at 72, explains *why*. No AI-attribution trailers.
  ```sh
  git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "..." -m "..."
  ```

## Verified Addresses

Confirmed via `ld -T link_kernel.ld -o kernel.elf kernel.o && nm -n kernel.elf`. Use these values in comments; do not re-derive them.

| Symbol | Address |
|---|---|
| `main` | `0x80100000` |
| `relocated` | `0x80100002` |
| `boot_paging` | `0x8010000f` |
| `mesg` | `0x80100065` |
| `create_phys_mem_list` | `0x801000b8` |
| `allocate_page` | `0x801000e3` |
| `create_process_pages` | `0x8010016d` |
| `aviable_phys_mem_stack_index` | `0x80100174` — end of kernel code, 372 bytes |
| `aviable_phys_mem_stack_bottom` | `0x80101000` |
| `aviable_phys_mem_stack_top` | `0x80102000` |
| `boot_pgdir` | `0x80102000` — **same address as the stack top** |
| `boot_pgtabels` | `0x80103000` |
| `end` | `0x80303000` |
| `KERNEL_PHYS_END` | `0x303001` — one byte past the page boundary |

## File Structure

| File | Change | Sections |
|---|---|---|
| `boot.S` | Modify | 11 |
| `kernel.S` | Modify | 3 |
| `boot_paging.S` | Modify | 4 |
| `allocator.S` | Modify | 6 |
| `hello.S` | Modify | 1 |
| `clear_screen.S` | Modify | 1 |
| `kernelEnd.S` | Modify | 1 |
| `link.ld` | Modify | 1 |
| `link_kernel.ld` | Modify | 1 |
| `Makefile` | Modify | 1 |
| `docs/notes/00-overview.md` … `08-build-system.md` | Create | 9 chapters |
| `TODO.md` | Modify | 4 new entries |

`CLAUDE.md` is in the spec's scope but has **no task here** — its comment-convention line was already updated in commit `988b557`, alongside the spec. Nothing further is needed there.

Nine tasks, in boot order. Each pairs the inline comments for one subsystem with its docs chapter, so a reviewer can check the cross-references in one sitting.

---

### Task 1: boot.S entry, and the block format

**Files:**
- Modify: `boot.S:1-13`
- Create: `docs/notes/01-real-mode-boot.md`

**Interfaces:**
- Consumes: nothing.
- Produces: **the block format every later task copies.** A ruled `####################` header, an ALL-CAPS section title, and a body of roughly 4–10 lines. Sections whose subject a chapter covers close with a `See docs/notes/NN-name.md.` line; sections with no corresponding chapter (the `BEGIN`/`END` macros, the boot-signature block) simply omit it. Every such reference must be written out in full — `docs/notes/05-paging.md`, never a bare `05-paging.md` — so the Task 9 cross-reference check can find it. Later tasks must match this shape.

- [ ] **Step 1: Replace `boot.S` lines 1-3 with the file header**

```
	####################
	# BOOT SECTOR
	####################
	# The BIOS finds this code by reading the first 512 bytes of
	# the disk, checking for 0x55AA in the last two, and jumping
	# to it at physical 0x7c00 in 16-bit real mode. Everything
	# below has to fit in those 512 bytes.
	#
	# Its job is narrow: get the CPU from real mode into 32-bit
	# protected mode, pull the kernel off the disk, and jump to
	# it. See docs/notes/01-real-mode-boot.md.

	.section .text
	.global start

	# Where load_kernel deposits the kernel: 1 MB, the first
	# address clear of the real-mode and BIOS clutter below.
	.set KERNEL_PLACE, 0x100000
```

- [ ] **Step 2: Annotate `start:` — replace lines 4-13**

```
start:
	.code16

	# No IDT exists yet, so an interrupt here would vector
	# through whatever the BIOS left behind, into code that is
	# about to stop being valid. Mask them until the kernel
	# installs its own handlers.
	cli
	# Clear the direction flag. Every string instruction from
	# here on - the insw below, the rep stosl in boot_paging -
	# assumes it counts upward, and the BIOS makes no promise
	# about DF on entry.
	cld

	# Real-mode addressing is segment * 16 + offset. Zeroing all
	# three segment registers makes offsets equal physical
	# addresses, so linking at 0x7c00 is enough to make every
	# reference in this file resolve correctly.
	xorw	%ax, %ax
	movw	%ax, %ds
	movw	%ax, %es
	movw	%ax, %ss
```

- [ ] **Step 3: Write `docs/notes/01-real-mode-boot.md`**

Must state, with these exact values:
- The BIOS POSTs, then loads sector 0 (512 bytes) to physical `0x7c00` and jumps there. `0x7c00` is convention inherited from the IBM PC 5150, chosen to leave the largest contiguous free block below the 32 KB minimum RAM.
- The CPU starts in 16-bit real mode: addresses are `segment * 16 + offset`, giving a 20-bit (1 MB) space, no memory protection, and BIOS interrupts available.
- Why `cli` (no IDT yet) and `cld` (string direction is not guaranteed).
- Why segments are zeroed, and how that makes `link.ld`'s `. = 0x7c00` sufficient.
- The memory below `0x7c00` is free; the boot sector puts its stack there (covered in chapter 03).
- Close with the **In the code** table:

| Location | What |
|---|---|
| `boot.S:4-5` | `start:`, `.code16` |
| `boot.S:7-8` | `cli` / `cld` |
| `boot.S:10-13` | Segment register zeroing |
| `link.ld:5` | `. = 0x7c00` |

- [ ] **Step 4: Verify the build is byte-identical**

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
```

- [ ] **Step 5: Commit**

```bash
git add boot.S docs/notes/01-real-mode-boot.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Explain the real-mode entry path" -m "Reading boot.S cold means knowing why the BIOS chose 0x7c00 and why
the segment registers must be zeroed before any link-time address is
trustworthy. Neither is visible from the instructions themselves."
```

---

### Task 2: The A20 gate and the GDT

**Files:**
- Modify: `boot.S:15-28` (A20), `boot.S:123-136` (GDT table)
- Create: `docs/notes/02-a20-and-gdt.md`

**Interfaces:**
- Consumes: the block format from Task 1.
- Produces: the `BUG:` block shape — state the mechanism, then the intended form, then whether it bites in practice. Tasks 4, 6, 7, 8 reuse it.

- [ ] **Step 1: Annotate the A20 gate — replace `boot.S:15-28`**

```
	####################
	# A20 GATE
	####################
	# The 8086 had 20 address lines, so an address above 1 MB
	# wrapped around to 0. Enough software relied on that wrap
	# that the IBM AT, which had more lines, put line 20 behind
	# a gate that boots disabled. Until it is opened, physical
	# 0x100000 aliases 0x0 - and 0x100000 is exactly where the
	# kernel is about to be loaded.
	#
	# The gate is driven by the 8042 keyboard controller, which
	# got the job because it had a spare output pin.
	#   port 0x64  status (read) / command (write)
	#   port 0x60  data
	# Status bit 1 set means the input buffer is still full, so
	# poll it clear before each write.
	#
	# Sequence: command 0xd1 ("write output port"), then the
	# byte 0xdf, whose bit 1 is A20.
	#
	# See docs/notes/02-a20-and-gdt.md for the two other ways to
	# do this - port 0x92, and BIOS INT 15h AX=2401.

seta20_1:
	inb	$0x64, %al
	testb	$0x2, %al
	jnz	seta20_1
	# 0xd1 -> port 0x64 :
	movb	$0xd1, %al
	outb	%al, $0x64
seta20_2:
	inb	$0x64, %al
	testb	$0x2, %al
	# BUG (TODO.md): this targets seta20_1, so a controller that
	# is still busy re-runs the 0xd1 command write instead of
	# just re-polling status. It should be seta20_2. Harmless in
	# practice - the controller is idle by this point - but a
	# genuine copy-paste slip.
	jnz	seta20_1
	# 0xdf -> port 0x60 :
	movb	$0xdf, %al
	outb	%al, $0x60
```

- [ ] **Step 2: Annotate the GDT — replace `boot.S:123-136`**

```
	####################
	# THE GDT
	####################
	# Protected mode still addresses memory through segments;
	# there is no way to switch them off. The flat model works
	# around that by defining segments that span all 4 GB, so
	# every linear address equals the offset and segmentation
	# stops mattering. Paging does the real work later.
	#
	# A descriptor is 8 bytes, with the base and limit split
	# across non-contiguous fields - a compatibility scar from
	# the 286, which had only 24-bit bases:
	#   bytes 0-1  limit[15:0]
	#   bytes 2-3  base[15:0]
	#   byte  4    base[23:16]
	#   byte  5    access
	#   byte  6    flags[3:0] : limit[19:16]
	#   byte  7    base[31:24]
	#
	# access 0x9a = present, ring 0, code, readable
	# access 0x92 = present, ring 0, data, writable
	# flags  0xc  = G (limit counts 4 KB units) + D (32-bit)
	#
	# G is what turns a 20-bit limit of 0xfffff into 4 GB.
	#
	# A selector is a byte offset into this table, which is why
	# the code selector is 0x08 and data is 0x10.
	# See docs/notes/02-a20-and-gdt.md.

	.p2align 2
gdt:
	# Entry 0 must be null: selector 0 is the architecturally
	# defined "invalid" value, and loading it faults on use.
	.word 0,0
	.byte 0,0,0,0
	# code seg:
	.word	0xffff, 0x0
	.byte	0x0, 0x9a, 0xcf, 0x0
	# data seg :
	.word	0xffff, 0x0
	.byte	0x0, 0x92, 0xcf, 0x0
gdtdesc:
	# What lgdt reads: a 16-bit limit followed by a 32-bit base.
	# The limit is size-in-bytes minus one, so three entries of
	# 8 bytes gives 0x17.
	.word	0x17	# gdt size limit
	.long	gdt	# gdt address
```

Note: the old `# // gdt addres` typo is corrected to `# gdt address`, and the doubled `# //` prefix is normalised to `#`.

- [ ] **Step 3: Write `docs/notes/02-a20-and-gdt.md`**

Must state:
- A20 history: the 8086 wrap, the AT's gate, why software depended on the wrap.
- The 8042 protocol in full: poll `0x64` bit 1 clear, write `0xd1` to `0x64`, poll again, write `0xdf` to `0x60`.
- The two alternatives — the "fast A20" port `0x92` bit 1, and `INT 15h AX=2401` — and that neither is universally available, which is why the slow 8042 path remains the portable choice.
- The 8-byte descriptor layout table, reproduced from the inline block.
- Decode `0x9a`, `0x92`, `0xcf` bit by bit, including that `0xcf` splits into flags `0xc` and limit`[19:16]` `0xf`.
- Why the flat model exists: segmentation cannot be disabled, so it is neutralised.
- Selector arithmetic: index × 8, hence `0x08` and `0x10`.
- The `BUG` at `boot.S:25`.
- Close with the **In the code** table:

| Location | What |
|---|---|
| `boot.S:15-21` | Poll, then command `0xd1` |
| `boot.S:22-28` | Poll, then data `0xdf` |
| `boot.S:25` | `BUG` — jump targets `seta20_1` |
| `boot.S:124-133` | The three descriptors |
| `boot.S:134-136` | `gdtdesc`, the `lgdt` operand |

- [ ] **Step 4: Verify the build is byte-identical**

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
```

- [ ] **Step 5: Commit**

```bash
git add boot.S docs/notes/02-a20-and-gdt.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Explain the A20 gate and the flat GDT" -m "Both are pure historical accident - a gate on address line 20 and a
descriptor format designed around 24-bit bases - and neither makes
sense from the instructions alone. Also records the seta20_2 jump
target slip found while reading it."
```

---

### Task 3: The protected-mode switch

**Files:**
- Modify: `boot.S:30-59` (switch, `protcseg`, stack, `kernel_entry`), `boot.S:137-140` (signature)
- Create: `docs/notes/03-protected-mode.md`

**Interfaces:**
- Consumes: the block format from Task 1; the GDT descriptors annotated in Task 2 (`lgdt gdtdesc` here refers to them).
- Produces: the `NOTE:` block shape, first used here for the Cyrillic label.

- [ ] **Step 1: Annotate the switch — replace `boot.S:30-38`**

```
	####################
	# ENTER PROTECTED MODE
	####################
	# Three steps, in this order and no other:
	#   1. lgdt - the table must already be valid before any
	#      selector load, because the very next step makes
	#      selector loads meaningful.
	#   2. Set CR0 bit 0 (PE). The CPU is in protected mode from
	#      here, but CS still holds a real-mode segment value.
	#   3. A FAR jump. Only a far jump or far call reloads CS,
	#      and until CS holds a real selector the CPU still
	#      decodes with 16-bit defaults. This is why the switch
	#      cannot end with a near jump.
	# See docs/notes/03-protected-mode.md.

	lgdt    gdtdesc
	movl	%cr0, %eax
	orl	$0x1, %eax # protected mode enable flag
	movl    %eax, %cr0

	# jump into 32-bit code (selector, address)
	ljmp	$0x8, $protcseg
```

The old `# pr.mode enable flag` and `# jump im 32-bit (selecotr, addr)` typos are corrected above.

- [ ] **Step 2: Annotate `protcseg`, the stack, and `kernel_entry` — replace `boot.S:40-59`**

```
	.code32
protcseg:
	# The far jump reloaded CS. The other five segment registers
	# still hold real-mode values and must be pointed at the
	# flat data descriptor before any access uses them. 0x10 is
	# the third GDT entry: 2 * 8 bytes.
	movw	$0x10, %ax # data segment selector
	movw    %ax, %ds
	movw    %ax, %es
	movw    %ax, %fs
	movw    %ax, %gs
	movw    %ax, %ss

	# The stack goes at 0x7c00 and grows downward, into the free
	# low memory below the boot sector. Nothing lives there, so
	# it cannot collide with this code sitting just above it.
	# EBP is zeroed to terminate any frame-pointer walk.
	#
	# NOTE: the 'c' in this label is Cyrillic U+0441, not Latin
	# 'c'. GAS accepts it because the label is never referenced,
	# so no other spelling ever has to match. Left alone here -
	# renaming it would be a code change, not a comment change.
staсk_initialization:
	movl	$0x0, %ebp
	movl	$start, %esp
kernel_entry:
	call	load_kernel
	# Absolute jump to 0x100000, where load_kernel put the image
	# and where link_kernel.ld placed main.
	jmp	KERNEL_PLACE

	# Not reached. If that jump ever returns, stop rather than
	# execute whatever bytes follow.
	hlt
spin:	jmp	spin
```

The label `staсk_initialization` must be pasted with its Cyrillic character intact — copy it from the existing source rather than retyping.

- [ ] **Step 3: Annotate the boot signature — replace `boot.S:137-140`**

```
boot_signature:
	# .org pads with zeros out to byte 510, so the signature
	# lands at exactly 0x1fe no matter how much code precedes
	# it. If the code ever exceeds 510 bytes, `as` errors here
	# instead of silently truncating - which makes this
	# directive the 512-byte budget check.
	.org	0x0200-2
	# The BIOS treats a device as bootable only if these two
	# bytes are present.
	.byte	0x55
	.byte	0xAA
```

- [ ] **Step 4: Write `docs/notes/03-protected-mode.md`**

Must state:
- What protected mode buys: 32-bit addressing, privilege rings, and the paging that chapter 05 turns on.
- The three-step sequence and why the order is forced.
- Why a far jump is required: it is the only way to reload `CS`, and `CS`'s descriptor carries the D bit that selects 16- vs 32-bit decoding. A near jump would leave the CPU decoding 32-bit instructions with 16-bit defaults.
- The pipeline-flush framing: the far jump also discards instructions prefetched under the old mode.
- Why the other five segment registers must be reloaded separately.
- Stack placement at `0x7c00` growing down, and that this is why nothing needs to be reserved for it.
- The `0x55AA` signature and the `.org` trick as a build-time size assertion.
- Close with the **In the code** table:

| Location | What |
|---|---|
| `boot.S:32` | `lgdt gdtdesc` |
| `boot.S:33-35` | `CR0.PE` |
| `boot.S:38` | `ljmp $0x8, $protcseg` |
| `boot.S:41-48` | Data selector reload |
| `boot.S:50-52` | Stack at `0x7c00` |
| `boot.S:138-140` | `.org` and `0x55AA` |

- [ ] **Step 5: Verify the build is byte-identical**

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
```

If `my_boot.bin` differs, the most likely cause is that the Cyrillic label was retyped in Latin. That changes no bytes, so a hash mismatch instead means an instruction was altered — but check the label anyway with `grep -n 'sta.k_initialization' boot.S | cat -A`.

- [ ] **Step 6: Commit**

```bash
git add boot.S docs/notes/03-protected-mode.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Explain the protected-mode switch and its ordering" -m "The far jump looks like an ordinary control transfer but is load-
bearing: it is the only instruction that reloads CS, and CS carries
the bit that selects 32-bit decoding. Worth stating outright, since
substituting a near jump breaks the machine in a way that is hard to
diagnose."
```

---

### Task 4: ATA PIO disk read

**Files:**
- Modify: `boot.S:62-118`
- Create: `docs/notes/04-ata-pio.md`

**Interfaces:**
- Consumes: the block format from Task 1; the `BUG:` shape from Task 2.
- Produces: nothing later tasks depend on. This closes out `boot.S`.

- [ ] **Step 1: Annotate `wait_disk` — replace `boot.S:62-72`**

```
	####################
	####################

	####################
	# ATA PIO: WAIT FOR THE DRIVE
	####################
	# The disk is not memory-mapped. It is driven through eight
	# I/O ports, 0x1f0-0x1f7, and seven of them are only valid
	# to touch when the drive says it is not busy.
	#
	# Status register (0x1f7):
	#   bit 7  BSY   busy; every other register is invalid
	#   bit 6  DRDY  ready to accept a command
	#   bit 3  DRQ   a sector is ready to transfer
	#   bit 0  ERR   the last command failed
	#
	# Masking to bits 7:6 and comparing against 0x40 means "BSY
	# clear and DRDY set". Note what it does not check: DRQ, so
	# this waits for the drive to be idle rather than for data
	# to be available; and ERR, so a failed read cannot be
	# distinguished from a good one.
	#
	# NOTE: no timeout. A drive that never clears BSY hangs the
	# boot here forever. Real drivers bound the wait.
	# See docs/notes/04-ata-pio.md.

wait_disk:
	movw	$0x1f7, %dx
testwd:	inb	(%dx), %al
	# inb loaded only AL, so AH is stale - harmless, because the
	# comparison below is 8-bit.
	andw	$0xffc0, %ax
	cmpb	$0x40, %al
	jne	testwd
	ret
```

- [ ] **Step 2: Annotate `load_kernel` — replace `boot.S:74-118`**

```
	####################
	# ATA PIO: READ THE KERNEL
	####################
	# Programmed I/O: write the sector address into the port
	# registers, issue the read command, then pull the data out
	# of the data port a word at a time with the CPU. No DMA and
	# no interrupts - which is what you want in a boot sector,
	# where there is no driver stack and no IDT.
	#
	# Port map:
	#   0x1f2  sector count
	#   0x1f3  LBA[7:0]
	#   0x1f4  LBA[15:8]
	#   0x1f5  LBA[23:16]
	#   0x1f6  drive select + LBA[27:24]
	#   0x1f7  command (write) / status (read)
	#
	# Ports 0x1f3-0x1f5 are still named after the CHS geometry
	# fields they used to hold. In LBA mode - selected by bit 6
	# of 0x1f6 - they are simply the low 24 bits of a linear
	# sector number.
	# See docs/notes/04-ata-pio.md.

load_kernel:
	call wait_disk

	# BUG (TODO.md): one sector, 512 bytes, of a kernel image
	# that is 2 MB. It works today only because the kernel's
	# code ends at 0x80100174 (372 bytes) and everything past
	# that is storage the kernel writes rather than reads back
	# from disk. The next routine added can silently run off the
	# end of what was loaded. Raising this count and the insw
	# counter below has to happen together.
	movw	$0x1f2, %dx
	movb	$0x1, %al # sector count = 1
	outb	%al, (%dx)

	# LBA 1: the sector straight after this boot sector, which
	# is where the Makefile's `dd ... seek=1` wrote the kernel.
	movb	$0x1, %al
	# DX is 0x01f2, so DH is 0x01 and DL is 0xf2. Only DL has to
	# change to walk to the next port.
	movb	$0xf3, %dl
	outb	%al, (%dx)
	movb	$0x0, %al # LBA[15:8]
	movb	$0xf4, %dl
	outb	%al, (%dx)
	movb	$0x0, %al # LBA[23:16]
	movb	$0xf5, %dl
	outb	%al, (%dx)
	# 0xe0 = 1110 0000. Bits 7 and 5 are hardwired to 1, bit 6
	# selects LBA addressing, bit 4 picks drive 0 (master), and
	# the low nibble carries LBA[27:24].
	movb	$0xe0, %al
	movb	$0xf6, %dl
	outb	%al, (%dx)

	# 0x20 = READ SECTORS, with retry
	movb	$0x20, %al
	movb	$0xf7, %dl
	outb	%al, (%dx)

	call wait_disk

	# 0x100 words = 512 bytes = the one sector requested above.
	# insw reads a word from the port in DX into [EDI] and
	# advances EDI, because DF is clear.
	movl	$KERNEL_PLACE, %edi
	movl	$0x100, %ecx
	movw	$0x1f0, %dx
	cld
	# NOTE: repnz on a non-comparison string instruction behaves
	# exactly as rep - INS ignores the flag-testing half of the
	# F2 prefix. rep is the idiomatic spelling.
	repnz insw (%dx), (%edi)

	ret
```

The old comments corrected here: `0x1f3: (SECTOR COUNT PORT)` (it is LBA-low; `0x1f2` is the count), the bare `0xf5`/`0xf6`/`0xf7` port numbers (they are `0x1f5`/`0x1f6`/`0x1f7`), `sector count - 1`, the self-contradictory `read sector one (read sector two)`, `insl` where the code uses `insw`, and `wich`.

- [ ] **Step 3: Write `docs/notes/04-ata-pio.md`**

Must state:
- What PIO means and how it contrasts with DMA; why a boot sector uses PIO.
- The full `0x1f0`–`0x1f7` port table, including `0x1f1` (error/features), which the code never touches.
- The status register bit table, and that this code checks neither DRQ nor ERR.
- The CHS-to-LBA naming history, and how `0x1f6` bit 6 switches interpretation.
- The command sequence in order, ending with `0x20` READ SECTORS.
- That `0x1f2 = 0` means 256 sectors, not zero — the encoding trick behind the single-sector `BUG`.
- The `BUG`: one sector loaded, 372 bytes of code, and why growing the kernel requires changing `0x1f2` and the `insw` count together.
- The `NOTE`s: no timeout, and `repnz` vs `rep`.
- Close with the **In the code** table:

| Location | What |
|---|---|
| `boot.S:66-72` | `wait_disk`, the BSY/DRDY poll |
| `boot.S:79-81` | Sector count — `BUG` |
| `boot.S:84-95` | LBA bytes into `0x1f3`–`0x1f5` |
| `boot.S:96-99` | Drive select, `0xe0` |
| `boot.S:101-105` | Command `0x20` |
| `boot.S:109-116` | The `insw` transfer |

- [ ] **Step 4: Verify the build is byte-identical**

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
```

- [ ] **Step 5: Commit**

```bash
git add boot.S docs/notes/04-ata-pio.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Explain the ATA PIO read and its port protocol" -m "Half the constants here were mislabelled - 0x1f3 called the sector
count port, several ports written without their 0x1f prefix - which
makes the sequence impossible to follow against a datasheet. Also
records that only one sector is loaded, the constraint most likely to
bite when the kernel grows."
```

---

### Task 5: Kernel entry and paging

**Files:**
- Modify: `kernel.S` (all), `boot_paging.S` (all)
- Create: `docs/notes/05-paging.md`

**Interfaces:**
- Consumes: the block format from Task 1, translated to `//` comments — the ruled header becomes `// ------------------------------------------------------`.
- Produces: the `KERNEL_BASE` subtraction idiom explanation, which Task 6 and Task 8 both refer back to.

- [ ] **Step 1: Annotate the macros and constants — replace `kernel.S:1-18`**

```
	// ------------------------------------------------------
	// CALLING CONVENTION
	// ------------------------------------------------------
	// Every routine in this kernel opens with BEGIN and closes
	// with END. Together they maintain the standard frame
	// pointer chain - EBP points at the caller's saved EBP - so
	// a debugger can walk the stack.
	//
	// There is no C here and no ABI to honour, so arguments and
	// return values travel in registers. The `// long(void)` or
	// `// void(eax)` comment above each label is that routine's
	// signature. These macros preserve only EBP; callers must
	// save anything else they care about.

	.macro BEGIN
	pushl	%ebp
	movl	%esp, %ebp
	.endm

	.macro END
	movl	%ebp, %esp
	popl	%ebp
	ret
	.endm
	/////////////////////////////////
	/////////////////////////////////
	/////////////////////////////////

	// 0x400 = 1024 pages = 4 MB handed to the allocator. A
	// fixed count because there is no memory map yet: nothing
	// has asked the BIOS (INT 15h AX=E820) how much RAM
	// actually exists.
	.set	PHYS_PAGES_COUNT, 0x400
	// The kernel lives in the top 2 GB of the virtual address
	// space. Subtracting this from a virtual address yields the
	// physical one, which is what any code running before
	// CR0.PG has to do by hand.
	.set	KERNEL_BASE, 0x80000000
```

- [ ] **Step 2: Annotate `main` — replace `kernel.S:20-36`**

```
	.code32
	.section .text
	.global main
main:
	// Entered by the boot sector's `jmp 0x100000` with paging
	// still off, so this is executing at its physical address
	// rather than the 0x80100000 it was linked for. boot_paging
	// builds the tables, turns paging on, and jumps back to
	// `relocated` below - at which point the two agree.
	// See docs/notes/05-paging.md.
	jmp boot_paging
relocated:
	// Paging is on; execution is now at the linked virtual
	// address.

	call create_phys_mem_list

	call mprint

	// Nothing to return to.
	hlt
elop:	jmp elop
```

- [ ] **Step 3: Annotate `boot_paging.S` — insert this header above line 1**

```
	// ------------------------------------------------------
	// BOOT PAGE TABLES
	// ------------------------------------------------------
	// Runs with paging still off, executing near physical
	// 0x100000 while every symbol here was linked at
	// 0x80100000. That is why each one is written as
	// `symbol - KERNEL_BASE`: the assembler resolves the symbol
	// to its virtual address and the subtraction converts it
	// back to the physical one.
	//
	// 32-bit x86 paging is two levels. A linear address splits
	// 10 / 10 / 12: the top 10 bits index the page directory,
	// the next 10 index a page table, the last 12 are the byte
	// offset inside a 4 KB page. Directory and table entries
	// both hold a page-aligned physical address in their top 20
	// bits and flags in the low 12.
	//
	// Flag 0x7 = P | RW | US: present, writable, and reachable
	// from ring 3. US is set on everything here, which is wrong
	// for kernel memory but harmless while there is no user
	// mode to protect against.
	// See docs/notes/05-paging.md.
```

- [ ] **Step 4: Annotate the directory build — replace `boot_paging.S:2-18`**

```
	// 0) PAGE DIRECTORY
	// Two windows onto the same physical memory:
	//   entry 0         -> [0, 4 MB)            identity
	//   entries 512-1023 -> [KERNEL_BASE, 4 GB)  kernel
	// The identity map exists purely so the instruction after
	// CR0.PG is set is still fetchable: execution is at a
	// physical address at that moment, and without entry 0 the
	// very next fetch would page fault.
	movl	$boot_pgtabels - KERNEL_BASE + 0x7, %ebx	# (+ 0x7 is the P|RW|US mask) to the 4 KB-aligned address of the page tables
	movl	$boot_pgdir - KERNEL_BASE, %edi
	// 0.1) entry 0: [0, 4 MB)
	movl	%ebx,%eax
	stosl
	// 0.2) entries 1-511 zeroed. The whole user half is left
	// unmapped, so a stray access below KERNEL_BASE faults
	// instead of quietly succeeding.
	xorl	%eax,%eax
	movl	$0x1ff, %ecx
	rep	stosl
	// 0.3) entries 512-1023: [KERNEL_BASE, 4 GB). Entry 512
	// points at the same first page table as entry 0, which is
	// exactly what makes virtual 0x80100000 resolve to physical
	// 0x100000. Each following entry steps one 4 KB table on.
	movl    $0x200,%ecx
	movl	%ebx,%eax
boot_paging_loop1:
	stosl
	addl    $0x1000, %eax
	loop    boot_paging_loop1
```

- [ ] **Step 5: Annotate the table fill and the paging enable — replace `boot_paging.S:20-39`**

```
	// 1) PAGE TABLE ENTRIES
	// 0x80000 entries x 4 KB = 2 GB, mapped straight through:
	// entry N covers physical N * 4 KB. Filling all of it up
	// front means there is no page fault handler to write and
	// no lazy mapping to get right - at the cost of 2 MB of
	// tables, which is most of why kernel.bin is 2 MB.
	movl	$boot_pgtabels - KERNEL_BASE, %edi
	movl	$0x7, %eax
	movl	$0x80000, %ecx
loop_pgtbl_entry:
	stosl
	addl	$0x1000, %eax
	loop	loop_pgtbl_entry

	// 2) POINT CR3 AT THE DIRECTORY
	// CR3 takes the physical address - the MMU is not yet
	// translating anything, and could not translate this even
	// if it were.
	movl	$boot_pgdir - KERNEL_BASE, %eax
	movl	%eax, %cr3

	// CR0 bit 31 (PG). From the next instruction on, every
	// address goes through the MMU. This survives only because
	// of the identity map installed above.
	movl	%cr0, %eax
	orl	$0x80000000, %eax
	movl	%eax, %cr0

	// An indirect jump through a register, not a near relative
	// one. A relative jump would keep executing down in the
	// identity map; loading the absolute virtual address of
	// `relocated` and jumping through it is what actually moves
	// execution into the kernel window. The identity map is
	// dead weight from here and could be torn down.
	mov     $relocated, %eax
	jmp     *%eax
```

- [ ] **Step 6: Write `docs/notes/05-paging.md`**

Must state:
- The 10/10/12 split and the two-level walk.
- PDE and PTE bit layout: top 20 bits are a physical frame number, low 12 are flags. Decode `0x7` as P|RW|US, and name the others (PWT, PCD, A, D, PS).
- Why `boot_pgdir` is exactly `0x1000`: 1024 entries × 4 bytes.
- The higher-half trick: the kernel is linked at `0x80100000` but loaded at `0x00100000`, and PDE 512 pointing at the same table as PDE 0 is what reconciles them. `0x80000000 >> 22 = 512`.
- Why an identity map is mandatory for the instruction immediately after `CR0.PG`, and that it becomes removable afterwards.
- Why the jump must be indirect/absolute rather than near/relative.
- The pre-built 2 GB of tables: `0x80000` entries × 4 bytes = `0x200000` = 2 MB = 512 tables, spanning physical `0x103000`–`0x303000`, which lands exactly on `end`. The tradeoff — no fault handler needed, 2 MB of image paid for it.
- That `US` is set on kernel pages, and why that is a latent problem once ring 3 exists.
- Close with the **In the code** table:

| Location | What |
|---|---|
| `kernel.S:27` | `jmp boot_paging` |
| `boot_paging.S:3-4` | The `- KERNEL_BASE` idiom |
| `boot_paging.S:6-7` | PDE 0, identity map |
| `boot_paging.S:9-11` | PDEs 1–511 zeroed |
| `boot_paging.S:13-18` | PDEs 512–1023, the kernel window |
| `boot_paging.S:21-27` | 2 GB of PTEs |
| `boot_paging.S:30-31` | `CR3` |
| `boot_paging.S:34-36` | `CR0.PG` |
| `boot_paging.S:38-39` | The indirect jump to the virtual address |

- [ ] **Step 7: Verify the build is byte-identical**

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
```

- [ ] **Step 8: Commit**

```bash
git add kernel.S boot_paging.S docs/notes/05-paging.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Explain the higher-half mapping and paging enable" -m "The `symbol - KERNEL_BASE` idiom is everywhere in boot_paging.S and
means nothing until you know the code is running 2 GB below where it
was linked. Same for the indirect jump at the end, which reads like a
stylistic choice and is actually what moves execution into the kernel
window."
```

---

### Task 6: The physical page allocator

**Files:**
- Modify: `allocator.S` (all), `kernelEnd.S` (all)
- Create: `docs/notes/06-phys-allocator.md`

**Interfaces:**
- Consumes: the block format from Task 1; the `BUG:` shape from Task 2; the `KERNEL_BASE` explanation from Task 5.
- Produces: nothing later tasks depend on.

This task carries four of the seven bugs. Annotate every one; change no instruction.

- [ ] **Step 1: Annotate `create_phys_mem_list` — replace `allocator.S:1-19`**

```
	// ------------------------------------------------------
	// PHYSICAL PAGE ALLOCATOR
	// ------------------------------------------------------
	// A LIFO stack of free physical page addresses: push to
	// free, pop to allocate. Constant time both ways and about
	// as simple as an allocator gets. What it cannot do is
	// satisfy a request for physically contiguous pages, which
	// anything driving DMA eventually needs.
	//
	// Storage lives in kernelEnd.S.
	// See docs/notes/06-phys-allocator.md.

	// void(void)
	// Fills the stack with PHYS_PAGES_COUNT (1024) page
	// addresses stepping 4 KB from the end of the kernel image,
	// so the allocator never hands out memory the kernel is
	// sitting on.
	//
	// BUG (TODO.md): KERNEL_PHYS_END is 0x303001, not 0x303000.
	// kernelEnd.S emits a .byte after its .align, so every
	// address pushed here is one byte past a page boundary.
	// Handing one of these to CR3 or storing it in a PDE would
	// put stray bits in the flag field.
create_phys_mem_list:
	BEGIN
	pushl	%edi

	cld
	movl	$aviable_phys_mem_stack_bottom, %edi
	movl	$KERNEL_PHYS_END, %eax
	movl	$PHYS_PAGES_COUNT, %ecx
loop_create_phys_mem_list:
	stosl
	addl	$0x1000, %eax
	loop	loop_create_phys_mem_list

	// The index points at the topmost occupied slot, so it
	// starts one below the count.
	movl	$PHYS_PAGES_COUNT - 1, aviable_phys_mem_stack_index

	popl	%edi
	END
```

- [ ] **Step 2: Annotate `allocate_page` and `free_page` — replace `allocator.S:22-51`**

```
	// long(void)
	// Returns a physical page address in EAX, or 0 when the
	// stack is empty. Clobbers ECX.
allocate_page:	
	BEGIN

	movl	aviable_phys_mem_stack_index, %ecx		#// to mem
	// The stack is empty when the index falls below zero.
	// Index 0 cannot double as the empty marker, because slot 0
	// holds a real, allocatable page.
	//
	// BUG (TODO.md): `test %ecx, 0x0` does not compare ECX
	// against zero. In AT&T syntax a bare 0x0 is a memory
	// operand, so this ANDs ECX with the dword at absolute
	// address 0 and sets flags from that. Which branch runs is
	// decided by whatever physical page 0 happens to hold.
	// The intended instruction is `test %ecx, %ecx`.
	test	%ecx, 0x0 #// index zero is a page too
	jnz	allocate_page_1
	xor	%eax,%eax		# // return zero - no memory available
	jmp	allocate_page_exit	# // TODO: could return directly instead of jumping to the exit
allocate_page_1:
	//	leal	(%eax,%ecx,4), %edx
	// Pop: read the top slot, then move the index down.
	movl	aviable_phys_mem_stack_bottom(,%ecx,4), %eax	#// to mem
	decl	%ecx
	movl	%ecx, aviable_phys_mem_stack_index		#// to mem
allocate_page_exit:
	// returns EAX

	END


	// void(eax)
	// Pushes the page in EAX back onto the free stack.
	// Clobbers ECX.
	//
	// NOTE: no bounds check. Freeing more pages than were ever
	// allocated walks the index past the top of the stack and
	// writes past it - and the next thing in kernelEnd.S is
	// boot_pgdir, at the very same address. An overflow here
	// corrupts the page directory.
free_page:
	BEGIN

	movl	aviable_phys_mem_stack_index, %ecx		#// to mem
	incl	%ecx
	movl	%eax, aviable_phys_mem_stack_bottom(,%ecx,4)	#// to mem
	movl	%ecx, aviable_phys_mem_stack_index		#// to mem

	END
```

The Russian note on the `test` line is translated in place to `#// index zero is a page too`. The commented-out `leal` line is left exactly as it is — it is the author's dead code, not a comment to rewrite.

- [ ] **Step 3: Annotate the process stubs — replace `allocator.S:57-122`**

```
	//void(void)
	// NOTE: unfinished. It allocates a page directory and a
	// couple of tables, but the flags are placeholders - every
	// `addl $0x0, %eax` is where a P|RW|US mask belongs - and
	// nothing is returned to the caller.
allocate_process:
	BEGIN
	pushl	%edi
	pushl	%esi
	pushl	%ebx

	// page for process page dir
	call	allocate_page
	movl	%eax, %ebx

	// page for page dir entry
	// 1) make first entry:
	call	allocate_page
	addl	$0x0,%eax
	movl	%eax,(%ebx)

	// lazy... do only one page
	// BUG (TODO.md): allocate_page clobbers ECX - it loads the
	// stack index into it - so by the time the dereference two
	// lines down runs, ECX no longer holds the page saved here.
	// The value has to survive the call, on the stack or in a
	// callee-saved register.
	movl	%eax, %ecx
	call	allocate_page
	addl	$0x0,%eax
	movl	%eax, (%ecx)

	// 2) make kernel mappings:
	// Entry 512 is the first PDE of the kernel window, the same
	// slot boot_paging.S fills for the boot directory.
	call	allocate_page
	addl	$0x0,%eax
	movl	%eax,512*4(%ebx)
	// todo movl (%eax), %esi; etc...


	popl	%ebx
	popl	%esi
	popl	%edi
	END



	// void(edi)
	// Zeroes one 4 KB page. The count is right: 0x400 dwords is
	// exactly 4096 bytes.
	//
	// BUG (TODO.md): neither EDI nor the direction flag is set
	// up, so this zeroes 4 KB starting wherever EDI happened to
	// point, running in whichever direction DF happened to
	// select. Unusable until the caller's contract is fixed.
zero_page:
	BEGIN

	movl	$0x400, %ecx
	xorl	%eax,%eax
	rep	stosl

	END
	
	// void(void)
	// NOTE: a design sketch, not code - the comments below are
	// the intended layout of a process address space and
	// nothing here is implemented. This is where the work
	// stopped.
create_process_pages:
	BEGIN

	// kernel mappings (KERNEL BASE AND UP)

	// kernel user top:
	// cpu(0...) kernel stack for process
	// cpu(...n) kernel stack for process
	
	// user system top:
	// map user page dir (top)
	// map user page tables (top)
	// map exeption stack (?)

	// user program top:
	// program stack
	// heap
	// code

	END
```

The author's design-sketch comments inside `create_process_pages` are kept verbatim, `exeption` typo included — they are the record of an intent, not prose to polish.

- [ ] **Step 4: Annotate `kernelEnd.S` — replace the whole file**

```
	// ------------------------------------------------------
	// KERNEL STORAGE
	// ------------------------------------------------------
	// All the writable memory the kernel needs. This file must
	// stay LAST in the Makefile's prerequisite list: every .S
	// file is assembled as one translation unit, so the `end`
	// marker below only marks the true end of the image if
	// nothing follows it.
	//
	// None of this is in .bss, so all of it is emitted into
	// kernel.bin - 2 MB of mostly zeros, which is why the disk
	// image comes out at 2.1 MB rather than a 1440 KB floppy.
	// See docs/notes/06-phys-allocator.md.

aviable_phys_mem_stack_index:	.long 0x0
	.align 0x1000
aviable_phys_mem_stack_bottom:	.space PHYS_PAGES_COUNT * 4
	// NOTE: this label and boot_pgdir below both resolve to
	// 0x80102000 - the stack ends exactly where the page
	// directory starts. Since free_page has no bounds check,
	// overflowing the stack writes straight into the page
	// directory.
aviable_phys_mem_stack_top:

	.align 0x1000
	// 1024 entries x 4 bytes = exactly one 4 KB page.
boot_pgdir: .space 0x1000

	.align	0x1000
	// 0x80000 entries x 4 bytes = 2 MB = 512 page tables,
	// covering 2 GB. Filled by boot_paging.S.
boot_pgtabels: .space 0x80000 * 4

	
	// BUG (TODO.md): the .byte lands AFTER the .align, so while
	// `end` itself sits at 0x80303000 the location counter
	// finishes at 0x80303001 - and link_kernel.ld computes
	// KERNEL_PHYS_END from the counter, giving 0x303001. Every
	// page address create_phys_mem_list pushes inherits that
	// one-byte skew.
end: .align 0x1000
	.byte 0x0
```

- [ ] **Step 5: Write `docs/notes/06-phys-allocator.md`**

Must state:
- Why a page allocator exists at all, and why LIFO: O(1) both ways, trivial to write, no contiguity.
- The three storage objects and their addresses: index at `0x80100174`, stack from `0x80101000` to `0x80102000`, holding 1024 4-byte entries.
- `PHYS_PAGES_COUNT` is `0x400` = 4 MB, a hardcoded guess because nothing has queried `INT 15h AX=E820` for a real memory map.
- The push/pop asymmetry: `create_phys_mem_list` sets the index to `COUNT - 1`, `allocate_page` reads at `[index]` then decrements, `free_page` increments then writes at `[index]`. Consistent, but the empty and full boundaries are both unguarded.
- All four bugs in this subsystem: the `test` operand, the `KERNEL_PHYS_END` skew, the `%ecx` clobber, and `zero_page`'s unset `%edi`.
- The `free_page` overflow landing in `boot_pgdir`, with both symbols at `0x80102000` as evidence.
- What is left to build: `allocate_process` returns nothing and uses placeholder flags; `create_process_pages` is comments only. This is where the work stopped.
- Close with the **In the code** table:

| Location | What |
|---|---|
| `allocator.S:2` | `create_phys_mem_list` — `BUG`, unaligned base |
| `allocator.S:23` | `allocate_page` |
| `allocator.S:27` | `BUG` — `test %ecx, 0x0` |
| `allocator.S:43` | `free_page` — `NOTE`, no bounds check |
| `allocator.S:58` | `allocate_process` — unfinished |
| `allocator.S:75` | `BUG` — `%ecx` clobbered by the call |
| `allocator.S:94` | `zero_page` — `BUG`, `%edi` never set |
| `allocator.S:103` | `create_process_pages` — sketch only |
| `kernelEnd.S:3-4` | The stack, and where it ends |
| `kernelEnd.S:13-14` | `BUG` — `.byte` after `.align` |

- [ ] **Step 6: Verify the build is byte-identical**

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
```

`kernel.bin` is the sensitive one here — `kernelEnd.S` controls the image size, so a stray edit to `.space` or `.align` shows up immediately as a size change.

- [ ] **Step 7: Commit**

```bash
git add allocator.S kernelEnd.S docs/notes/06-phys-allocator.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Explain the page allocator and its four defects" -m "This is where the work stopped, so it is the code most likely to be
picked up cold. Four separate defects live here - the test operand,
the unaligned KERNEL_PHYS_END, an ECX clobbered across a call, and a
zero_page with no destination - and the stack overflows directly into
the page directory, which the symbol addresses make plain."
```

---

### Task 7: VGA text output

**Files:**
- Modify: `hello.S` (all), `clear_screen.S` (all)
- Create: `docs/notes/07-vga-text.md`

**Interfaces:**
- Consumes: the block format from Task 1; the `BUG:` shape from Task 2.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Annotate `hello.S` — replace the whole file**

```
	# ------------------------------------------------------
	# VGA TEXT OUTPUT
	# ------------------------------------------------------
	# NOTE: this string sits in .text, ahead of the code that
	# reads it. Safe only because nothing ever jumps to mesg -
	# execution always enters at mprint. .rodata would be the
	# conventional home, and link_kernel.ld already declares
	# one.
	# See docs/notes/07-vga-text.md.
mesg:
	.string "Memory initialized"

	# void(void)
	# Writes mesg to the top-left of the screen.
mprint:
	BEGIN
	pushl	%edi
	pushl	%esi

	call	clr_scr

	# VGA text mode maps the screen into memory at 0xb8000, two
	# bytes per cell: the character code, then its attribute. So
	# the loop stores one byte from the string and one byte of
	# attribute, and EDI lands on the next cell by itself.
	cld
	movl	$0xb8000,%edi
	movl	$mesg,%esi
print_loop:
	lodsb
	testb	%al, %al
	jz	print_loop_exit
	stosb
	# 0x07 = light grey on black. The low nibble is foreground,
	# the high nibble background; bit 7 is either blink or
	# bright-background, depending on how the adapter is
	# configured.
	movb	$7,%al
	stosb
	jmp	print_loop

print_loop_exit:
	popl	%esi
	popl	%edi
	END
```

- [ ] **Step 2: Annotate `clear_screen.S` — replace the whole file**

```
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
```

- [ ] **Step 3: Write `docs/notes/07-vga-text.md`**

Must state:
- Memory-mapped text output: the adapter reads `0xb8000` continuously and renders it; writing there puts characters on screen with no driver, no BIOS call, and no I/O port involved.
- The 2-byte cell — character code, then attribute — and that this is what makes `stosb` twice per character work out.
- The attribute byte layout: bits 0–3 foreground, 4–6 background, bit 7 blink or bright background. `0x07` = light grey on black; `0x00` = black on black, hence blank.
- The arithmetic: 80 × 25 = 2000 cells = 4000 bytes, `0xb8000`–`0xb8fa0`.
- The `BUG`, worked through: `0xf9e` words = 7996 bytes = 3996 bytes past the end, reaching `0xb9f3c`; correct value `0x7d0`.
- The `NOTE` about `mesg` living in `.text`.
- Close with the **In the code** table:

| Location | What |
|---|---|
| `hello.S:1-2` | `mesg` in `.text` |
| `hello.S:11-12` | `0xb8000`, source and destination |
| `hello.S:14-20` | The character/attribute pair loop |
| `hello.S:18` | Attribute `0x07` |
| `clear_screen.S:7-8` | Destination and the blank cell value |
| `clear_screen.S:10` | `BUG` — byte count used as a word count |

- [ ] **Step 4: Verify the build is byte-identical**

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
```

- [ ] **Step 5: Commit**

```bash
git add hello.S clear_screen.S docs/notes/07-vga-text.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Explain VGA text output and the clear-screen overrun" -m "The two-bytes-per-cell layout is the whole reason the print loop
stores twice per character, and it is also what makes clr_scr wrong:
a byte count passed to a word-at-a-time store clears twice the
screen. Both worth stating where the constants are."
```

---

### Task 8: The build system

**Files:**
- Modify: `link.ld`, `link_kernel.ld`, `Makefile`
- Create: `docs/notes/08-build-system.md`

**Interfaces:**
- Consumes: the `KERNEL_BASE` explanation from Task 5 — `link_kernel.ld`'s VMA/LMA split is the other half of it.
- Produces: nothing later tasks depend on.

Comment syntax changes here. Linker scripts take `/* */` only. Makefile comments must sit at column 0, never on a tab-indented recipe line.

- [ ] **Step 1: Annotate `link.ld` — replace the whole file**

```
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
```

- [ ] **Step 2: Annotate `link_kernel.ld` — replace the whole file**

```
/* The kernel is LOADED at physical 1 MB but LINKED to run at
   0x80100000, that same address plus KERNEL_BASE. Any code
   running before CR0.PG is therefore executing 2 GB below the
   address the linker gave it - which is exactly why
   boot_paging.S writes every symbol as `symbol - KERNEL_BASE`.
   See docs/notes/08-build-system.md and
   docs/notes/05-paging.md. */

ENTRY(main)

VIRTUAL_KERNEL_BASE = 0x80000000;
LMA = 0x00100000;                 /* load address: where the boot sector puts it */
VMA = LMA + VIRTUAL_KERNEL_BASE;  /* run address:  where it is linked to execute */
/*VMA = 0x80100000;*/
SECTIONS
{
. = VMA;
.text      ALIGN (0x1000) :   {  *(.text)          }
.rodata    ALIGN (0x1000) :   {  *(.rodata*)       }
.data      ALIGN (0x1000) :   {  *(.data)          }
.bss :                        {  *(COMMON) *(.bss) }
/DISCARD/ :                   {  *(.comment)       }
/* The physical address just past the kernel image, handed to
   create_phys_mem_list so the allocator starts giving out
   memory beyond the kernel rather than on top of it.

   This is taken from the location counter, not from the `end`
   symbol - which is why the stray .byte at the bottom of
   kernelEnd.S makes it 0x303001 instead of 0x303000. */
KERNEL_PHYS_END = . - VIRTUAL_KERNEL_BASE;
}	      
```

- [ ] **Step 3: Annotate the `Makefile` — replace the whole file**

Every comment below is at column 0. Do not indent any of them onto a recipe line.

```make
.PHONY : all clean

# Two independently linked binaries, because they run at
# different addresses and have different constraints: the boot
# sector must be exactly 512 bytes at 0x7c00, the kernel is
# linked high and loaded low.
# See docs/notes/08-build-system.md.
BOOT_NAME:=my_boot.bin
KERN_NAME:=kernel.bin
#CFLAGS:=-T link_kernel.ld -Iinclude -Wall -fno-builtin -nostdinc -nostdlib
#LFLAGS:=--oformat binary -T link.ld
#LIBS:=

DISK_NAME:=my_boot.img


all : $(BOOT_NAME) $(KERN_NAME)

$(BOOT_NAME) :
	as -o boot.o boot.S
	ld --oformat binary -T link.ld -o $@ boot.o

# All the .S files go through ONE `as` invocation, in this
# order, so they form a single translation unit: the BEGIN/END
# macros and the .set constants declared in kernel.S are visible
# in every later file, and nothing needs .global. kernelEnd.S
# must stay last - it holds the storage and the `end` marker.
#
# A new .S file goes in this list BEFORE kernelEnd.S.
#
# -al writes an assembly listing to kernel.asm. Since qemu is
# not available in this container, reading that listing is how
# encoded bytes get checked.
#
# Note that no --32 or -m elf_i386 is passed even though the
# host is x86_64. It works because .code16/.code32 drive code
# generation directly, and --oformat binary strips the ELF
# wrapper that would otherwise carry the wrong machine type.
$(KERN_NAME) : kernel.S boot_paging.S hello.S clear_screen.S allocator.S kernelEnd.S
	as -al -o kernel.o $^ > kernel.asm
	ld --oformat binary -T link_kernel.ld -o $@ kernel.o

clean :
	rm -f $(BOOT_NAME) $(KERN_NAME) *.o *~ $(DISK_NAME) kernel.asm

# Boot sector at offset 0, kernel from sector 1 - which is the
# LBA that load_kernel asks the drive for. conv=notrunc stops dd
# truncating the image down to the size of what it writes.
#
# The result is ~2.1 MB rather than the 1440 KB a floppy would
# be, because kernel.bin is 2 MB: kernelEnd.S's page-table
# storage is in .text and gets emitted into the file.
make_disk :
	dd if=/dev/zero of=$(DISK_NAME) bs=1024 count=1440
	dd if=$(BOOT_NAME) of=$(DISK_NAME) conv=notrunc
	dd if=$(KERN_NAME) of=$(DISK_NAME) conv=notrunc seek=1
```

- [ ] **Step 4: Write `docs/notes/08-build-system.md`**

Must state:
- Why two linker scripts: two binaries at two addresses with two different jobs.
- VMA vs LMA as a general concept, and this specific instance: LMA `0x00100000`, VMA `0x80100000`, difference `KERNEL_BASE`.
- The single-translation-unit consequence, spelled out: macros and `.set` constants propagate forward, no `.global` is needed, file order in the prerequisite list is semantically significant, and `kernelEnd.S` must be last.
- `--oformat binary`: what it strips, and why that makes the missing `--32` harmless on an x86_64 host.
- How to get symbols back for inspection, since the shipped binary has no symbol table:
  ```sh
  ld -T link_kernel.ld -o kernel.elf kernel.o && nm -n kernel.elf
  ```
- `KERNEL_PHYS_END` coming from the location counter rather than the `end` symbol, and how that produces the one-byte skew.
- Why the image is 2.1 MB: storage sits in `.text` and is emitted.
- The verification loop available in this container — build, `hexdump -C my_boot.img`, read `kernel.asm` — and that `qemu` is not installed.
- Close with the **In the code** table:

| Location | What |
|---|---|
| `link.ld:5` | `. = 0x7c00` |
| `link_kernel.ld:3-5` | `VMA = LMA + VIRTUAL_KERNEL_BASE` |
| `link_kernel.ld:15` | `KERNEL_PHYS_END` from the location counter |
| `Makefile:17` | The prerequisite order that defines the translation unit |
| `Makefile:18` | `as -al` and the `kernel.asm` listing |
| `Makefile:26` | `seek=1`, matching `load_kernel`'s LBA |

- [ ] **Step 5: Verify the build is byte-identical**

This is the task most likely to break the build, since it edits the build files themselves. If `make` errors, the cause is almost certainly a `#` on an indented Makefile recipe line or a `//` in a linker script.

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
```

- [ ] **Step 6: Verify `make make_disk` still works**

Run:
```sh
make make_disk >/dev/null 2>&1 && wc -c my_boot.img && hexdump -C my_boot.img | head -1
```
Expected: `2109952 my_boot.img`, and a first line of hexdump showing the boot sector, not zeros.

- [ ] **Step 7: Clean up and commit**

```bash
make clean >/dev/null
git add link.ld link_kernel.ld Makefile docs/notes/08-build-system.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Explain the two-linker build and the single translation unit" -m "Nothing in the build files says that file order in the kernel.bin
prerequisite list is load-bearing, or that --oformat binary is what
lets a plain x86_64 `as` produce 32-bit output. Both are the kind of
thing that only surfaces when adding a file breaks the image."
```

---

### Task 9: Overview chapter and TODO entries

**Files:**
- Create: `docs/notes/00-overview.md`
- Modify: `TODO.md`

**Interfaces:**
- Consumes: all eight chapters from Tasks 1–8; every `BUG:` annotation placed so far.
- Produces: the finished documentation set.

Written last because it summarises everything before it.

- [ ] **Step 1: Write `docs/notes/00-overview.md`**

Must contain:
- One paragraph on what this project is: an educational OS kernel, currently booting into protected mode with paging on and a physical page allocator, stopped at process page tables.
- **How to read these notes:** chapters run in boot order, 01 through 08. Point at chapter 08 for anyone who just wants to build it.
- **The boot path**, as a numbered list matching `CLAUDE.md`:
  1. BIOS loads sector 0 to `0x7c00`, real mode.
  2. `boot.S`: zero segments, A20, `lgdt`, `CR0.PE`, `ljmp` to 32-bit, stack at `0x7c00`.
  3. `load_kernel`: ATA PIO, one sector from LBA 1 to physical `0x100000`, then `jmp` there.
  4. `kernel.S:main` → `boot_paging` → tables, `CR3`, `CR0.PG`, indirect jump to `relocated`.
  5. `create_phys_mem_list`, then `mprint`, then `hlt`.
- **The memory map table:**

| Region | Address | What |
|---|---|---|
| Boot sector | `0x7c00` | 512 bytes, loaded by BIOS |
| Boot stack | below `0x7c00` | Grows down |
| Kernel load address | `0x00100000` | LMA |
| Kernel run address | `0x80100000` | VMA = LMA + `KERNEL_BASE` |
| Kernel code end | `0x80100174` | 372 bytes |
| Free page stack | `0x80101000`–`0x80102000` | 1024 entries |
| `boot_pgdir` | `0x80102000` | 4 KB |
| `boot_pgtabels` | `0x80103000` | 2 MB, 512 tables, 2 GB mapped |
| Image end | `0x80303000` | `KERNEL_PHYS_END` = `0x303001` |
| VGA text buffer | `0xb8000`–`0xb8fa0` | 80 × 25 × 2 bytes |

- **Build and verify**, copied from `CLAUDE.md`: `make`, `make make_disk`, `make clean`, `./mk.sh`. State that `qemu` is not in the container and the image is booted outside it.
- **What is unfinished:** `allocate_process` returns nothing and uses placeholder flags; `create_process_pages` is comments only; there is no IDT, no fault handler, no user mode, and no memory map query.
- **Known bugs:** a table of all seven, each with its `file:line` and a one-line summary, pointing at `TODO.md` as the tracker.
- A chapter index linking 01 through 08.

- [ ] **Step 2: Append the four new bugs to `TODO.md`**

Match the existing entry style exactly — bold summary, parenthesised `file:line`, then the mechanism.

```markdown
- [ ] **`seta20_2` re-sends the command byte instead of re-polling**
  (boot.S:25). The busy-wait after the `0xd1` command write branches back
  to `seta20_1`, so a controller that is still busy repeats the command
  write rather than just re-reading status. Should be `jnz seta20_2`.
  Harmless in practice — the 8042 is idle by that point.

- [ ] **`clr_scr` clears twice the screen** (clear_screen.S:10). `$0xf9e`
  is the buffer size in bytes, but `rep stosw` writes a word per
  iteration, so it zeroes 7996 bytes over a 4000-byte screen and runs out
  to 0xb9f3c. Invisible only because that is still VGA memory. The count
  should be `$0x7d0` — 2000 cells of 80 × 25.

- [ ] **`allocate_process` dereferences a clobbered `%ecx`**
  (allocator.S:75-78). `movl %eax, %ecx` saves a page, then
  `call allocate_page` overwrites `%ecx` with the stack index before
  `movl %eax, (%ecx)` writes through it. The saved value has to survive
  the call, on the stack or in a callee-saved register.

- [ ] **`zero_page` has no destination** (allocator.S:94-99). Neither
  `%edi` nor the direction flag is set, so it zeroes 4 KB from wherever
  `%edi` happened to point, in whichever direction DF happened to select.
  The count is correct: `0x400` dwords is exactly one page.
```

- [ ] **Step 3: Verify every cross-reference resolves**

Check that every `docs/notes/NN-*.md` named in an inline comment exists:
```sh
grep -rhoE 'docs/notes/[0-9]{2}-[a-z0-9-]+\.md' *.S *.ld Makefile | sort -u | while read f; do
  test -f "$f" && echo "OK   $f" || echo "MISSING $f"
done
```
Expected: eight `OK` lines, no `MISSING`.

Then confirm all nine chapters exist:
```sh
ls docs/notes/
```
Expected: `00-overview.md` through `08-build-system.md`.

- [ ] **Step 4: Verify the build is byte-identical one final time**

Run:
```sh
make clean >/dev/null && make >/dev/null 2>&1 && md5sum my_boot.bin kernel.bin && wc -c my_boot.bin
```
Expected, exactly:
```
79ca39bcd2c8254baff292f0fb7c7b1a  my_boot.bin
c28428650b543a9046c9fcacc73feeb7  kernel.bin
512 my_boot.bin
```

Then confirm the boot signature survived:
```sh
hexdump -C my_boot.bin | tail -2
```
Expected: `55 aa` in the final two bytes, at offset `0x1fe`.

- [ ] **Step 5: Clean up and commit**

```bash
make clean >/dev/null
git add docs/notes/00-overview.md TODO.md
git -c user.name=wisp -c user.email=forworkandtravel@yandex.ru commit -m "Add the overview chapter and four newly found bugs" -m "The per-subsystem chapters assume you already know roughly where you
are; the overview is the entry point that gives the memory map and the
boot order first. The four bugs found while reading the code go into
TODO.md so it stays the single list of what is known broken."
```

---

## Post-Implementation Check

Not a task — a final read-through before calling the work done.

- [ ] Every one of the 30 sections in the File Structure table has a block comment.
- [ ] All seven `BUG:` annotations are present: `boot.S:25`, `boot.S:80`, `allocator.S:27`, `allocator.S:75`, `allocator.S:94`, `clear_screen.S:10`, `kernelEnd.S:13`.
- [ ] No instruction, directive, label, or constant was changed. `git diff c8e95cc..HEAD -- '*.S'` should show only comment lines added or altered.
- [ ] `TODO.md` lists all seven bugs.
- [ ] Both hashes still match the baseline.
