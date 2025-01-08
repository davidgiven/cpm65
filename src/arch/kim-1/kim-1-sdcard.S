; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "cpm65.inc"

.section loader, "ax"

.global system_init
zproc system_init, loader
    ldy #0
    sty current_drive
    sty zp_sd_currentsector+3           ; Always 0

    dey
    sty zp_sd_currentsector+2           ; Mark buffer data as invalid

    lda #<DISK_BUFFER
    sta zp_sd_address+0
    lda #>DISK_BUFFER
    sta zp_sd_address+1

    ; Determine RAM size. Assumes at least a memory expansion from 0x2000 to 0x9fff

    ldy #0
    sty ptr+0
    lda #0xa0
    sta ptr+1

    zloop
        lda #0x55
        sta (ptr), y
        lda (ptr), y
        cmp #0x55
        bne 1f
        lda #0xaa
        sta (ptr), y
        lda (ptr), y
        cmp #0xaa
        bne 1f
        iny
        zif_eq
            inc ptr+1
            lda ptr+1
            cmp #0xff
            beq 1f
        zendif
    zendloop
1:  lda ptr+1
    sta mem_end

    rts

.text

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

    lda #<dph0
    ldx #>dph0
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

zproc bios_SETSEC
    sta ptr+0
    stx ptr+1

    ; Copy the sector number to requested_cpm_sector

    ldy #2
    zrepeat
        lda (ptr), y
        sta requested_cpm_sector, y
        dey
    zuntil_mi

    ; Divide by 4, keeping the 2 LSB of the CPM sector as the
    ; 2 MSB of buffer_offset

    lda #0
    sta buffer_offset
    ldy #2
    zrepeat
        lsr requested_cpm_sector+2
        ror requested_cpm_sector+1
        ror requested_cpm_sector+0
        ror buffer_offset
        dey
    zuntil_eq

    ; Use the disk number to set the offset into the sd card

    lda current_drive
    sta requested_cpm_sector+2

    clc
    rts
zendproc

; --- Disk access -----------------------------------------------------------

; This assumes that DISK_BUFFER is page aligned!!

zproc set_disk_buffer_offset
    lda #<DISK_BUFFER
    sta ptr+0
    lda #>DISK_BUFFER
    sta ptr+1

    bit buffer_offset
    zif_mi
        inc ptr+1
    zendif
    zif_vs
        lda #0x80
        sta ptr+0
    zendif

    rts
zendproc

zproc change_sector
    ; First check if requested sector is already in buffer

    ldy #2
    zrepeat
        lda requested_cpm_sector, y
        cmp zp_sd_currentsector, y
        bne 1f
        dey
    zuntil_mi

    ; Buffered sector not changing, so do no work.

    clc
    rts

    ; If requested sector is not buffered, flush buffer before changing

1:  bit buffer_dirty
    zif_mi
        jsr flush_buffer
        zif_cs
            rts
        zendif
    zendif

    ; Change sector

    ldy #2
    zrepeat
        lda requested_cpm_sector, y
        sta zp_sd_currentsector, y
        dey
    zuntil_mi

    ; Read sector from disk

    jsr sd_readsector
    zif_cs
        ; Some kind of read error. The data in the buffer is corrupt.

        lda #0xff
        sta zp_sd_currentsector+2
    zendif

    rts
zendproc

zproc flush_buffer
    jsr sd_writesector
    zif_cc
        ; A successful write, so mark the buffer as clean.

         lda #0
        sta buffer_dirty
        rts
    zendif

    rts
zendproc

; --- Data ------------------------------------------------------------------

.data

; DPH for drives 0

define_drive dph0, 4096*64, 4096, 1024, 64

.bss

current_drive:          .fill 1     ; Current selected disk drive number
buffer_offset:          .fill 1     ; Offset of CP/M sector into host sector buffer
requested_cpm_sector:   .fill 3     ; CP/M sector requested by user
