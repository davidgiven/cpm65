; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

ZEROPAGE

.zeropage ptr
.zeropage ptr1

; Reads a 256-byte sector whose LBA index is in XA.

zproc read_sector
    jsr convert_to_ts
    pha
    tya
    pha

    lda #0x6f               ; SECOND channel 15
    jsr ieee_listen

    ldx #u1_string_end - u1_string
    zrepeat
        lda u1_string-1, x
        jsr ieee_write
        dex
    zuntil eq

    pla
    jsr decimal_out

    pla
    jsr decimal_out
    jsr ieee_unlisten

    lda #0x62               ; SECOND channel 2
    jsr ieee_talk

    ldy #0
    zrepeat
        jsr ieee_getb
        sta disk_buffer, y
        iny
    zuntil cs

    jsr ieee_untalk
    clc
    rts

u1_string:
    .ascii "0 2 1U" ; reversed!
u1_string_end:
zendproc

; Writes a 256-byte sector whose LBA index is in XA.

zproc write_sector
    jsr convert_to_ts
    pha
    tya
    pha

    ; Reset buffer pointer.

    lda #0x6f               ; SECOND channel 15
    jsr ieee_listen

    ldx #bp_string_end - bp_string
    zrepeat
        lda bp_string-1, x
        jsr ieee_write
        dex
    zuntil eq

    jsr ieee_unlisten

    ; Write bytes.

    lda #0x62               ; SECOND channel 2
    jsr ieee_listen

    ldy #0
    zrepeat
        lda disk_buffer, y
        jsr ieee_write
        iny
    zuntil eq

    jsr ieee_unlisten

    ; Write sector to disk.

    lda #0x6f               ; SECOND channel 15
    jsr ieee_listen

    ldx #u2_string_end - u2_string
    zrepeat
        lda u2_string-1, x
        jsr ieee_write
        dex
    zuntil eq

    pla
    jsr decimal_out

    pla
    jsr decimal_out

    jsr ieee_unlisten

    clc
    rts

bp_string:
    .ascii "0 2 P-B" ; reversed!
bp_string_end:
u2_string:
    .ascii "0 2 2U" ; reversed!
u2_string_end:
zendproc

.if 0
zproc getstatus
    lda #0x6f
    jsr ieee_talk

    zloop
        jsr ieee_getb
        zbreakif cs
        jsr bios_CONOUT
    zendloop

    lda #0x0d
    jsr bios_CONOUT
    lda #0x0a
    jsr bios_CONOUT
    jsr ieee_untalk
    rts
zendproc
.endif

; Prints a decimal number in A to the IEEE output.

zproc decimal_out
    pha
    lda #' '
    jsr ieee_write
    pla

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #100
    zuntil cc
    adc #100
    jsr digit

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #10
    zuntil cc
    adc #10
    jsr digit
    tax
digit:
    pha
    txa
    ora #'0'
    jsr ieee_write
    pla
    rts
zendproc

; Converts an LBA sector number in XA to track/sector in Y, A.

zproc convert_to_ts
    ldy #0
    zloop
        cpx #0
        zif eq
            cmp track_size_table, y
            zif cc
                iny     ; tracks are one-based.
                rts
            zendif
        zendif

        sec
        sbc track_size_table, y
        zif cc
            dex
        zendif
        iny
    zendloop

track_size_table:
    .fill 17, 1, 21
    .fill 7, 1, 19
    .fill 6, 1, 18
    .fill 10, 1, 17
zendproc
