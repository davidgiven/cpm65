; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "cpm65.inc"

DEFDRIVE = $08          ; Default drive number

#ifdef PAL_1
TALK    = $dcfe
LISTN   = $dd01
SECND   = $ddaa
TKSA    = $ddb9
CIOUT   = $ddce
UNTLK   = $dde3
UNLSN   = $ddf2
ACPTR   = $de07
#else
TALK    = $f2fe
LISTN   = $f301
SECND   = $f3aa
TKSA    = $f3b9
CIOUT   = $f3ce
UNTLK   = $f3e3
UNLSN   = $f3f2
ACPTR   = $f407
#endif

.section loader, "ax"

    .word _start

#include "kim-1.S"

    ; System init

zproc system_init, loader
    lda #0
    sta current_drive
    sta pending_key
    sta buffer_dirty

    lda #0xff
    sta buffered_sector+0
    sta buffered_sector+1
    sta buffered_sector+2

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

    lda #DEFDRIVE
    jsr LISTN
    lda #$f2
    jsr SECND
    lda #'#'
    jsr CIOUT
    jsr UNLSN

    rts
zendproc

.text

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

    lda sector_num+0
    ror a               ; bottom bit -> C
    lda #0
    ror a               ; C -> top bit, producing $00 or $80
    sta buffer_offset

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

    jsr flush_buffer

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

; Flush the current buffer to disk, if necessary.

zproc flush_buffer
    lda buffer_dirty
    zif_mi
        jsr buffered_sector_to_lba
        jsr write_sector

        lda #0
        sta buffer_dirty
    zendif
    rts
zendproc

; Reads a 256-byte sector whose LBA index is in XA.

zproc read_sector
    jsr convert_to_ts
    pha
    tya
    pha

    lda #8
    jsr LISTN
    lda #$6f
    jsr SECND

    lda #'U'
    jsr CIOUT
    lda #'1'
    jsr CIOUT
    lda #2
    jsr decimal_out
    lda #0
    jsr decimal_out
    pla                 ; get sector
    jsr decimal_out
    pla                 ; get track
    jsr decimal_out

    jsr UNLSN

    ;jsr get_status

    lda #8
    jsr TALK
    lda #$62
    jsr TKSA

    ldy #0
    zrepeat
        jsr ACPTR
        sta DISK_BUFFER, y
        iny
    zuntil_eq

    jsr UNTLK
    rts
zendproc

; Writes a 256-byte sector whose LBA index is in XA.

zproc write_sector
    jsr convert_to_ts
    pha
    tya
    pha

    ; Reset buffer pointer.

    lda #8
    jsr LISTN
    lda #$6f
    jsr SECND

    lda #<reset_buffer_pointer_command
    ldx #>reset_buffer_pointer_command
    jsr string_out

    jsr UNLSN

    ; Write bytes.

    lda #8
    jsr LISTN
    lda #$62
    jsr SECND

    ldy #0
    zrepeat
        lda DISK_BUFFER, y
        jsr CIOUT
        iny
    zuntil_eq

    jsr UNLSN

    ; Write buffer to disk.

    lda #8
    jsr LISTN
    lda #$6f
    jsr SECND

    lda #'U'
    jsr CIOUT
    lda #'2'
    jsr CIOUT
    lda #2
    jsr decimal_out
    lda #0
    jsr decimal_out
    pla                 ; get sector
    jsr decimal_out
    pla                 ; get track
    jsr decimal_out
    lda #13
    jsr CIOUT

    jsr UNLSN

    ; jsr get_status

    rts

reset_buffer_pointer_command:
    .ascii "B-P 2 0"
    .byte 13, 0
zendproc

zproc get_status
    lda #8
    jsr TALK
    lda #$6f
    jsr TKSA

    zrepeat
        jsr ACPTR
        jsr OUTCH
        cmp #13
    zuntil_eq

    jsr UNTLK
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

; Prints a decimal number in A to the IEC output.

zproc decimal_out
    pha
    lda #' '
    jsr CIOUT
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
    jsr CIOUT
    pla
    rts
zendproc

zproc string_out
    sta ptr+0
    stx ptr+1

    ldy #0
    zloop
        lda (ptr), y
        zif_eq
            rts
        zendif
        jsr CIOUT
        iny
    zendloop
zendproc

; --- Data ------------------------------------------------------------------

.data

; DPH for drive 0 (our only drive)

define_drive dph0, 136*10, 1024, 64, 0

.bss

sector_num:      .fill 3 ; current absolute sector number
buffered_sector: .fill 3 ; sector currently in disk buffer
