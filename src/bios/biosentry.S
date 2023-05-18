; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "mos.inc"
#include "cpm65.inc"
#include "driver.inc"

.global drvtop

; BIOS entry point. Parameter is in XA, function in Y.
zproc biosentry
    pha
    lda biostable_lo, y
    sta ptr+0
    lda biostable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

biostable_lo:
    .byte entry_CONST@mos16lo
    .byte entry_CONIN@mos16lo
    .byte entry_CONOUT@mos16lo
    .byte entry_SELDSK@mos16lo
    .byte entry_SETSEC@mos16lo
    .byte entry_SETDMA@mos16lo
    .byte entry_READ@mos16lo
    .byte entry_WRITE@mos16lo
    .byte entry_RELOCATE@mos16lo
    .byte entry_GETTPA@mos16lo
    .byte entry_SETTPA@mos16lo
    .byte entry_GETZP@mos16lo
    .byte entry_SETZP@mos16lo
    .byte entry_SETBANK@mos16lo
	.byte entry_ADDDRV@mos16lo
	.byte entry_FINDDRV@mos16lo
biostable_hi:
    .byte entry_CONST@mos16hi
    .byte entry_CONIN@mos16hi
    .byte entry_CONOUT@mos16hi
    .byte entry_SELDSK@mos16hi
    .byte entry_SETSEC@mos16hi
    .byte entry_SETDMA@mos16hi
    .byte entry_READ@mos16hi
    .byte entry_WRITE@mos16hi
    .byte entry_RELOCATE@mos16hi
    .byte entry_GETTPA@mos16hi
    .byte entry_SETTPA@mos16hi
    .byte entry_GETZP@mos16hi
    .byte entry_SETZP@mos16hi
    .byte entry_SETBANK@mos16hi
	.byte entry_ADDDRV@mos16hi
	.byte entry_FINDDRV@mos16hi
zendproc

zproc entry_ADDDRV
	sta ptr+0			; save new driver address
	stx ptr+1

	ldy #DRVSTRUCT_NEXT
	lda drvtop+0		; get old driver address
	sta (ptr), y
	iny
	lda drvtop+1
	sta (ptr), y

	ldy ptr+0			; update address
	sty drvtop+0
	ldy ptr+1
	sty drvtop+1

	pha
	txa
	pha
	jsr initdrivers
	pla
	tax
	pla
	rts
zendproc

zproc entry_FINDDRV
	sta ptr1+0
	stx ptr1+1

	ora ptr1+1
	zif_eq
		; input ID is 0; return first driver structure

		lda drvtop+0
		ldx drvtop+1
		clc
		rts
	zendif

	lda drvtop+0
	sta ptr+0
	lda drvtop+1
	sta ptr+1

	zloop
		; Stop if no more drivers.

		lda ptr+0
		ora ptr+1
		zif_eq
			sec
			rts
		zendif

		; Check this driver's ID.

		ldy #DRVSTRUCT_ID
		lda (ptr), y
		cmp ptr1+0
		zif_eq
			iny
			lda (ptr), y
			cmp ptr1+1
			zif_eq
				; Found a matching driver, so return its strategy routine.

				iny
				iny
				lda (ptr), y
				tax
				dey
				lda (ptr), y
				clc
				rts
			zendif
		zendif

		; This driver doesn't match, so continue on down the list.

		ldy #DRVSTRUCT_NEXT
		lda (ptr), y
		tax
		iny
		lda (ptr), y
		sta ptr+1
		stx ptr+0
	zendloop
zendproc

; Recache driver pointers.

zproc initdrivers
	lda #<DRVID_TTY
	ldx #>DRVID_TTY
	jsr entry_FINDDRV
	sta drv_tty+0
	stx drv_tty+1
	rts
zendproc

; TTY routine implementations which delegate to a driver.

zproc entry_CONST
	ldy #TTY_CONST
	jmp (drv_tty)
zendproc

zproc entry_CONIN
	ldy #TTY_CONIN
	jmp (drv_tty)
zendproc

zproc entry_CONOUT
	ldy #TTY_CONOUT
	jmp (drv_tty)
zendproc

.bss
drv_tty: .fill 2
