# 06 - The Physical Page Allocator

## Why an allocator, and why LIFO

Once paging is live, the kernel needs a way to hand out physical
pages one at a time - a page directory here, a page table there,
eventually process memory. `allocator.S` does this with a LIFO stack
of free physical page addresses: freeing is a push, allocating is a
pop. Both operations are O(1) and the implementation is about as
simple as an allocator gets - a handful of instructions each.

The cost of that simplicity is contiguity. A stack can only ever hand
back one page at a time, in whatever order they happen to sit in it,
so nothing can ask this allocator for a run of physically contiguous
pages. Anything driving DMA eventually needs that and will need a
different allocator (or an additional layer on top of this one) to
get it.

## The three storage objects

All of the allocator's state lives in `kernelEnd.S`, not in
`allocator.S` itself:

- `aviable_phys_mem_stack_index` - a single 4-byte index, at
  `0x80100174`.
- `aviable_phys_mem_stack_bottom` - the stack storage itself, running
  from `0x80101000` to `0x80102000`: 1024 entries of 4 bytes each.
- `aviable_phys_mem_stack_top` - the label marking where the storage
  ends, at `0x80102000`.

`PHYS_PAGES_COUNT` is `0x400` (1024) pages, i.e. 4 MB of manageable
physical memory. That number is not discovered - it's a hardcoded
guess. Nothing in this codebase has queried the BIOS (`INT 15h,
AX=E820h`) for a real memory map, so the allocator only knows about
memory it's been told to assume exists.

## The push/pop asymmetry

`create_phys_mem_list` fills the stack and sets the index to
`PHYS_PAGES_COUNT - 1` - the index always points at the topmost
*occupied* slot, not one past it. That convention shapes both
operations:

- `allocate_page` (pop) reads the slot at `[index]`, *then*
  decrements the index.
- `free_page` (push) increments the index *first*, then writes the
  new page at `[index]`.

The two are mirror images of each other and internally consistent.
What neither one has is a bounds check: `allocate_page` only checks
for an empty stack (and, per the bug below, checks it wrong), and
`free_page` doesn't check for a full one at all.

## The four bugs

This subsystem carries four of the seven bugs documented in
`TODO.md`:

1. **The `test` operand.** `allocate_page` checks for an empty stack
   with `test %ecx, 0x0`. In AT&T syntax a bare `0x0` is a memory
   operand, not an immediate, so this ANDs `%ecx` with the dword at
   absolute address 0 instead of testing anything about the index.
   Which branch is taken ends up decided by whatever physical page 0
   holds. But `test %ecx, %ecx` is not the fix either: paired with the
   `jnz` that follows, it sets ZF - and takes the empty-stack branch -
   exactly when the index is 0, and slot 0 holds a real, allocatable
   page. The index only goes negative once slot 0 has been handed out,
   so the check that actually distinguishes "empty" from "slot 0" has
   to test the sign, not equality with zero.
2. **The `KERNEL_PHYS_END` skew.** `kernelEnd.S`'s `end` label emits
   a `.byte` after its `.align`, but that `.byte` only moves the
   location counter - the symbol `end` itself is still page-aligned,
   at `0x80303000`. `link_kernel.ld` takes `KERNEL_PHYS_END` from the
   location counter, not from `end`, so `KERNEL_PHYS_END` is the one
   that lands one byte past the page boundary (`0x303001`, not
   `0x303000`). Every address `create_phys_mem_list` pushes inherits
   that one-byte skew.
3. **The `%ecx` clobber.** In `allocate_process`, a page address is
   saved into `%ecx` and then `allocate_page` is called again before
   it's used - but `allocate_page` itself loads the stack index into
   `%ecx`, destroying the saved value.
4. **`zero_page`'s unset `%edi`.** `zero_page` runs `rep stosl`
   without ever loading `%edi` or issuing a `cld` first. It zeroes 4
   KB starting wherever `%edi` happened to already point, in whatever
   direction the flag happened to already select.

## The overflow that reaches the page directory

`free_page` has no bounds check, and the address it would overflow
into is not some harmless pad - it's `boot_pgdir`. `nm` on the linked
kernel shows why:

```
0000000080102000 t aviable_phys_mem_stack_top
0000000080102000 t boot_pgdir
```

`aviable_phys_mem_stack_top` and `boot_pgdir` resolve to the exact
same address, `0x80102000`, because the free-page stack's storage
ends precisely where the page directory begins. Free enough pages
without ever having allocated them, and `free_page` walks the index
past the top of the stack and starts overwriting live page directory
entries.

## Where the work stopped

Past `free_page`, the file is unfinished. `allocate_process` allocates
a page directory and a couple of page-table pages, but every flags
field is a placeholder `addl $0x0, %eax` where a `P|RW|US` mask
belongs, and the routine never returns anything to its caller.
`create_process_pages` is comments only - a design sketch of the
intended layout of a process address space (kernel mappings, user
page directory and tables, exception stack, user stack/heap/code) with
no implementation behind any of it. This is where the allocator's
author left off.

## In the code

| Location | What |
|---|---|
| `allocator.S` — `// PHYSICAL PAGE ALLOCATOR` block | Why LIFO |
| `allocator.S` — `create_phys_mem_list` | Stack fill — `BUG`, unaligned base |
| `allocator.S` — `allocate_page` | The pop |
| `allocator.S` — `test	%ecx, 0x0` | `BUG` — memory operand, not a register |
| `allocator.S` — `free_page` | The push — `NOTE`, no bounds check |
| `allocator.S` — `allocate_process` | Unfinished, placeholder flags |
| `allocator.S` — `movl	%eax, %ecx` | `BUG` — clobbered by the next call |
| `allocator.S` — `zero_page` | `BUG` — `%edi` never set |
| `allocator.S` — `create_process_pages` | Design sketch only |
| `kernelEnd.S` — `aviable_phys_mem_stack_bottom` | The stack storage |
| `kernelEnd.S` — `aviable_phys_mem_stack_top` | Where it collides with `boot_pgdir` |
| `kernelEnd.S` — `end:` | `BUG` — `.byte` after `.align` |
