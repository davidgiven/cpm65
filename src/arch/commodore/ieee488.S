; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

ZEROPAGE

.zeropage ptr
.zeropage ptr1

ieee_has_buffered_char: .fill 1
ieee_buffered_char:     .fill 1

; Initialises the IEEE488 library.

zproc ieee_init, ".init"
    lda #0
    sta ieee_has_buffered_char
    sta ieee_buffered_char
    sta buffer_dirty

    ldy #3
    zrepeat
        lda #0
        sta sector_num-1, y
        lda #0xff
        sta buffered_sector-1, y
        dey
    zuntil_eq

    rts
zendproc

; Writes a single character in A with buffering.
; Preserves X and Y.

zproc ieee_write
    pha
    lda ieee_has_buffered_char
    zif_ne
        lda ieee_buffered_char
        jsr ieee_putb
    zendif
    lda #1
    sta ieee_has_buffered_char
    pla
    sta ieee_buffered_char
    rts
zendproc

; Flushes the last character with EOI asserted.
; Preserves X and Y.

zproc ieee_flush
    lda ieee_has_buffered_char
    zif_ne
        lda ieee_buffered_char
        jsr ieee_puteoib
        lda #0
        sta ieee_has_buffered_char
    zendif
    rts
zendproc

; See http://www.6502.org/users/andre/petindex/local/pet-io-2.txt
; https://www.pagetable.com/?p=1023
; http://www.primrosebank.net/computers/pet/documents/PET_and_the_IEEE488_Bus_text.pdf
; (appendix E)

; A is the secondary address (0xfX for OPEN).

zproc ieee_talk
    pha
    jsr ieee_mode_atn
    lda #0x48               ; TALK device 8
    jsr ieee_putb
    pla
    ora #0x60               ; SECOND
    jsr ieee_putb
    jmp ieee_mode_listen
zendproc

zproc ieee_untalk
    jsr ieee_mode_atn
    lda #0x5f               ; UNTALK
    jsr ieee_putb
    jmp ieee_mode_talk
zendproc

; A is the secondary address.

zproc ieee_listen
    pha
    jsr ieee_mode_atn
    lda #0x28               ; LISTEN device 8
    jsr ieee_putb
    pla
    ora #0x60               ; SECOND
    jsr ieee_putb
    jmp ieee_mode_talk
zendproc

zproc ieee_unlisten
    jsr ieee_flush
    jsr ieee_mode_atn
    lda #0x3f               ; UNLISTEN
    jsr ieee_putb
    jmp ieee_mode_talk
zendproc

; Sets the current DMA address.

zproc bios_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc bios_SELDSK
    cmp #0
    zif_ne
        sec                 ; invalid drive
        rts
    zendif

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

zproc bios_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil_mi
    clc
    rts
zendproc

zproc bios_READ
    jsr change_sectors
    zif_cc
        lda sector_num+0
        ror a               ; bottom bit -> C
        lda #0
        ror a               ; C -> top bit, producing $00 or $80
        tax

        ldy #0
        zrepeat
            lda disk_buffer, x
            sta (dma), y
            iny
            inx
            cpy #$80
        zuntil_eq

        clc
    zendif
    rts
zendproc

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc bios_WRITE
    pha
    jsr change_sectors
    zif_cs
        pla
        sec
        rts
    zendif

    lda sector_num+0
    ror a               ; bottom bit -> C
    lda #0
    ror a               ; C -> top bit, producing $00 or $80
    tax

    ldy #0
    zrepeat
        lda (dma), y
        sta disk_buffer, x
        iny
        inx
        cpy #$80
    zuntil_eq

    lda #$80
    sta buffer_dirty

    pla
    zif_ne
        jmp flush_buffered_sector
    zendif

    clc
    rts
zendproc

; Returns C on error.

zproc change_sectors
    ; If the buffered sector is the one we want, just return.

    lda sector_num+0
    and #$fe
    cmp buffered_sector+0
    zif_eq
        lda sector_num+1
        cmp buffered_sector+1
        zif_eq
            lda sector_num+2
            cmp buffered_sector+2
            zif_eq
                clc
                rts
            zendif
        zendif
    zendif

    ; We need to change sectors. Flush the current one?

    jsr flush_buffered_sector

    ; Now read the new one.

    lda sector_num+0
    and #$fe
    sta buffered_sector+0
    lda sector_num+1
    sta buffered_sector+1
    lda sector_num+2
    sta buffered_sector+2

    jsr buffered_sector_to_lba
    jmp read_sector
zendproc

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
    zuntil_eq

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
    zuntil_cs

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
    zuntil_eq

    jsr ieee_unlisten

    ; Write bytes.

    lda #0x62               ; SECOND channel 2
    jsr ieee_listen

    ldy #0
    zrepeat
        lda disk_buffer, y
        jsr ieee_write
        iny
    zuntil_eq

    jsr ieee_unlisten

    ; Write sector to disk.

    lda #0x6f               ; SECOND channel 15
    jsr ieee_listen

    ldx #u2_string_end - u2_string
    zrepeat
        lda u2_string-1, x
        jsr ieee_write
        dex
    zuntil_eq

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

.if 1
zproc getstatus
    lda #0x6f
    jsr ieee_talk

    zloop
        jsr ieee_getb
        zbreakif_cs
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
    zuntil_cc
    adc #100
    jsr digit

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #10
    zuntil_cc
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
        zif_eq
            cmp track_size_table, y
            zif_cc
                iny     ; tracks are one-based.
                rts
            zendif
        zendif

        sec
        sbc track_size_table, y
        zif_cc
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

; Compute the current LBA sector number in XA for the buffered sector.

zproc buffered_sector_to_lba
    lda buffered_sector+1
    lsr a
    tax
    lda buffered_sector+0
    ror
    rts
zendproc

zproc flush_buffered_sector
    bit buffer_dirty
    zif_mi
        jsr buffered_sector_to_lba
        jsr write_sector

        lda #0
        sta buffer_dirty
    zendif
    rts
zendproc

ZEROPAGE

dma:             .fill 2

sector_num:      .fill 3 ; current absolute sector number
buffered_sector: .fill 3 ; sector currently in disk buffer

.bss

.global directory_buffer
directory_buffer: .fill 128
disk_buffer:      .fill 256
buffer_dirty:     .fill 1 ; non-zero if sector needs flushing

; DPH for drive 0 (our only drive)

define_drive dph, 136*10, 1024, 64, 0


