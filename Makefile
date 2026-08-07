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
