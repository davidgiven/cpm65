; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65.inc"
#include "zif.inc"

.zeropage ptr
.zeropage ptr1

; This is a very simple miniature loader suitable for use in discardable
; startup code for doing jobs like loading the BDOS. It understands just enough
; of the CP/M filesystem to be able to find a file by name and read it,
; provided that:
;
;   - the file occupies exactly one extent
;   - it contains no empty blocks
;   - it's on drive 0
;   - the file exists (the system hangs if it doesn't!)
;
; To use, set Y to the page number of the destination address, and XA to a
; 11-byte expanded filename.

zproc loadfile
    sta filename+0
    stx filename+1

    sty destination_addr+1
    lda #0
    sta destination_addr+0

    ; Select the drive.

    ; A is zero
    jsr bios_SELDSK
    sta ptr1+0
    stx ptr1+1

    ; Get the DPB address (which is the bit we actually want).

    ldy #DPH_DPB
    lda (ptr1), y
    pha
    iny
    lda (ptr1), y
    sta ptr1+1
    pla
    sta ptr1+0              ; ptr1 -> DPB

    ; Fetch the data we want.

    ldy #DPB_BSH
    lda (ptr1), y
    sta block_shift
    ldy #DPB_OFF
    lda (ptr1), y
    sta reserved_sectors+0
    sta current_sector+0
    iny
    lda (ptr1), y
    sta reserved_sectors+1
    sta current_sector+1
    ldy #DPB_DSM+1
    lda (ptr1), y
    sta large_disk

    lda #0
    sta current_sector+2

    ; Start scanning for the file.

    lda #<directory_buffer
    ldx #>directory_buffer
    jsr bios_SETDMA

    ; Scan the directory for the filename.

    zloop
        zloop
            jsr readsector
        zuntil_cc

        lda #0x01
        zrepeat
            pha
            jsr checkfilename
            pla
            bcc found

            clc
            adc #0x20
            cmp #0x81
        zuntil_eq

        jsr gotonextsector
    zendloop
found:

    ; We have the dirent in the directory buffer, with the offset to the
    ; filename in A. Adjust to point at the blocks.

    clc
    adc #0x0f
    sta directory_offset

    ; Start reading blocks.

    zrepeat
        ldx directory_offset
        ldy #0

        lda directory_buffer, x
        sta current_sector+0
        inx

        sty current_sector+1
        lda large_disk
        zif_ne
            ; This is a large disk; it's using two-byte block numbers.

            lda directory_buffer, x
            sta current_sector+1
            inx
        zendif

        sty current_sector+3
        stx directory_offset

        ; Check for EOF.

        lda current_sector+0
        ora current_sector+1
        zbreakif_eq

        ; Convert block number to sector number.

        ldy block_shift
        zrepeat
            asl current_sector+0
            rol current_sector+1
            rol current_sector+2
            dey
        zuntil_eq

        ; Remember to add on the number of reserved sectors.

        clc
        lda current_sector+0
        adc reserved_sectors+0
        sta current_sector+0
        lda current_sector+1
        adc reserved_sectors+1
        sta current_sector+1
        zif_cs
            inc current_sector+2
        zendif

        ; Calculate the block size.

        ldy block_shift
        lda #1
        zrepeat
            asl a
            dey
        zuntil_eq
        sta sector_count

        ; Read the block.

        zrepeat
            ; Read this sector.

            lda destination_addr+0
            ldx destination_addr+1
            jsr bios_SETDMA
            zrepeat
                jsr readsector
            zuntil_cc

            ; Advance to the next sector.

            lda destination_addr+0
            eor #0x80
            sta destination_addr+0
            zif_eq
                inc destination_addr+1
            zendif

            jsr gotonextsector
            dec sector_count
        zuntil_eq

        ldx directory_offset
        cpx #16
    zuntil_eq

    ; We're finished!

    rts
zendproc

; On entry, A is the offset of the filename in the directory.

zproc checkfilename,,local
    tax
    ldy #0
    zrepeat
        lda directory_buffer, x
        and #0x7f
        cmp (filename), y
        zif_ne
            sec
            rts
        zendif

        iny
        inx
        cpy #11
    zuntil_eq
    clc
    rts
zendproc

zproc gotonextsector,,local
    inc current_sector+0
    zif_eq
        inc current_sector+1
        zif_eq
            inc current_sector+2
        zendif
    zendif
    rts
zendproc

zproc readsector,,local
    lda #<current_sector
    ldx #>current_sector
    jsr bios_SETSEC
    jmp bios_READ
zendproc

.section .loaderzp, "zax", @nobits

filename:         .fill 2 ; filename pointer
block_shift:      .fill 1 ; block shift
reserved_sectors: .fill 2 ; offset to start of filesystem
current_sector:   .fill 3 ; current sector
destination_addr: .fill 2 ; where we're currently writing
directory_offset: .fill 1 ; offset into directory buffer
sector_count:     .fill 1 ; number of sectors left in current block
large_disk:       .fill 1 ; non-zero if this disk uses two-byte block numbers

; vim: sw=4 ts=4 et ft=asm

