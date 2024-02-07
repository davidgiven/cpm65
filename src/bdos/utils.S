; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "jumptables.inc"
#include "bdos.inc"

; Shifts XA right Y bits.
; Uses temp. Leaves the shifted value in temp+0.

zproc shiftr, .text.shiftr
    sta temp+0
    stx temp+1
.global shiftr_temp0
shiftr_temp0:
    iny
    zloop
        dey
        beq shift_exit
        clc
        ror temp+1
        ror temp+0
    zendloop
shift_exit:
    lda temp+0
    ldx temp+1
    rts
zendproc

; Shifts XA left Y bits.
; Uses temp. Leaves the shifted value in temp+0.

zproc shiftl, .text.shiftl
    sta temp+0
    stx temp+1
    iny
    zloop
        dey
        beq shift_exit
        clc
        rol temp+0
        rol temp+1
    zendloop
zendproc

; Sets bit Y of (XA).
; Uses temp.

zproc setbit, .text.setbit
    sta temp+2
    stx temp+3

    lda #1
    ldx #0
    jsr shiftl      ; shift it left by Y

    ldy #1
    zrepeat
        lda (temp+2), y
        ora temp+0, y
        sta (temp+2), y
        dey
    zuntil_mi

    rts
zendproc

; Rotate A right X times.
zproc rotater8, .text.rotater8
    inx
    zloop
        dex
        zbreakif_eq
        lsr a
        zif_cs
            ora #$80
        zendif
    zendloop
    rts
zendproc

; Rotate A left X times.
zproc rotatel8, .text.rotatel8
    inx
    zloop
        dex
        zbreakif_eq
        asl a
        adc #0
    zendloop
    rts
zendproc

