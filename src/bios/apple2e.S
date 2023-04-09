; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

.global _start
ZEROPAGE

; --- Initialisation code ---------------------------------------------------

; Boot sector and relocator. Loaded at 0x0800 when the disk boots.  Called once
; on startup and then never again.
.section loader, "ax"
	.byte 1 ; number of sectors in boot image
_start:
    cli
	lda	0xC088, x			; turn off disk motor
    sta 0xc08b              ; R/W 0xe000 RAM; bank 1 in 0xd000
    sta 0xc08b              ; yes, I'm sure

    zloop
        load = .
        lda bios_load_addr
        store = .
        sta bios_exec_addr

        inc load+1
        zif_eq
            inc load+2
        zendif

        inc store+1
        zif_eq
            inc store+2
            zbreakif_eq
        zendif
    zendloop

	jmp .

zproc bios
    rts
zendproc

; This must go last --- it's the three 6502 vectors.
nmi_handler:
reset_handler:
irq_handler:
    rti

.text
    .word nmi_handler
    .word reset_handler
    .word irq_handler

; vim: filetype=asm sw=4 ts=4 et

