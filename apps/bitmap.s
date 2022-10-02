; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

	.include "cpm65.inc"
	.include "zif.inc"
	.include "xfcb.inc"

	.import xfcb_readsequential
	.import xfcb_make

	.zeropage

bitmap: .word 0
index:	.byte 0

	.code
	CPM65_COM_HEADER

	jsr bdos_GETALLOCATIONBITMAP
	sta bitmap+0
	stx bitmap+1

	lda #0
	sta index
	zrepeat
		ldy index
		lda (bitmap), y
		
		jsr print_hex_number
		jsr space

		inc index
		lda index
		cmp #32
	zuntil_eq
	jmp newline
	
.scope

	rts
.endscope

; Prints an 8-bit hex number in A.
.proc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr h4
    pla
h4:
    and #%00001111
    ora #'0'
    cmp #'9'+1
	zif_cs
		adc #6
	zendif
   	pha
	jsr bdos_CONOUT
	pla
	rts
.endproc

space:
	lda #' '
	jmp bdos_CONOUT

newline:
	lda #13
	jsr bdos_CONOUT
	lda #10
	; fall through
bdos_CONOUT:
	ldy #bdos::console_output
	jmp BDOS

bdos_SETDMA:
	ldy #bdos::set_dma_address
	jmp BDOS

bdos_WRITESTRING:
	ldy #bdos::write_string
	jmp BDOS

bdos_GETALLOCATIONBITMAP:
	ldy #bdos::get_allocation_bitmap
	jmp BDOS
