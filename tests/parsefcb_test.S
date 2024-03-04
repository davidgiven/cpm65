; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "bdos.inc"
#include "cpm65.inc"

ZEROPAGE

zproc main
	lda #<fcb_buffer
	sta user_dma+0
	lda #>fcb_buffer
	sta user_dma+1

	lda #<filenames
	sta param+0
	lda #>filenames
	sta param+1
	
	zrepeat
		jsr bdos_PARSEFCB
		jsr print_fcb

		ldy #0
		zrepeat
			inc param+0
			zif_eq
				inc param+1
			zendif

			lda (param), y
		zuntil_eq
		inc param+0
		zif_eq
			inc param+1
		zendif
		lda (param), y
	zuntil_eq
		
	rts
zendproc

filenames:
	.ascii "JUSTFITS.TXT"
	.byte 0
	.ascii "A:JUSTFITS.TXT"
	.byte 0
	.ascii "SHORT.S"
	.byte 0
	.ascii "TOOLONGTOOFIT.S"
	.byte 0
	.ascii "SHORT"
	.byte 0
	.ascii "TOOLONGTOOFIT"
	.byte 0
	.ascii ".EXT"
	.byte 0
	.ascii "lowercase"
	.byte 0
	.ascii "WILD????"
	.byte 0
	.ascii "WILD*"
	.byte 0
	.ascii "WILD*.*"
	.byte 0
	.ascii "*.*"
	.byte 0
	.ascii ".*"
	.byte 0
	.byte 0

zproc print_fcb
	lda param+0
	ldx param+1
	jsr printstring
	jsr space

	lda fcb_buffer+FCB_DR
	ldx #0
	jsr printi
	jsr space

	ldx #FCB_F1
	zrepeat
		txa
		pha

		lda fcb_buffer, x
		jsr print1
		jsr space

		pla
		inx
		cpx #FCB_T3+1
	zuntil_eq
		
	jmp nl
zendproc

zproc nl
	lda #13
	jsr cpm_conout
	lda #10
	jmp cpm_conout
zendproc

zproc space
	lda #' '
	jmp cpm_conout
zendproc

zproc printstring
	ldy #BDOS_WRITE_STRING
	jmp BDOS
zendproc

zproc print1
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
    zif_cs
        adc #6
    zendif
	pha
	jsr cpm_conout
	pla
	rts
zendproc

NOINIT

fcb_buffer: .fill FCB__SIZE

