; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "cpm65.inc"

.section loader, "ax"

.global system_init
zproc system_init, loader
    lda #0xff
    sta buffered_host_sector

    ; Init drives 1-3. Ignore errors as drives may not be present.
    ldy #1
    jsr fdc_exec_recal
    ldy #2
    jsr fdc_exec_recal
    ldy #3
    jsr fdc_exec_recal

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

    ; Copy bottom 16 of sector number to temporary (the top byte must be 0).

    ldy #0
    lda (ptr), y
    sta ptr1+0
    iny
    lda (ptr), y
    sta ptr1+1

    ; There are 52 CP/M sectors per host track (each 256 byte host sector
    ; contains two CP/M sects). Do a 16-bit divide.

    ldx #16
    lda #0
    zrepeat
        asl ptr1+0
        rol ptr1+1
        rol a
        cmp #52
        zif_cs
            sbc #52
            inc ptr1+0
        zendif
        dex
    zuntil_eq

    ; Host sectors are 256 bytes long, so divide by 2 and put carry as MSB of
    ; buffer_offset
    lsr a
    sta requested_cpm_sector
    lda #0
    ror a
    sta buffer_offset

    lda ptr1+0
    sta requested_track

    clc
    rts
zendproc

; --- Disk access -----------------------------------------------------------

zproc set_disk_buffer_offset
    ; WARNING: DISK_BUFFER __must__ be page aligned!!

    lda buffer_offset
    sta ptr+0
    lda #>DISK_BUFFER
    sta ptr+1

    rts
zendproc

zproc change_sector
    ; First check if requested sector is already in buffer

    lda requested_cpm_sector
    cmp buffered_host_sector
    zif_eq
        lda requested_track
        cmp buffered_track
        zif_eq
            lda current_drive
            cmp buffered_drive
            zif_eq
                ; Buffered disk/track/sector not changing, so do no work.

                clc
                rts
            zendif
        zendif
    zendif

    ; If requested sector is not buffered, flush buffer before changing

    bit buffer_dirty
    zif_mi
        jsr flush_buffer
        zif_cs
            rts
        zendif
    zendif

    ; Change sector

    lda current_drive
    sta buffered_drive
    lda requested_track
    sta buffered_track
    lda requested_cpm_sector
    sta buffered_host_sector

    ; Seek track

    jsr seek_track
    zif_cs
        rts
    zendif

    ; Read sector from disk

    lda #2                          ; Retries
    sta tmp1
    zrepeat
        lda buffered_host_sector
        ldx buffered_track
        ldy buffered_drive
        jsr fdc_exec_read
        zif_cc
            rts
        zendif

        dec tmp1
    zuntil_eq

    ; Some kind of read error. The data in the buffer is corrupt.

    lda #0xff
    sta buffered_host_sector

    rts
zendproc

zproc flush_buffer
    jsr seek_track
    zif_cs
        rts
    zendif

    lda #2                          ; Retries
    sta tmp1
    zrepeat
        lda buffered_host_sector
        ldx buffered_track
        ldy buffered_drive

        jsr fdc_exec_write
        zif_cc
            ; A successful write, so mark the buffer as clean.

            lda #0
            sta buffer_dirty
            rts
        zendif

        dec tmp1
    zuntil_eq

    sec
    rts
zendproc

zproc seek_track
    lda #2                          ; Retries
    sta tmp1
    zloop
        lda buffered_track
        ldy buffered_drive
        jsr fdc_exec_seek
        zbreakif_cc

        dec tmp1
        zif_ne
            ldy buffered_drive
            jsr fdc_exec_recal
            zcontinue
        zendif

        ; No more retries. Seek error, invalidate buffered track

        lda #0xff
        sta buffered_track
        sec
        rts
    zendloop
    rts
zendproc

; --- Data ------------------------------------------------------------------

.data

; DPH for drive 0

define_drive dph0, 77*52, 2048, 128, 52

.bss

current_drive:          .fill 1     ; Current selected disk drive number
buffer_offset:          .fill 1     ; Offset of CP/M sector into host sector buffer
requested_cpm_sector:   .fill 1     ; CP/M sector requested by user
requested_track:        .fill 1     ; track requested by user
buffered_host_sector:   .fill 1     ; host sector in buffer
buffered_track:         .fill 1     ; track in buffer
buffered_drive:         .fill 1     ; Drive of track/sector in buffer
