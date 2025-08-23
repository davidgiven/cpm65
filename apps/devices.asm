\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"
.include "drivers.inc"

.expand 1

.label space
.label newline
.label printchar
.label print_hex_number

.zp ptr, 2
.zp index, 1

zproc start
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    \ Find the head of the driver chain.

    lda #0
	tax
    ldy #BIOS_FINDDRV
    jsr BIOS
	sta ptr+0
	stx ptr+1

	zloop
		lda ptr+0
		ora ptr+1
		zif eq
			rts
		zendif

		\ Print driver address.

		lda ptr+1
		jsr print_hex_number
		lda ptr+0
		jsr print_hex_number
		jsr space

		\ Print driver name.

		ldy #DRVSTRUCT_NAME
		sty index
		zloop
			ldy index
			lda (ptr), y
			zbreak eq

			jsr printchar
			inc index
		zendloop
		jsr space

		\ Print driver ID.

		lda #'('
		jsr printchar

		ldy #DRVSTRUCT_ID+1
		lda (ptr), y
		jsr print_hex_number

		ldy #DRVSTRUCT_ID+0
		lda (ptr), y
		jsr print_hex_number

		lda #')'
		jsr printchar
		jsr newline

		\ Advance to next driver.

		ldy #DRVSTRUCT_NEXT
		lda (ptr), y
		pha
		iny
		lda (ptr), y
		sta ptr+1
		pla
		sta ptr+0
	zendloop

BIOS:
    jmp 0

\ Prints an 8-bit hex number in A.
zproc print_hex_number
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
    zif cs
        adc #6
    zendif
	pha
	jsr printchar
	pla
	rts
zendproc

zproc space
	lda #' '
zendproc
    \ fall through
zproc printchar
    ldy #BDOS_CONOUT
    jmp BDOS
zendproc

zproc newline
	lda #13
	jsr printchar
	lda #10
	jmp printchar
zendproc

\ vim: sw=4 ts=4 et



