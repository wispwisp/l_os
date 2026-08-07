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
