# 04 - The ATA PIO Disk Read

## PIO versus DMA, and why a boot sector uses PIO

There are two ways to move data off an ATA disk. DMA (direct memory
access) hands the controller a memory address and lets it write there
on its own, interrupting the CPU only when the transfer finishes. PIO
(programmed I/O) has the CPU pull the data itself, one word at a time,
out of a data port. DMA is faster and doesn't burn CPU cycles on the
transfer, but setting it up needs a driver: buffers, interrupt
handling, controller-specific configuration.

None of that exists yet at this point in `boot.S`. There is no IDT, so
there is nowhere for a completion interrupt to go; there is no driver
stack, so there is nothing to configure a DMA engine with. PIO needs
none of that - it's just port writes and a polling loop, which is
exactly what a piece of code has to be when it's the only thing running
in a machine that hasn't been set up yet.

## The port map

The drive is addressed through eight consecutive I/O ports,
`0x1f0`-`0x1f7`:

| Port | Read | Write |
|---|---|---|
| `0x1f0` | data | data |
| `0x1f1` | error | features |
| `0x1f2` | sector count | sector count |
| `0x1f3` | LBA[7:0] | LBA[7:0] |
| `0x1f4` | LBA[15:8] | LBA[15:8] |
| `0x1f5` | LBA[23:16] | LBA[23:16] |
| `0x1f6` | drive/head | drive/head |
| `0x1f7` | status | command |

`load_kernel` never touches `0x1f1`. On read it holds an error code
from the last failed command; on write it configures drive features
this code doesn't use. It's in the table because it's part of the same
eight-port block, not because `boot.S` reads or writes it.

## The status register

`0x1f7`, read, is the status register. `wait_disk` only inspects two of
its eight bits:

| Bit | Name | Meaning |
|---|---|---|
| 7 | BSY | busy; every other register is invalid while this is set |
| 6 | DRDY | drive is ready to accept a command |
| 3 | DRQ | a sector is ready to transfer |
| 0 | ERR | the last command failed |

`wait_disk` masks to bits 7:6 and compares against `0x40`, i.e. "BSY
clear and DRDY set". It does not check DRQ, so what it waits for is the
drive going idle, not data actually being ready to read - and it does
not check ERR, so a failed command and a successful one look identical
to this loop. Both are corners a real driver would not cut.

## CHS names, LBA meaning

Ports `0x1f3`-`0x1f5` are still named after the CHS (cylinder-head-
sector) geometry fields ATA drives used originally: sector number,
cylinder low, cylinder high. Modern drives are addressed with LBA
(logical block addressing) instead - a flat sector index - but the
ports were never renamed. Bit 6 of `0x1f6` selects which interpretation
is in effect: clear, the drive reads `0x1f3`-`0x1f5` as CHS fields;
set, it reads the same three ports as the low 24 bits of an LBA sector
number. `boot.S` sets that bit, so despite the CHS-era port names, what
gets written is a linear sector address.

## The command sequence

In order, `load_kernel` does:

1. Write the sector count to `0x1f2`.
2. Write LBA[7:0] to `0x1f3`, LBA[15:8] to `0x1f4`, LBA[23:16] to
   `0x1f5`.
3. Write `0xe0` to `0x1f6`: bits 7 and 5 are hardwired to 1, bit 6
   selects LBA addressing, bit 4 picks drive 0 (master), and the low
   nibble carries LBA[27:24] (here, 0 - the whole address is `1`).
4. Write the command `0x20`, READ SECTORS (with retry), to `0x1f7`.
   This is the write that actually starts the drive moving; everything
   before it just stages the address and count the command will use.
5. Poll `wait_disk` again, then read the data out of `0x1f0`.

## Walking the ports through `%dl`

`load_kernel` sets `%dx` to `0x1f2` once and then, for the LBA and
drive/command writes that follow, only ever rewrites the low byte,
`%dl` - `0x1f2` is `%dh = 0x01`, `%dl = 0xf2`, and every port from
`0x1f2` to `0x1f7` shares that same `0x01` high byte. Since all eight
ports live in that one page, stepping `%dl` from `0xf2` up to `0xf7`
is enough to address each of them in turn; `%dh` is set once and never
touched again.

## `0x1f2 = 0` means 256, not zero

The sector-count register is one byte, so it can only directly express
1-255. To still be able to request the natural round number 256, the
convention is that `0` in this register means 256 sectors, not zero
sectors - there's no way to ask for a zero-sector transfer through this
port, so that value was free to be repurposed. This is what makes the
`BUG` below possible to phrase as an off-by-one: `boot.S` writes `1`,
requesting exactly one sector, but a careless "count minus one" reading
of this register - as if it worked like some other size fields do -
would have written `0` and accidentally requested 256 sectors instead
of one.

## BUG: one sector loaded

`load_kernel` requests a sector count of `1` - 512 bytes - for a kernel
image that is roughly 2 MB. It works today only because the kernel's
actual code ends at `0x80100174`, 372 bytes in, and everything past
that offset is storage the kernel writes at runtime rather than code it
needs read back from disk at boot. The moment a routine is added that
runs code placed past that boundary, it silently runs off the end of
what was actually loaded - there's no fault, just garbage instructions
from whatever happened to be in memory beyond the one sector read.
Fixing this later means raising two numbers together: the sector count
written to `0x1f2`, and the `insw` counter (`$0x100`, one iteration per
word) that pulls the matching number of words back out of the data
port. Changing one without the other reintroduces the same bug in a
different shape - either reading past what was requested, or
requesting more than gets copied out.

## NOTEs: no timeout, and `repnz` vs `rep`

`wait_disk` has no timeout. If a drive never clears BSY, this loop
spins forever and the boot hangs right there. A real driver bounds the
wait and reports failure instead of hanging indefinitely; a boot sector
this small doesn't have the room for that logic.

The data transfer uses `repnz insw (%dx), (%edi)`. `repnz` (also spelled
`repne`) is meant for string instructions that compare and set flags -
it repeats "while not equal", using the zero flag as the loop
condition. `insw` isn't a comparison instruction and never touches the
zero flag, so the "while not equal" test that distinguishes `repnz`
from plain `rep` never has anything to observe; the CPU just decrements
`ECX` and repeats until it hits zero, exactly as plain `rep` would. The
prefix executes correctly here, just under a name that doesn't describe
what's actually happening - `rep` is the idiomatic spelling for a
non-comparison string instruction like this one.

## In the code

| Location | What |
|---|---|
| `boot.S` — `wait_disk` / `testwd` | The BSY/DRDY poll |
| `boot.S` — `load_kernel` | The whole PIO sequence |
| `boot.S` — `movb	$0x1, %al # sector count = 1` | Sector count — `BUG` |
| `boot.S` — the `$0xf3` / `$0xf4` / `$0xf5` writes | LBA bytes |
| `boot.S` — `movb	$0xe0, %al` | Drive select, LBA mode |
| `boot.S` — `movb	$0x20, %al` | READ SECTORS command |
| `boot.S` — `repnz insw` | The data transfer |
