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

.enum bdos
	exit
.endenum

.enum bios
	const
	conin
	conout
	seldsk
	settrk
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

