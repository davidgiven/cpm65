; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"
#include "c64.inc"

ZEROPAGE

.global ptr

ptr:       .fill 2

    .text
    .word 2f
2:
    .word 1f, 1
    .byte $9e
    .asciz "2061"
1:
    .word 0
zproc _start
    lda #$36
    sta 1                   ; map Basic out
    lda #0
    sta 53280               ; black border
    sta 53281               ; black background

    ; Print the startup banner (directly with CHROUT).

    ldx #<loading_msg
    ldy #>loading_msg
    jsr printstring

    ; Read 0xfea0 from the drive to get the family.

    jsr sendmrcommand
    jsr getbyte
    jsr closecommand

    ; Is this a 1541?

    cmp #0x0d
    zif ne
        ldx #<baddrive_msg
        ldy #>baddrive_msg
        jsr printstring
        jmp .
    zendif

    ; Upload the data itself.

    lda #usrcommand_end - usrcommand
    ldx #<usrcommand
    ldy #>usrcommand
    jsr sendcommand

    sei
    jsr yload_init
    jsr yload_test_link

    ; Read the directory.

    lda #'D'
    jsr yload_send

    jsr reset_ptr
    jsr yload_recv_file

    ; Scan the directory for the BIOS.

    jsr reset_ptr
    zrepeat
        ldx #0              ; offset into filename
        ldy #3              ; offset into dirent

        zloop
            lda biosfile, x
            cmp (ptr), y
            zbreakif ne
            inx
            iny
            cmp #0xa0
            beq bios_found
        zendloop
        
        clc
        lda ptr+0
        adc #32
        sta ptr+0
        zif cs
            inc ptr+1
        zendif
    zendloop
bios_found:
    
    ; Fetch the BIOS itself.

    lda #'F'
    jsr yload_send
    ldy #1
    lda (ptr), y
    jsr yload_send
    ldy #2
    lda (ptr), y
    jsr yload_send

    jsr reset_ptr
    jsr yload_recv_file
    jmp bootstrap_start

loading_msg:
    .byte 147, 14, 5
    .ascii "cp/m-65 FOR THE cOMMODORE 64"
    .byte 13, 0

baddrive_msg:
    .ascii "nOT A SUPPORTED DRIVE!"
    .byte 13, 0
zendproc

zproc reset_ptr
    lda #<bootstrap_start
    sta ptr+0
    lda #>bootstrap_start
    sta ptr+1
    rts
zendproc

; Prints the string in XY.
zproc printstring
    stx ptr+0
    sty ptr+1

    ldy #0
    zloop
        lda loading_msg, y
        zbreakif eq
        jsr CHROUT
        iny
    zendloop
    rts
zendproc

zproc sendmrcommand
    lda #mrcommand_end - mrcommand
    ldx #<mrcommand
    ldy #>mrcommand
zproc sendcommand
    jsr SETNAM

    lda #0x6f
    sta SA
    jmp SENDSECOND
zendproc

zproc closecommand
    pha
    jsr UNTALK
    jsr CLOSECURR
    pla
    rts
zendproc

zproc getbyte
    lda #0
    sta STATUS

    lda FA
    jsr TALK
    lda #0x6f
    jsr TALKSA
    jmp ACPTR
zendproc

.data

mrcommand:
    .ascii "M-R"
    .word 0xfea0
    .byte 1
mrcommand_end:

usrcommand:
    .ascii "&YLOAD1541"
usrcommand_end:

biosfile:
    .ascii "BIOS"
    .byte 0xa0
