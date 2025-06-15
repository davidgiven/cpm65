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
    sei
    jsr io_init

    lda #0xf2               ; OPEN channel 2
    jsr ieee_listen

    ldx #0
    zrepeat
        lda biosfile, x
        jsr ieee_write
        inx
        cpx #biosfile_end - biosfile
    zuntil eq
    
    jsr ieee_unlisten

    lda #0x62               ; READ channel 2
    jsr ieee_talk

    lda #<bootstrap_start
    sta ptr+0
    lda #>bootstrap_start
    sta ptr+1
    zrepeat
        jsr ieee_getb
        php

        ldy #0
        sta (ptr), y
        inc ptr+0
        zif eq
            inc ptr+1
            lda #'.'
            cli
            jsr CHROUT
            sei
        zendif
        
        plp
    zuntil cs

    jsr ieee_untalk
    jsr dumperror

    lda #0xe2               ; CLOSE channel 2
    jsr ieee_listen
    jsr ieee_unlisten

    jmp bootstrap_start
zendproc

.data

biosfile:
    .ascii "BIOS,P,R"
biosfile_end:

zproc dumperror
    lda #0x5f               ; READ channel 15
    jsr ieee_talk

    zrepeat
        jsr ieee_getb
        php
        cli
        jsr CHROUT
        sei
        plp
    zuntil cs
    lda #13
    jsr CHROUT

    jsr ieee_untalk
    rts
zendproc
