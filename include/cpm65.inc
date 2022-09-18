.macro CPM65_BARE_HEADER
	.import __ZEROPAGE_SIZE__
	.import __CODE_RUN__
	.import __BSS_RUN__

	.byte <__ZEROPAGE_SIZE__
	.word __BSS_RUN__ - __CODE_RUN__
.endmacro

.macro CPM65_COM_HEADER
	CPM65_BARE_HEADER
BDOS:
	jmp 0
ENTRY:

.endmacro

HDR_ZPSIZE = 0
HDR_RELOTABLE_OFFSET = 1

.enum fcb
    dr
    f1
    f2
    f3
    f4
    f5
    f6
    f7
    f8
    t1
    t2
    t3
    ex
    s1
    s2
    rc
    al
    cr = $20
    r0
    r1
    r2
.endenum

.enum bdos
	exit
.endenum

.enum bios
	const
	conin
	conout
	seldsk
	setsec
	setdma
	read
	write
	relocate
	gettpa
	settpa
	getzp
	setzp
.endenum

; vim: filetype=asm sw=4 ts=4 et

