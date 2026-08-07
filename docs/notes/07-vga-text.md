# 07 - VGA Text Output

## Memory-mapped, not a driver

`0xb8000` is the standard VGA text-mode framebuffer address. The
adapter reads that memory continuously and renders it to the screen,
so writing to it puts characters on screen directly - no driver, no
BIOS call, no I/O port involved. `mprint` and `clr_scr` are both just
`mov`-family instructions aimed at that address; from the CPU's point
of view it's indistinguishable from writing to any other RAM.

## The two-byte cell

Each character on screen occupies two consecutive bytes: the
character code, then an attribute byte. That layout is the whole
reason `print_loop` in `hello.S` calls `stosb` twice per character -
once for the byte read out of `mesg` via `lodsb`, once for the fixed
attribute `0x07` - and why `%edi` needs no extra adjustment between
the two: each `stosb` advances it by exactly one byte, so two of them
land it on the next cell by itself.

## The attribute byte

Within the attribute byte, bits 0-3 select the foreground color, bits
4-6 the background, and bit 7 is either a blink flag or a bright-
background bit depending on how the adapter is configured. `0x07` -
what `mprint` writes after every character - is light grey on black,
the standard default. `0x00` sets both foreground and background to
black, which is why it doubles as the "blank" value `clr_scr` uses to
clear cells: an invisible character on an invisible background reads
as empty.

## The screen in numbers

Default VGA text mode is 80 columns by 25 rows: 80 * 25 = 2000 cells,
and at 2 bytes per cell that's 4000 bytes total, running from
`0xb8000` to `0xb8fa0`. Every constant in `clear_screen.S` is supposed
to fall out of that arithmetic - and one of them doesn't.

## The bug: a byte count fed to a word-at-a-time store

`clr_scr` sets `%ecx` to `0xf9e` before `rep stosw`. `stosw` writes
one word (2 bytes) per iteration and decrements `%ecx` once per
iteration, so the loop writes `0xf9e` words - `0xf9e * 2 = 7996`
bytes - not `0xf9e` bytes. Against a 4000-byte screen that's 3996
bytes too many, carrying the write out to `0xb8000 + 7996 = 0xb9f3c`,
nearly double the intended range. The value that belongs there is
`0x7d0` (2000 decimal), the actual cell count: `0x7d0` words is
`0x7d0 * 2 = 4000` bytes, exactly the screen.

It goes unnoticed because the overrun still lands in VGA memory - the
adapter has more than 4000 bytes of buffer behind it even though only
the first 4000 are what's actually displayed in 80x25 mode - so the
extra writes clobber unused adapter RAM instead of crashing or
corrupting something else. Nothing visibly breaks, which is exactly
how a wrong constant like this survives.

The `0xf9e` figure itself traces back to a stale comment rather than
a fresh miscalculation: the old note in this file gave the buffer's
end address as `0xb8f9e`, two bytes short of the real end `0xb8fa0`,
and the byte-count-shaped `0xf9e` was carried over from that already-
wrong figure straight into a word count.

## NOTE: `mesg` living in `.text`

`hello.S` puts the string literal `mesg` directly in `.text`, ahead
of the code that reads it, rather than in `.rodata` - which
`link_kernel.ld` already declares as a section. That's only safe
because nothing ever jumps to `mesg`; every entry into this file goes
through `mprint`, so the bytes of the string are never fetched as
instructions. `.rodata` would be the conventional home for it, but
placement in `.text` costs nothing here as long as that invariant
holds.

## In the code

| Location | What |
|---|---|
| `hello.S` — `mesg:` | The string, sitting in `.text` |
| `hello.S` — `mprint:` | Setup, `0xb8000` as destination |
| `hello.S` — `print_loop` | The character/attribute pair loop |
| `hello.S` — `movb	$7,%al` | Attribute `0x07`, light grey on black |
| `clear_screen.S` — `clr_scr` | Destination and the blank cell value |
| `clear_screen.S` — `movl	$0xf9e,%ecx` | `BUG` — byte count used as a word count |
