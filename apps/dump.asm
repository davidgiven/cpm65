\ CP/M-65 Copyright © 2023 David Given
\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

\ This will assemble using the built-in ASM.COM. To assemble it, run this:
\
\ ASM DUMP.ASM NEWDUMP.COM

.include "cpm65.inc"

.zp address, 3
.zp index, 1

.label cannot_open
.label dump_line
.label newline
.label print_hex_number
.label space
.label syntax_error

.expand 1
.label printchar

.zproc start
	\ Did we get a parameter?

	lda cpm_fcb + 1
	cmp #' '
	beq syntax_error

	\ Try and open the file.

	lda #0
	sta cpm_fcb+0x20 \ must clear CR before opening. Why?

	lda #<cpm_fcb
	ldx #>cpm_fcb
	ldy #BDOS_OPEN_FILE
	jsr BDOS
	bcs cannot_open

	\ Read each record and dump it.

	lda #0
	sta address+0
	sta address+1
	sta address+2

	lda #<cpm_default_dma
	ldx #>cpm_default_dma
	ldy #BDOS_SET_DMA
	jsr BDOS

	.zloop
		lda #<cpm_fcb
		ldx #>cpm_fcb
		ldy #BDOS_READ_SEQUENTIAL
		jsr BDOS
		.zbreak cs

		.zrepeat
			jsr dump_line
			lda address+0
			and #0x7f
		.zuntil eq
	.zendloop
	rts
.zendproc
	
.zproc syntax_error
	lda #<msg
	ldx #>msg
	ldy #BDOS_PRINTSTRING
	jmp BDOS
msg:
	.byte "Syntax error", 13, 10, 0
.zendproc

.zproc cannot_open
	lda #<msg
	ldx #>msg
	ldy #BDOS_PRINTSTRING
	jmp BDOS
msg:
	.byte "Cannot open file", 13, 10, 0
.zendproc

.zproc dump_line
	\ Print the address.

	lda address+2
	jsr print_hex_number
	lda address+1
	jsr print_hex_number
	lda address+0
	jsr print_hex_number
	jsr space

	\ Print hex.

	lda #0
	sta index
	.zrepeat
		lda address+0
		and #0x7f
		ora index
		tax

		lda cpm_default_dma, x
		jsr print_hex_number
		jsr space

		inc index
		lda index
		cmp #8
	.zuntil eq

	\ Print ASCII.

	lda #0
	sta index
	.zrepeat
		lda address+0
		and #0x7f
		ora index
		tax

		lda cpm_default_dma, x
		cmp #32
		.zif cc
			lda #'.'
		.zendif
		cmp #127
		.zif cs
			lda #'.'
		.zendif
        jsr printchar

		inc index
		lda index
		cmp #8
	.zuntil eq

	\ Advance address.

	lda address+0
	clc
	adc #8
	sta address+0
	.zif eq
		inc address+1
		.zif eq
			inc address+2
		.zendif
	.zendif

	jmp newline
.zendproc

\ Prints an 8-bit hex number in A.
.zproc print_hex_number
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr print
	pla
print:
	and #0x0f
	ora #48
	cmp #58
    .zif cs
        adc #6
    .zendif
	pha
	jsr printchar
	pla
	rts
.zendproc

.zproc space
	lda #' '
.zendproc
    \ fall through
.zproc printchar
    ldy #BDOS_CONOUT
    jmp BDOS
.zendproc

.zproc newline
	lda #13
	jsr printchar
	lda #10
	jmp printchar
.zendproc

\ vim: filetype=asm sw=4 ts=4 et


