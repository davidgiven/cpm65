	.include "cpm65.inc"

	.code
	CPM65_COM_HEADER

    ldy #bdos::exit
    jmp BDOS


