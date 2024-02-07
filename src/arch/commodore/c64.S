; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

READST = $ffb7
SETLFS = $ffba
SETNAM = $ffbd
OPEN = $ffc0
CLOSE = $ffc3
CHKIN = $ffc6
CHKOUT = $ffc9
CHRIN = $ffcf
CHROUT = $ffd2
LOAD = $ffd5
SAVE = $ffd8
CLALL = $ffe7
SETMSG = $ff90
ACPTR = $ffa5
CIOUT = $ffa8
UNTALK = $ffab
UNLSN = $ffae
LISTEN = $ffb1
TALK = $ffb4
SECOND = $ff93
TALKSA = $ff96
CLRCHN = $ffcc
GETIN = $ffe4
STATUS = $90

ZEROPAGE

.global ptr
.global ptr1
ptr:        .word 0
ptr1:       .word 0
dma:        .word 0    ; current DMA

    .text

    .word $0801
    .word 1f, 1
    .byte $9e
    .asciz "2061"
1:
    .word 0
zproc _start
    jsr init_system

    ; Load the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy mem_base
    jsr loadfile

    ; Relocate the BDOS.

    lda mem_base
    ldx zp_base
    jsr bios_RELOCATE

    ; Compute the entry address and jump.

    lda mem_base
    pha
    lda #COMHDR_ENTRY-1 ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump

bdos_filename:
    .ascii "BDOS    SYS"
zendproc

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    pha
    lda jmptable_lo, y
    sta ptr+0
    lda jmptable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

jmptable_lo:
    .byte tty_const@mos16lo
    .byte tty_conin@mos16lo
    .byte tty_conout@mos16lo
jmptable_hi:
    .byte tty_const@mos16hi
    .byte tty_conin@mos16hi
    .byte tty_conout@mos16hi
zendproc

; Blocks and waits for the next keypress; returns it in A.

zproc tty_conin
    lda pending_key
    zif_eq
        zrepeat
            jsr GETIN
            tax
        zuntil_ne
    zendif
    ldx #0
    stx pending_key

    cmp #20         ; DEL
    zif_eq
        lda #8
    zendif

    clc
    rts
zendproc

zproc tty_conout
    jsr topetscii
    jsr CHROUT
    clc
    rts
zendproc

zproc tty_const
    lda pending_key
    zif_eq
        jsr GETIN
        sta pending_key
        zif_eq
            lda #0
            clc
            rts
        zendif
    zendif

    lda #$ff
    clc
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

zproc bios_GETTPA
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc bios_SETTPA
    sta mem_base
    stx mem_end
    clc
    rts
zendproc

zproc bios_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc

zproc bios_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc bios_SETBANK
    rts
zendproc

zproc bios_READ
    jsr change_sectors

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
    rts
zendproc

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc bios_WRITE
    pha
    jsr change_sectors

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
        jsr flush_buffered_sector
    zendif

    clc
    rts
zendproc

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

; Flush the current buffer to disk, if necessary.

zproc flush_buffered_sector
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
    jsr LISTEN
    lda #$6f
    jsr SECOND

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
    jsr TALKSA

    ldy #0
    zrepeat
        jsr ACPTR
        sta disk_buffer, y
        iny
    zuntil_eq

    jsr UNTALK
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
    jsr LISTEN
    lda #$6f
    jsr SECOND

    lda #<reset_buffer_pointer_command
    ldx #>reset_buffer_pointer_command
    jsr string_out

    jsr UNLSN

    ; Write bytes.

    lda #8
    jsr LISTEN
    lda #$62
    jsr SECOND

    ldy #0
    zrepeat
        lda disk_buffer, y
        jsr CIOUT
        iny
    zuntil_eq

    jsr UNLSN

    ; Write buffer to disk.

    lda #8
    jsr LISTEN
    lda #$6f
    jsr SECOND

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

; Prints an 8-bit hex number in A.
zproc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr h4
    pla
h4:
    and #0x0f ; %00001111
    ora #'0'
    cmp #'9'+1
    zif_cs
        adc #6
    zendif
    pha
    jsr CHROUT
    pla
    rts
zendproc

zproc get_status
    lda #8
    jsr TALK
    lda #$6f
    jsr TALKSA

    zrepeat
        jsr ACPTR
        jsr CHROUT
        cmp #13
    zuntil_eq

    jsr UNTALK
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

; Prints the string at XA with the kernel.

zproc print
    sta ptr+0
    stx ptr+1

    ldy #0
    zloop
        lda (ptr), y
        zbreakif_eq

        jsr topetscii
        jsr CHROUT

        iny
    zendloop
    rts
zendproc

zproc init_system
    lda #$36
    sta 1                   ; map Basic out
    lda #0
    sta 53280               ; black border
    sta 53281               ; black background

    ; Print the startup banner (directly with CHROUT).

    ldy #0
    zloop
        lda loading_msg, y
        zbreakif_eq
        jsr CHROUT
        iny
    zendloop

    ; General initialisation.

    lda #0
    sta pending_key
    sta buffer_dirty
    lda #$ff
    sta buffered_sector+0
    sta buffered_sector+1
    sta buffered_sector+2

    jsr initdrivers

    lda #8
    jsr LISTEN
    lda #$f2
    jsr SECOND
    lda #'#'
    jsr CIOUT
    jsr UNLSN

    rts
zendproc

loading_msg:
    .byte 147, 14, 5
    .ascii "cp/m-65 FOR THE cOMMODORE 64"
    .byte 13, 0

.data

zp_base:    .byte __USERZEROPAGE_START__
zp_end:     .byte __USERZEROPAGE_END__
mem_base:   .byte __USERTPA_START__@mos16hi
mem_end:    .byte __USERTPA_END__@mos16hi

; DPH for drive 0 (our only drive)

define_drive dph, 136*10, 1024, 64, 0

NOINIT

pending_key:     .byte 0 ; pending keypress from system
sector_num:      .fill 3 ; current absolute sector number
buffered_sector: .fill 3 ; sector currently in disk buffer
buffer_dirty:    .fill 1 ; non-zero if sector needs flushing

.global directory_buffer
directory_buffer: .fill 128
disk_buffer: .fill 256

; vim: sw=4 ts=4 et ft=asm

