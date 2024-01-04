; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65.inc"
#include "driver.inc"
#include "zif.inc"

zproc _call_serial, .text._call_serial
    jmp 0
zendproc

zproc serial_init, .text.screen_init
    lda #<DRVID_SERIAL
    ldx #>DRVID_SERIAL
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta _call_serial+1
    stx _call_serial+2
    lda #0
    ror a
    eor #0x80
    rts
zendproc

zproc serial_open, .text.serial_open
    ldy #SERIAL_OPEN
    jmp _call_serial
zendproc

zproc serial_close, .text.serial_close
    ldy #SERIAL_CLOSE
    jmp _call_serial
zendproc

zproc _serial_inp, .text._serial_inp
    ldy #SERIAL_INP
    jsr _call_serial
    zif_cs
        ldx #0
        rts
    zendif
    ldx #1
    rts
zendproc

zproc serial_out, .text.serial_out
    ldy #SERIAL_OUT
    jmp _call_serial
zendproc

zproc serial_outp, .text.serial_outp
    ldy #SERIAL_OUTP
    jmp _call_serial
zendproc

zproc serial_in, .text.serial_in
    ldy #SERIAL_IN
    jmp _call_serial
zendproc

