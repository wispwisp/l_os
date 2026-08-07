# 03 - The Protected-Mode Switch

## What protected mode buys

Real mode gives 16-bit addressing capped at 1 MB and no memory
protection at all - any code can touch any address. Protected mode is
the 80286/80386-era upgrade: 32-bit addressing (so the CPU can reach
the full 4 GB space instead of wrapping at 1 MB), privilege rings that
let a kernel wall itself off from user code, and the descriptor
machinery that paging - switched on in chapter 05 - builds on top of.
`boot.S` only needs the addressing width and the mode bit here; rings
and paging come later.

## The three-step sequence, and what order is actually forced

Entering protected mode is three instructions:

1. **`lgdt`** loads the GDT descriptor into `GDTR`. Once selectors
   start meaning something - which happens at step 3 - the table has
   to already be valid, or anything that reads it reads garbage.
2. **Set `CR0.PE`** (bit 0). This is the actual mode switch: the moment
   this bit is set, the CPU is in protected mode. But `CS` still holds
   whatever real-mode segment value it had before - the switch doesn't
   reload any segment register on its own.
3. **A far jump** reloads `CS` with a real protected-mode selector.

What is actually forced is that steps 1 and 2 both precede step 3:
skipping step 1 means step 3's far jump loads a selector that indexes
into an invalid table, and skipping step 2 means there's no protected
mode to jump into. Steps 1 and 2, though, could swap - nothing reads
the GDT between them, so setting `CR0.PE` before `lgdt` would work just
as well. `boot.S` does `lgdt` first because that is the sequence Intel
documents as recommended practice, not because the CPU requires it.
Steps 2 and 3 cannot swap: until `CR0.PE` is set, a far jump is still
interpreted the real-mode way.

## Why it has to be a *far* jump

`CS` is not an ordinary register - loading it is special-cased by the
CPU because, in protected mode, the value in `CS` is a selector that
indexes a descriptor carrying the D bit: the flag that decides whether
the CPU decodes subsequent instructions with 16-bit or 32-bit
defaults. Only a far jump (or far call, or `iret`) reloads `CS`; a
near jump changes `EIP` but leaves `CS` - and therefore the D bit the
CPU is decoding under - untouched. If the switch used a near jump
here, the CPU would carry on decoding the following 32-bit code with
16-bit instruction defaults, misreading opcode lengths from the very
next instruction. That failure mode doesn't announce itself as "wrong
mode" - it looks like random garbage execution, which is what makes
substituting a near jump so easy to get wrong and so hard to diagnose.

The far jump does double duty: besides reloading `CS`, it also flushes
whatever the CPU had prefetched under the old mode. Instructions
fetched before the jump were fetched (and possibly partially decoded)
under 16-bit rules; a control transfer discards that prefetch queue,
so nothing decoded under the stale mode ever executes.

## The other five segment registers

The far jump only reloads `CS`. `DS`, `ES`, `FS`, `GS`, and `SS` still
hold their real-mode values after it, and a real-mode segment value is
not a valid protected-mode selector - using one would either fault or
address the wrong memory. Each of the other five has to be explicitly
loaded with a selector into the flat data descriptor before anything
touches memory through it. `boot.S` uses selector `0x10`, the GDT's
third entry (`2 * 8` bytes in), which is the data descriptor set up in
chapter 02.

## The stack

The stack is placed at `0x7c00` - the same address the boot sector was
loaded to and is currently executing from - and it grows downward from
there. That downward range isn't entirely empty: the interrupt vector
table occupies `0x0`-`0x3ff` and the BIOS data area occupies
`0x400`-`0x4ff`. But between `0x500` and `0x7c00` there is roughly
30 KB of genuinely free space, and a boot sector's stack never grows
deep enough to descend all the way down to those structures, so it
simply claims free space as it grows and can't collide with the boot
code sitting just above it.

## The `0x55AA` signature and the `.org` trick

The BIOS only treats a disk as bootable if the last two bytes of the
first 512-byte sector are `0x55`, `0xAA`. `boot.S` reaches that offset
with `.org 0x0200-2`, which pads the assembled output with zeros up to
byte 510 no matter how much code precedes it. That directive doubles
as a build-time size assertion: if the code before it already exceeds
510 bytes, `.org` can't pad backward, so `as` errors out right there
instead of silently producing a signature at the wrong offset or a
truncated boot sector.

## In the code

| Location | What |
|---|---|
| `boot.S` — `# ENTER PROTECTED MODE` block | Why the order is forced |
| `boot.S` — `lgdt    gdtdesc` | Loading the descriptor table |
| `boot.S` — `orl	$0x1, %eax` | Setting `CR0.PE` |
| `boot.S` — `ljmp	$0x8, $protcseg` | The far jump that reloads `CS` |
| `boot.S` — `protcseg:` | Data selector reload |
| `boot.S` — the stack setup above `kernel_entry:` | Stack at `0x7c00`, growing down |
| `boot.S` — `boot_signature:` | `.org` and `0x55AA` |
