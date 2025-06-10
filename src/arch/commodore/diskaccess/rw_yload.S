; CP/M-65 Copyright © 2025 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

ZEROPAGE

.zeropage ptr
.zeropage ptr1

zproc rw_init, .init
    rts
zendproc

; Reads a 256-byte sector whose LBA index is in XA.

zproc rw_yload_read_sector
zproc read_sector, .text, weak
    tay
    txa
    pha
    tya
    pha

    lda #'R'
    jsr yload_send
    pla
    jsr yload_send
    pla
    jsr yload_send

    jsr yload_recv
    zif mi
        sec
        rts
    zendif

    ldy #0
    zrepeat
        jsr yload_recv
        sta disk_buffer, y
        iny
    zuntil eq

    clc
    rts
zendproc

; Writes a 256-byte sector whose LBA index is in XA.

zproc rw_yload_write_sector
zproc write_sector, .text, weak
    tay
    txa
    pha
    tya
    pha

    lda #'W'
    jsr yload_send
    pla
    jsr yload_send
    pla
    jsr yload_send

    ldx #0
    zrepeat
        lda disk_buffer, x
        jsr yload_send
        inx
    zuntil eq

    jsr yload_recv
    clc
    zif mi
        sec
    zendif
    rts
zendproc

