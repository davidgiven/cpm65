; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

ZEROPAGE

.global ptr
ptr:        .word 0
dma:        .word 0    ; current DMA

    .text

    .word $0401
    .word 1f, 1
    .byte $9e
    .asciz "1037"
1:
    .word 0
zproc _start
    rts
zendproc

; vim: sw=4 ts=4 et ft=asm

