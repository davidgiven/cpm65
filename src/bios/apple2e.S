; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

.text
	.byte 1 ; number of sectors in boot image

ZEROPAGE

; --- Initialisation code ---------------------------------------------------

; Called once on startup and then never again.
; TODO: figure out a way to discard this after startup.

zproc _start
	lda	0xC088, x			; turn off disk motor
	jmp .

; vim: filetype=asm sw=4 ts=4 et

