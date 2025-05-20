; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"

; Converts ASCII to PETSCII for printing.

zproc topetscii
    cmp #8
    zif eq
        lda #20
        rts
    zendif
    cmp #127
    zif eq
        lda #20
        rts
    zendif

    cmp #'A'
    zif cs
        cmp #'Z'+1
        bcc swapcase
    zendif

    cmp #'a'
    zif cs
        cmp #'z'+1
        bcc swapcase
    zendif
    rts

swapcase:
    eor #$20
    rts
zendproc

