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
    .word $0801
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

label:
    zrepeat
        ldx mwcommand_len
        dex
        zrepeat
        source_address = .+1
            lda drive_load_addr, x
            sta mwcommand_data, x
            dex
        zuntil mi

        jsr sendmwcommand
        jsr closecommand

        clc
        lda source_address+0
        adc mwcommand_len
        sta source_address+0
        zif cs
            inc source_address+1
        zendif

        clc
        lda mwcommand_addr+0
        adc mwcommand_len
        sta mwcommand_addr+0
        tax
        lda mwcommand_addr+1
        adc #0
        sta mwcommand_addr+1

        cpx #<drive_end_addr
        zcontinueif ne
        cmp #>drive_end_addr
    zuntil eq

    ; Run it.

    lda DA
    jsr LISTEN
    lda #0x6f
    jsr SECOND

    ldx #0
    zrepeat
        lda mecommand, x
        jsr CIOUT
        inx
        cpx #mecommand_end - mecommand
    zuntil eq

    jsr UNLSN

    sei
    jsr uload3_init

    ldx #0
    zrepeat
        lda loadbios_command, x
        stx ptr+1
        jsr uload3_send
        ldx ptr+1
        inx
        cpx #loadbios_command_end - loadbios_command
    zuntil eq

    zloop
        jsr uload3_recv
    zendloop
    jmp .

loading_msg:
    .byte 147, 14, 5
    .ascii "cp/m-65 FOR THE cOMMODORE 64"
    .byte 13, 0

baddrive_msg:
    .ascii "nOT A SUPPORTED DRIVE!"
    .byte 13, 0
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

zproc sendmwcommand
    lda #mwcommand_end - mwcommand
    ldx #<mwcommand
    ldy #>mwcommand
    jmp sendcommand
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

    lda DA
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

mwcommand:
    .ascii "M-W"
mwcommand_addr:
    .word drive_exec_addr
mwcommand_len:
    .byte 32
mwcommand_data:
    .fill 32
mwcommand_end:

mecommand:
    .ascii "M-E"
    .word drv_start
mecommand_end:

loadbios_command:
    .ascii "FBIOS"
    .byte 0
loadbios_command_end: