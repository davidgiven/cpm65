; Ohio Scientific Instruments ASCII keyboard routines.
; Copyright © 2024 by Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

ZEROPAGE

cur_char:   .fill 1
wait_cntr:  .fill 1
last_char:  .fill 1

KEYBD = $df01

; ----------------------------------------------------------------------------

    .section .text, "ax"

scan_keyboard:

    zloop
        lda KEYBD

        zif mi
            sta last_char
            sta cur_char
            ldx #2
            stx wait_cntr
            rts
        zendif

        cmp cur_char
        zif ne
            sta cur_char
            lda #2
            sta wait_cntr
            zcontinue
        zendif

        dec wait_cntr
        zbreakif eq

        ldy #$10
        zloop
            ldx #$40
            zloop
                dex
            zuntil eq
            dey
        zuntil eq
    zendloop

    ldx #$64                ; long delay on first character
    cmp last_char
    zif eq
        ldx #$0f                ; shorter repeat rate
    zendif

    stx wait_cntr
    sta last_char

    rts

; ----------------------------------------------------------------------------

; vim: filetype=asm sw=4 ts=4 et
