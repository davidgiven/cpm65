; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

;https://www.antimon.org/dl/c64/code/stable.txt

TEXT = 0x0200
FRAMEBUFFER = 0x1000

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
	lda 0x9002
	ora #0x80
	sta 0x9002

	lda #0x8c
	sta 0x9005

	ldy #0
	zrepeat
		tya
		sta TEXT+0x000, y
		sta TEXT+0x100, y
		sta FRAMEBUFFER+0x000, y
		sta FRAMEBUFFER+0x100, y
		sta FRAMEBUFFER+0x200, y
		sta FRAMEBUFFER+0x300, y
		iny
	zuntil_eq

	jmp biosentry

zproc biosentry
	jmp .
zendproc

