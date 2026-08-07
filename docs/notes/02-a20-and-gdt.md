# 02 - The A20 Gate and the GDT

## Why the A20 gate exists

The 8086 had 20 address lines, giving it a 1 MB address space. An
address that computed past the top of that space - `0xFFFFF + 1` -
simply wrapped around to `0x0`; the CPU had no line 20 to carry into.
Enough software came to depend on that wraparound behaving that way
that when the IBM AT shipped with a 80286 and more address lines, IBM
could not just let line 20 work. Existing programs would break the
moment an address like `0x100000` stopped aliasing `0x0`. The
compromise was a gate on address line 20 that boots *disabled*, so old
software sees the old wraparound by default, and new software can
switch it on when it wants the extra memory. Until it is opened,
physical `0x100000` aliases `0x0` - which matters here because
`0x100000` is exactly where `load_kernel` is about to place the
kernel.

## The 8042 protocol

The gate ended up wired to the 8042 keyboard controller, which had a
spare output pin and got volunteered for the job. `boot.S` talks to it
through two ports:

- port `0x64` - status (read) / command (write)
- port `0x60` - data

The sequence in `seta20_1` / `seta20_2` is:

1. Poll `0x64`; bit 1 set means the input buffer is still full, so
   wait for it to clear.
2. Write command `0xd1` ("write output port") to `0x64`.
3. Poll `0x64` again for the same reason.
4. Write `0xdf` to `0x60`. Bit 1 of that byte is A20; the write sets
   it, opening the gate.

## The other two ways to do it

The 8042 dance is not the only way to enable A20, just the most
portable one:

- **Fast A20**, port `0x92`: writing with bit 1 set opens the gate in
  a single I/O write, no polling. Not present on every chipset, and
  bit 0 of that same byte is the fast CPU reset line, so a careless
  write that sets bit 0 - blindly writing a whole byte instead of
  reading, modifying just bit 1, and writing it back - resets the CPU
  instead of just opening the gate.
- **BIOS `INT 15h`, `AX=2401`**: asks the BIOS to do it. Only works in
  real mode, before the interrupt vector table stops being trustworthy,
  and not every BIOS implements the call.

Neither is guaranteed to exist, so the slow, always-present 8042 path
is the one that works everywhere - the reason `boot.S` uses it instead
of the shorter alternatives.

## The GDT: descriptor layout

Protected mode still addresses memory through segments; there is no
way to switch segmentation off. The flat model works around that
instead of fighting it: define segments that span all 4 GB, so every
linear address equals its offset and segmentation stops mattering in
practice. Paging is what does the real work of managing memory later.

A descriptor is 8 bytes, and the base and limit fields are split
across non-contiguous positions - a compatibility scar left by the
80286, which only had 24-bit base addresses:

| Bytes | Field |
|---|---|
| 0-1 | limit[15:0] |
| 2-3 | base[15:0] |
| 4 | base[23:16] |
| 5 | access |
| 6 | flags[3:0] : limit[19:16] |
| 7 | base[31:24] |

## Decoding the code and data descriptors

`boot.S` builds a null descriptor plus one code and one data
descriptor:

- `0x9a` (code access) = present, ring 0, code segment, readable.
- `0x92` (data access) = present, ring 0, data segment, writable.
- `0xcf` is byte 6, and it packs two fields together: the high nibble
  `0xc` is the flags nibble, and the low nibble `0xf` is
  limit[19:16]. The flags nibble `0xc` is G (granularity: the limit
  counts in 4 KB units, not bytes) plus D (32-bit default operand and
  address size).

G is what turns a 20-bit limit field of `0xfffff` into an actual 4 GB
span: `0xfffff` units of 4 KB each is `0xfffff000 + 0xfff`, i.e. all
32 bits.

## Selectors

A selector is just a byte offset into the GDT, which is why the
segment registers get loaded with `0x08` and `0x10`: the null
descriptor occupies bytes 0-7, the code descriptor bytes 8-15
(selector `0x08`), and the data descriptor bytes 16-23 (selector
`0x10`). Selector = descriptor index times 8.

## BUG: `seta20_2`'s stray jump target

`seta20_2`'s poll loop reads `jnz seta20_1` instead of
`jnz seta20_2`. If the controller is still busy at that point, this
re-issues the `0xd1` command write from the top instead of just
re-polling status - a copy-paste slip from `seta20_1`'s otherwise
identical loop. The `outb` that writes `0xd1` runs immediately before
this poll, so the input buffer genuinely can still be full right
here - that is the reason this second poll exists at all, per the
protocol above. It is harmless anyway: re-issuing `0xd1` is
idempotent, so the mistargeted branch just repeats the write and
loops back into the same poll until the buffer drains and the check
passes, converging on the correct end state by a longer path. It is a
genuine bug and is left unfixed here so it can be pointed at
directly.

## In the code

| Location | What |
|---|---|
| `boot.S` — `# A20 GATE` block | The history and the 8042 protocol |
| `boot.S` — `seta20_1` | Poll `0x64`, then command `0xd1` |
| `boot.S` — `seta20_2` | Poll again, then data `0xdf` |
| `boot.S` — the `jnz	seta20_1` inside `seta20_2` | `BUG` — wrong jump target |
| `boot.S` — `# THE GDT` block | Descriptor layout and the flat model |
| `boot.S` — `gdt:` | The three descriptors |
| `boot.S` — `gdtdesc:` | The `lgdt` operand |
