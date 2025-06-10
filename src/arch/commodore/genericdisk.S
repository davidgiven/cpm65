; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

ZEROPAGE

.zeropage ptr
.zeropage ptr1

dma:             .fill 2

sector_num:      .fill 3 ; current absolute sector number
buffered_sector: .fill 3 ; sector currently in disk buffer

; Initialises the disk library.

zproc genericdisk_init, ".init"
    lda #0
    sta buffer_dirty

    ldy #3
    zrepeat
        lda #0
        sta sector_num-1, y
        lda #0xff
        sta buffered_sector-1, y
        dey
    zuntil eq

    rts
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
    zif ne
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
    zuntil mi
    clc
    rts
zendproc

zproc bios_READ
    jsr change_sectors
    zif cc
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
        zuntil eq

        clc
    zendif
    rts
zendproc

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc bios_WRITE
    pha
    jsr change_sectors
    zif cs
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
    zuntil eq

    lda #$80
    sta buffer_dirty

    pla
    zif ne
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
    zif eq
        lda sector_num+1
        cmp buffered_sector+1
        zif eq
            lda sector_num+2
            cmp buffered_sector+2
            zif eq
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
    zif mi
        jsr buffered_sector_to_lba
        jsr write_sector

        lda #0
        sta buffer_dirty
    zendif
    rts
zendproc

.bss

.global directory_buffer, disk_buffer
disk_buffer:      .fill 256
directory_buffer: .fill 128
buffer_dirty:     .fill 1 ; non-zero if sector needs flushing

; DPH and DPB for drive 0 (our only drive)

define_dpb dpb_1541, 136*10, 1024, 64, 0
define_dph dph, dpb_1541
