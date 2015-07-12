	.section .text
	.global start
	.set KERNEL_PLACE, 0x100000
start:
	.code16
	
	cli
	cld
	
	xorw	%ax, %ax
	movw	%ax, %ds
	movw	%ax, %es
	movw	%ax, %ss

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

	.p2align 2
gdt:
	#first zero entry in table :
	.word 0,0
	.byte 0,0,0,0
	# code seg:
	.word	0xffff, 0x0
	.byte	0x0, 0x9a, 0xcf, 0x0
	# data seg :
	.word	0xffff, 0x0
	.byte	0x0, 0x92, 0xcf, 0x0
gdtdesc:
	.word	0x17	# // gdt size limit
	.long	gdt	# // gdt addres
boot_signature:	
	.org	0x0200-2
	.byte	0x55
	.byte	0xAA
