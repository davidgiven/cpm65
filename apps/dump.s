; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

	.include "cpm65.inc"
	.include "zif.inc"
	.include "xfcb.inc"

	.import xfcb_readsequential
	.import xfcb_open

	.zeropage

address: .res 3
index:	 .res 1

	.code
	CPM65_COM_HEADER

.scope
	; Did we get a parameter?

	lda FCB+xfcb::f1
	cmp #' '
	beq syntax_error

	; Try and open the file.

	lda #<FCB
	ldx #>FCB
	jsr xfcb_open
	bcs cannot_open

	; Read each record and dump it.

	lda #0
	sta address+0
	sta address+1
	sta address+2

	zloop
		lda #<COMMANDLINE
		ldx #>COMMANDLINE
		jsr bdos_SETDMA

		lda #<FCB
		ldx #>FCB
		jsr xfcb_readsequential
		zbreakif_cs

		zrepeat
			jsr dump_line
			lda address+0
			and #$7f
		zuntil_eq
	zendloop
	rts
.endscope

.proc syntax_error
	lda #<msg
	ldx #>msg
	jmp bdos_WRITESTRING
msg:
	.byte "Syntax error", 13, 10, 0
.endproc

.proc cannot_open
	lda #<msg
	ldx #>msg
	jmp bdos_WRITESTRING
msg:
	.byte "Cannot open file", 13, 10, 0
.endproc

.proc dump_line
	; Print the address.

	lda address+2
	jsr print_hex_number
	lda address+1
	jsr print_hex_number
	lda address+0
	jsr print_hex_number
	jsr space
		
	; Print hex.

	lda #0
	sta index
	zrepeat
		lda address+0
		and #$7f
		ora index
		tax

		lda COMMANDLINE, x
		jsr print_hex_number
		jsr space

		inc index
		lda index
		cmp #8
	zuntil_eq
	
	; Print ASCII.

	lda address+0

	lda #0
	sta index
	zrepeat
		lda address+0
		and #$7f
		ora index
		tax

		lda COMMANDLINE, x
		cmp #32
		zif_cc
			lda #'.'
		zendif
		cmp #127
		zif_cs
			lda #'.'
		zendif
		jsr bdos_CONOUT

		inc index
		lda index
		cmp #8
	zuntil_eq

	; Advance address.

	lda address+0
	clc
	adc #8
	sta address+0
	zif_eq
		inc address+1
		zif_eq
			inc address+2
		zendif
	zendif

	jmp newline
.endproc

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

