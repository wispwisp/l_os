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
	# just re-polling status. It should be seta20_2. The outb
	# just above has genuinely just filled the input buffer, so
	# IBF can really be set here - that is exactly why this
	# second poll exists. It converges anyway: re-issuing 0xd1 is
	# idempotent, so the loop just keeps looping until the buffer
	# drains and exits normally. Harmless, but a genuine
	# copy-paste slip.
	jnz	seta20_1
	# 0xdf -> port 0x60 :
	movb	$0xdf, %al
	outb	%al, $0x60
	
	####################
	# ENTER PROTECTED MODE
	####################
	# Three steps. What is forced is that both of the first two
	# precede the third:
	#   1. lgdt - the table has to be valid before anything can
	#      consult it. Intel documents lgdt-first as the
	#      recommended sequence; steps 1 and 2 could in
	#      principle swap, since nothing reads the GDT between
	#      them.
	#   2. Set CR0 bit 0 (PE). The CPU is in protected mode from
	#      here, but CS still holds a real-mode segment value.
	#   3. A FAR jump. Only a far jump or far call reloads CS,
	#      and until CS holds a real selector the CPU still
	#      decodes with 16-bit defaults. This is why the switch
	#      cannot end with a near jump.
	# See docs/notes/03-protected-mode.md.

	lgdt    gdtdesc
	movl	%cr0, %eax
	orl	$0x1, %eax # protected mode enable flag
	movl    %eax, %cr0

	# jump into 32-bit code (selector, address)
	ljmp	$0x8, $protcseg
	
	.code32
protcseg:
	# The far jump reloaded CS. The other five segment registers
	# still hold real-mode values and must be pointed at the
	# flat data descriptor before any access uses them. 0x10 is
	# the third GDT entry: 2 * 8 bytes.
	movw	$0x10, %ax # data segment selector
	movw    %ax, %ds
	movw    %ax, %es
	movw    %ax, %fs
	movw    %ax, %gs
	movw    %ax, %ss

	# The stack goes at 0x7c00 and grows downward, into the
	# roughly 30 KB of free memory below this code. The
	# interrupt vector table (0x0-0x3ff) and the BIOS data area
	# (0x400-0x4ff) do occupy the very bottom, but a boot
	# sector's stack never grows deep enough to reach them.
	# EBP is zeroed to terminate any frame-pointer walk.
	#
	# NOTE: the 'c' in this label is Cyrillic U+0441, not Latin
	# 'c'. GAS accepts it because the label is never referenced,
	# so no other spelling ever has to match. Left alone here -
	# renaming it would be a code change, not a comment change.
staсk_initialization:
	movl	$0x0, %ebp
	movl	$start, %esp
kernel_entry:	
	call	load_kernel
	# Absolute jump to 0x100000, where load_kernel put the image
	# and where link_kernel.ld placed main.
	jmp	KERNEL_PLACE

	# Not reached. If that jump ever returns, stop rather than
	# execute whatever bytes follow.
	hlt
spin:	jmp	spin


	####################
	####################

	####################
	# ATA PIO: WAIT FOR THE DRIVE
	####################
	# The disk is not memory-mapped. It is driven through eight
	# I/O ports, 0x1f0-0x1f7, and seven of them are only valid
	# to touch when the drive says it is not busy.
	#
	# Status register (0x1f7):
	#   bit 7  BSY   busy; every other register is invalid
	#   bit 6  DRDY  ready to accept a command
	#   bit 3  DRQ   a sector is ready to transfer
	#   bit 0  ERR   the last command failed
	#
	# Masking to bits 7:6 and comparing against 0x40 means "BSY
	# clear and DRDY set". Note what it does not check: DRQ, so
	# this waits for the drive to be idle rather than for data
	# to be available; and ERR, so a failed read cannot be
	# distinguished from a good one.
	#
	# NOTE: no timeout. A drive that never clears BSY hangs the
	# boot here forever. Real drivers bound the wait.
	# See docs/notes/04-ata-pio.md.

