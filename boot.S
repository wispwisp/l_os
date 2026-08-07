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
	
	####################
	# protectd mode:
	lgdt    gdtdesc
	movl	%cr0, %eax
	orl	$0x1, %eax # pr.mode enable flag
	movl    %eax, %cr0

	# jump im 32-bit (selecotr, addr)
	ljmp	$0x8, $protcseg
	
	.code32
protcseg:
	# Set up the protected-mode registers:
	movw	$0x10, %ax # data segment selector
	movw    %ax, %ds
	movw    %ax, %es
	movw    %ax, %fs
	movw    %ax, %gs
	movw    %ax, %ss

staсk_initialization: # инициализируем стек 0x7c00 (тк как растет вниз - пох)
	movl	$0x0, %ebp
	movl	$start, %esp
kernel_entry:	
	call	load_kernel
	jmp	KERNEL_PLACE

	# bad:
	hlt
spin:	jmp	spin


	####################
	####################

	#func:
wait_disk:
	movw	$0x1f7, %dx
testwd:	inb	(%dx), %al
	andw	$0xffc0, %ax
	cmpb	$0x40, %al
	jne	testwd
	ret
	
	#func:
load_kernel:
	call wait_disk

	# set sector count:
	movw	$0x1f2, %dx 
	movb	$0x1, %al # sector count - 1
	outb	%al, (%dx)

	# set offset:
	# 0x1f3: (SECTOR COUNT PORT)  (sector number, the actual sector wanted)
	movb	$0x1, %al # read sector one (read sector two)
	movb	$0xf3, %dl # put in lower part because dx=0x1f2 --> dh=0x1 dl=f2,f3,etc
	outb	%al, (%dx)
	# 0x1f4: (cylinder low port, cylinders is 0-1024)
	movb	$0x0, %al # Cylinder 0
	movb	$0xf4, %dl
	outb	%al, (%dx)
	# 0xf5: (cylinder high port, this makes up the rest of the 1024)
	movb	$0x0, %al # The rest of the cylinder 0
	movb	$0xf5, %dl
	outb	%al, (%dx)
	# 0xf6: (drive/head) Drive and head port
	movb	$0xe0, %al # Drive 0, head 0
	movb	$0xf6, %dl
	outb	%al, (%dx)

	# command - read sectors:
	# 0x1f7 - Command port
	movb	$0x20, %al # command - read sectors with retry
	movb	$0xf7, %dl
	outb	%al, (%dx)

	call wait_disk
	
	# reads a sector :
	movl	$KERNEL_PLACE, %edi # kernel place
	movl	$0x100, %ecx # (One sector-512) / 2  // try 80
	movw	$0x1f0, %dx # port
	cld
	# insl: data from port wich in edx, to edi
	# rep : until register ecx not zero
	repnz insw (%dx), (%edi)
	
	ret

	####################
	####################

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
boot_signature:	
	.org	0x0200-2
	.byte	0x55
	.byte	0xAA
