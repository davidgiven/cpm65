; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

;https://www.antimon.org/dl/c64/code/stable.txt

TEXT = 0x1000
FRAMEBUFFER = 0x1100
COLOURRAM = 0x9400

ZEROPAGE

ptr:		.fill 2
ptr1:		.fill 2
dma:		.fill 2

.section header, "ax"
    .word $1201
    .word 1f, 1
    .byte $9e
    .asciz "4621"
1:
    .word 0
.global _start
_start:
    ; Goodbye interrupts, we'll never use you again...

    sei

    ; Relocate the BIOS.

    zrepeat
        load1 = .
        lda bios_load_addr
        store1 = .
        sta bios_exec_addr

        inc load1+1
        zif_eq
            inc load1+2
        zendif

        inc store1+1
        zif_eq
            inc store1+2
            zbreakif_eq
        zendif

		lda store1+1
		cmp #<bios_end_addr
		zcontinueif_ne
		lda store1+2
		cmp #>bios_end_addr
    zuntil_eq

	; Relocate the init code --- we can't execute it here because BASIC will
	; load it right into the middle of what we're going to use as video memory.

    zrepeat
        load2 = .
        lda init_load_addr
        store2 = .
        sta init_exec_addr

        inc load2+1
        zif_eq
            inc load2+2
        zendif

        inc store2+1
        zif_eq
            inc store2+2
            zbreakif_eq
        zendif

		lda store2+1
		cmp #<init_end_addr
		zcontinueif_ne
		lda store2+2
		cmp #>init_end_addr
    zuntil_eq

	jmp _init

.section init, "ax"
_init:
	; Initialise the VIC.

	ldx #vic_tab_end - vic_tab
	zrepeat
		lda vic_tab-1, x
		sta 0x9000-1, x
		dex
	zuntil_eq

	lda #0x08			; black border, black background, inverted
	sta 0x900f

	jsr clear_screen

	jmp biosentry

vic_tab:
	.byte 14   			; 0x9000: abbbbbbb: interlace, screen X
	.byte 35            ; 0x9001: cccccccc: screen Y
	.byte 0x00 | 20     ; 0x9002: hddddddd: screen address, screen width
	.byte (12<<1) | 1   ; 0x9003: geeeeeef: screen height, char size
	.byte 0             ; 0x9004: gggggggg: variable
	.byte 0xcc          ; 0x9005: hhhhiiii: screen address, char address
vic_tab_end:

zproc biosentry
	jmp .
zendproc

; --- Screen handling ----------------------------------------------------

zproc clear_screen
	; Reset the character mapping on the screen.

	ldx #16
	zrepeat
		txa
		sta TEXT-16, x
		lda #1
		sta COLOURRAM-16, x
		inx
	zuntil_eq

	; Clear the bitmap itself.

	ldx #>(FRAMEBUFFER + 0xe00)
	ldy #0
	tya
	sta ptr+0
	zrepeat
		stx ptr+1
		zrepeat
			lda #0
			sta (ptr), y
			dec ptr+1
			lda ptr+1
			cmp #>(FRAMEBUFFER - 0x100)
		zuntil_eq
		iny
	zuntil_eq

	rts
zendproc

