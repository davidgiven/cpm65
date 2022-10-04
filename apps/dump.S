; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65_llvm.inc"
#include "zif_llvm.inc"

	.text

ZEROPAGE

address: .fill 3
index:   .fill 1

zproc main
	; Did we get a parameter?

	lda cpm_fcb + FCB_F1
	cmp #' '
	beq syntax_error

	; Try and open the file.

	lda #<cpm_fcb
	ldx #>cpm_fcb
	jsr xfcb_open
	bcs cannot_open

	; Read each record and dump it.

	lda #0
	sta address+0
	sta address+1
	sta address+2

	zloop
		lda #<cpm_default_dma
		ldx #>cpm_default_dma
		jsr bdos_SETDMA

		lda #<cpm_fcb
		ldx #>cpm_fcb
		jsr xfcb_readsequential
		zbreakif_cs

		zrepeat
			jsr dump_line
			lda address+0
			and #$7f
		zuntil_eq
	zendloop
	rts
zendproc

zproc syntax_error
	lda #<1f
	ldx #>1f
	jmp bdos_WRITESTRING

1:
	.ascii "Syntax error"
	.byte 13, 10, 0
zendproc

zproc cannot_open
	lda #<1f
	ldx #>1f
	jmp bdos_WRITESTRING

1:
	.ascii "Cannot open file"
	.byte 13, 10, 0
zendproc

zproc dump_line
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

		lda cpm_default_dma, x
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

		lda cpm_default_dma, x
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
zendproc

; Prints an 8-bit hex number in A.
zproc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr 1f
    pla
1:
    and #0x0f
    ora #'0'
    cmp #'9'+1
	zif_cs
		adc #6
	zendif
   	pha
	jsr bdos_CONOUT
	pla
	rts
zendproc

zproc space
	lda #' '
	jmp bdos_CONOUT
zendproc

zproc newline
	lda #13
	jsr bdos_CONOUT
	lda #10
	jmp bdos_CONOUT
zendproc