wait_disk:
	movw	$0x1f7, %dx
testwd:	inb	(%dx), %al
	# inb loaded only AL, so AH is stale - harmless, because the
	# comparison below is 8-bit.
	andw	$0xffc0, %ax
	cmpb	$0x40, %al
	jne	testwd
	ret
	
	####################
	# ATA PIO: READ THE KERNEL
	####################
	# Programmed I/O: write the sector address into the port
	# registers, issue the read command, then pull the data out
	# of the data port a word at a time with the CPU. No DMA and
	# no interrupts - which is what you want in a boot sector,
	# where there is no driver stack and no IDT.
	#
	# Port map:
	#   0x1f2  sector count
	#   0x1f3  LBA[7:0]
	#   0x1f4  LBA[15:8]
	#   0x1f5  LBA[23:16]
	#   0x1f6  drive select + LBA[27:24]
	#   0x1f7  command (write) / status (read)
	#
	# Ports 0x1f3-0x1f5 are still named after the CHS geometry
	# fields they used to hold. In LBA mode - selected by bit 6
	# of 0x1f6 - they are simply the low 24 bits of a linear
	# sector number.
	# See docs/notes/04-ata-pio.md.

load_kernel:
	call wait_disk

	# BUG (TODO.md): one sector, 512 bytes, of a kernel image
	# that is 2 MB. It works today only because the kernel's
	# code ends at 0x80100174 (372 bytes) and everything past
	# that is storage the kernel writes rather than reads back
	# from disk. The next routine added can silently run off the
	# end of what was loaded. Raising this count and the insw
	# counter below has to happen together.
	movw	$0x1f2, %dx
	movb	$0x1, %al # sector count = 1
	outb	%al, (%dx)

	# LBA 1: the sector straight after this boot sector, which
	# is where the Makefile's `dd ... seek=1` wrote the kernel.
	movb	$0x1, %al
	# DX is 0x01f2, so DH is 0x01 and DL is 0xf2. Only DL has to
	# change to walk to the next port.
	movb	$0xf3, %dl
	outb	%al, (%dx)
	movb	$0x0, %al # LBA[15:8]
	movb	$0xf4, %dl
	outb	%al, (%dx)
	movb	$0x0, %al # LBA[23:16]
	movb	$0xf5, %dl
	outb	%al, (%dx)
	# 0xe0 = 1110 0000. Bits 7 and 5 are hardwired to 1, bit 6
	# selects LBA addressing, bit 4 picks drive 0 (master), and
	# the low nibble carries LBA[27:24].
	movb	$0xe0, %al
	movb	$0xf6, %dl
	outb	%al, (%dx)

	# 0x20 = READ SECTORS, with retry
	movb	$0x20, %al
	movb	$0xf7, %dl
	outb	%al, (%dx)

	call wait_disk

	# 0x100 words = 512 bytes = the one sector requested above.
	# insw reads a word from the port in DX into [EDI] and
	# advances EDI, because DF is clear.
	movl	$KERNEL_PLACE, %edi
	movl	$0x100, %ecx
	movw	$0x1f0, %dx
	cld
	# NOTE: repnz on a non-comparison string instruction behaves
	# exactly as rep - INS ignores the flag-testing half of the
	# F2 prefix. rep is the idiomatic spelling.
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
	# defined "invalid" value. Loading it into CS or SS faults
	# immediately; loading it into DS, ES, FS or GS is allowed,
	# and the fault arrives when that segment is used.
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
	# .org pads with zeros out to byte 510, so the signature
	# lands at exactly 0x1fe no matter how much code precedes
	# it. If the code ever exceeds 510 bytes, `as` errors here
	# instead of silently truncating - which makes this
	# directive the 512-byte budget check.
	.org	0x0200-2
	# The BIOS treats a device as bootable only if these two
	# bytes are present.
	.byte	0x55
	.byte	0xAA
