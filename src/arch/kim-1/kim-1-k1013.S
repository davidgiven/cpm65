; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "cpm65.inc"
#include "k-1013.inc"

SEEK_RETRIES = 2
CHCK_RETRIES = 5
READ_RETRIES = 5
WRIT_RETRIES = 10

.section loader, "ax"

.global system_init
zproc system_init, loader
    ldy #0
    sty selected_drive

    dey
    sty buffered_track              ; Mark buffer data as invalid

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

    cmp #(dphtab_end-dphtab)/2      ; Check if drive number is supported
    bcs 1f                          ; drive > max. drive number

    ldy #CHCK_RETRIES
    sty tmp1
    zrepeat
        jsr check_drive_ready       ; Check drive status
        zif cc
            sta selected_drive
            asl a
            tay
            lda dphtab+0, y
            ldx dphtab+1, y
            rts
        zendif
        dec tmp1                    ; Decrement retries counter
    zuntil eq
    sec
1:  rts
zendproc

; Check if drive is ready.
; A is drive number
; Returns carry clear if ready, set otherwise
; Preserves A

zproc check_drive_ready
    pha
    tay
    jsr fdc_exec_sensestatus        ; Check drive status
    bcs 1f                          ; Command failed

    and #ST3_RY                     ; Check if ready flag is set
    zif eq
        sec
    zendif
1:  pla
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
        zif cs
            sbc #52
            inc ptr1+0
        zendif
        dex
    zuntil eq

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
    zif eq
        lda requested_track
        cmp buffered_track
        zif eq
            lda selected_drive
            cmp buffered_drive
            zif eq
                ; Buffered disk/track/sector not changing, so do no work.

                clc
                rts
            zendif
        zendif
    zendif

    ; If requested sector is not buffered, flush buffer before changing

    bit buffer_dirty
    zif mi
        jsr flush_buffer
        zif cs
            rts
        zendif
    zendif

    ; Change sector

    lda selected_drive
    sta buffered_drive
    lda requested_track
    sta buffered_track
    lda requested_cpm_sector
    sta buffered_host_sector

    ; Seek track

    jsr seek_track
    zif cs
        rts
    zendif

    ; Read sector from disk

    lda #READ_RETRIES
    sta tmp1
    zrepeat
        lda buffered_host_sector
        ldx buffered_track
        ldy buffered_drive
        jsr fdc_exec_read
        zif cc
            rts
        zendif

        dec tmp1
    zuntil eq

    ; Some kind of read error. The data in the buffer is corrupt.
zendproc
;
; Fall through
;
zproc invalidate_buffer
    lda #0xff
    sta buffered_track
    sec
    rts
zendproc

zproc flush_buffer
    jsr seek_track
    zif cc
        lda #WRIT_RETRIES
        sta tmp1
        zrepeat
            lda buffered_host_sector
            ldx buffered_track
            ldy buffered_drive

            jsr fdc_exec_write
            zif cc
                ; A successful write, so mark the buffer as clean.

                lda #0
                sta buffer_dirty

                ; Wait at least 500uS after write to allow the write current
                ; to decay before seeking again

                ldx #0
                zrepeat
                    dex
                zuntil eq

                rts
            zendif

            dec tmp1
        zuntil eq
        sec
    zendif
    rts
zendproc

zproc seek_track
    lda #SEEK_RETRIES
    sta tmp1
    zloop
        lda buffered_track
        ldy buffered_drive
        jsr fdc_exec_seek
        zbreakif cc

        dec tmp1
        zif ne
            ldy buffered_drive
            jsr fdc_exec_recal
            zcontinue
        zendif

        ; No more retries. Seek error, invalidate buffered track

        jmp invalidate_buffer
    zendloop
    rts
zendproc

; --- Data ------------------------------------------------------------------

.data

dphtab:
    .word dph0
    .word dph1
    .word dph2
    .word dph3
dphtab_end:

define_drive dph0, 77*52, 2048, 128, 52
define_drive dph1, 77*52, 2048, 128, 52
define_drive dph2, 77*52, 2048, 128, 52
define_drive dph3, 77*52, 2048, 128, 52

.bss

selected_drive:         .fill 1     ; Current selected disk drive number
buffer_offset:          .fill 1     ; Offset of CP/M sector into host sector buffer
requested_cpm_sector:   .fill 1     ; CP/M sector requested by user
requested_track:        .fill 1     ; track requested by user
buffered_host_sector:   .fill 1     ; host sector in buffer
buffered_track:         .fill 1     ; track in buffer
buffered_drive:         .fill 1     ; Drive of track/sector in buffer
