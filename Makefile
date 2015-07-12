.PHONY : all clean

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
$(KERN_NAME) : kernel.S boot_paging.S hello.S clear_screen.S allocator.S kernelEnd.S
	as -al -o kernel.o $^ > kernel.asm
	ld --oformat binary -T link_kernel.ld -o $@ kernel.o

clean :
	rm -f $(BOOT_NAME) $(KERN_NAME) *.o *~ $(DISK_NAME) kernel.asm
make_disk :
	dd if=/dev/zero of=$(DISK_NAME) bs=1024 count=1440
	dd if=$(BOOT_NAME) of=$(DISK_NAME) conv=notrunc
	dd if=$(KERN_NAME) of=$(DISK_NAME) conv=notrunc seek=1
