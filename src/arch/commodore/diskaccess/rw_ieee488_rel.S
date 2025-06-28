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

zproc rw_init, .init
    ; Set up sector IO.

    lda #0xf2               ; OPEN channel 2 (for use with sector I/O)
    jsr ieee_listen

    ldx #0
    zrepeat
        lda filename, x
        jsr ieee_write
        inx
        cpx #filename_end - filename
    zuntil eq

    jmp ieee_unlisten

filename:
    .ascii "FILESYSTEM,L,"
    .byte 128
filename_end:

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

zlproc set_file_position
    lda #0x6f               ; REOPEN command channel
    jsr ieee_listen
    lda #'P'                ; command POSITION
    jsr ieee_write          
    lda #2+96               ; file number plus 96 (which is magic)
    jsr ieee_write
    lda sector_num+0
    jsr ieee_write
    lda sector_num+1
    jsr ieee_write
    lda #1                  ; offset --- 1 based
    jsr ieee_write
    jmp ieee_unlisten
zendproc

zproc bios_READ
    jsr set_file_position

    lda #0x62               ; REOPEN data channel
    jsr ieee_talk

    ldy #0
    clc
    zrepeat
        zif cc
            jsr ieee_getb
        zendif
        sta (dma), y
        zif cs
            lda #0
        zendif
        iny
    zuntil mi

    jsr ieee_untalk
    clc
    rts
zendproc

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc bios_WRITE
    jsr set_file_position

    lda #0x62               ; REOPEN data channel
    jsr ieee_listen

    ldy #0
    zrepeat
        lda (dma), y
        jsr ieee_write
        iny
    zuntil mi

    jsr ieee_unlisten

    ; DOS bug workaround.
    jsr set_file_position
    clc
    rts
zendproc

.bss

.global directory_buffer
directory_buffer: .fill 128

