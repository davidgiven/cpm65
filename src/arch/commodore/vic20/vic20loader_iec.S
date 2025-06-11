; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "vic20.inc"

ZEROPAGE

.global ptr

ptr:       .fill 2

    .text
    .word 2f
2:
    .word 1f, 1
    .byte $9e
    .asciz "4621"
1:
    .word 0
zproc _start
    lda #1
    ldx #8
    ldy #2
    jsr SETLFS

    lda #biosfile_end - biosfile
    ldx #<biosfile
    ldy #>biosfile
    jsr SETNAM

    jsr OPEN

    ldx #1
    jsr CHKIN

    lda #<bootstrap_start
    sta ptr+0
    lda #>bootstrap_start
    sta ptr+1
    zrepeat
        ldy #0
        sty STATUS
        jsr CHRIN

        sta (ptr), y
        inc ptr+0
        zif eq
            inc ptr+1
            lda #'.'
            jsr CHROUT
        zendif

        lda STATUS
    zuntil ne

    jsr CLRCHN

    lda #1
    jsr CLOSE
    jmp bootstrap_start
zendproc

.data

biosfile:
    .ascii "BIOS,P,R"
biosfile_end:
