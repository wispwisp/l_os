ENTRY(main)

VIRTUAL_KERNEL_BASE = 0x80000000;
LMA = 0x00100000;
VMA = LMA + VIRTUAL_KERNEL_BASE;
/*VMA = 0x80100000;*/
SECTIONS
{
. = VMA;
.text      ALIGN (0x1000) :   {  *(.text)          }
.rodata    ALIGN (0x1000) :   {  *(.rodata*)       }
.data      ALIGN (0x1000) :   {  *(.data)          }
.bss :                        {  *(COMMON) *(.bss) }
/DISCARD/ :                   {  *(.comment)       }
KERNEL_PHYS_END = . - VIRTUAL_KERNEL_BASE;
}	      
