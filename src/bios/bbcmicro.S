; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "mos.inc"
#include "cpm65.inc"

ZEROPAGE

.global ptr
ptr: .word 0

; --- Initialisation code ---------------------------------------------------

; Called once on startup and then never again.
; TODO: figure out a way to discard this after startup.

zproc _start
    ; Print banner.

    ldy #banner_end - banner
    zrepeat
        lda banner - 1, y
        jsr OSWRCH
        dey
    zuntil_eq

    ; Figure out the start and end of the TPA.

    lda #$83
    jsr OSBYTE
    sty mem_base

    lda #$84
    ldy #0
    jsr OSBYTE
    cpy #$4
    zif_eq              ; Tube present?
        ldy #$f8        ; override mem_end
        lda #$ee
        sta zp_end      ; override zp_end
    zendif
    sty mem_end

    ; Load the BDOS image.

    lda mem_base
    sta bdos_osfile_block + 3
    lda #$ff
    ldx #<bdos_osfile_block
    ldy #>bdos_osfile_block
    jsr OSFILE

    ; Relocate it.

    lda mem_base
    ldx zp_base
    jsr entry_RELOCATE

    ; Close any existing files.

    lda #0
    tay
    jsr OSFIND

    ; Open the file system image file.

    lda #$c0            ; open file for r/w
    ldx #<cpmfs_filename
    ldy #>cpmfs_filename
    jsr OSFIND
    sta filehandle

    ; Compute the entry address and jump.

    lda mem_base
    pha
    lda #COMHDR_ENTRY-1 ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump
zendproc

bdos_osfile_block:
    .word bdos_filename ; filename
    .word 0             ; load address low
    .word 0             ; load address high
    .word 0             ; exec address low
    .word 0             ; exec address high
    .word 0             ; length low
    .word 0             ; length high
    .word 0             ; attrs low
    .word 0             ; attrs high
    
bdos_filename:
    .ascii "BDOS"
    .byte 13

banner: ; reversed!
    .byte 13, 10
    .ascii "56-M/PC"
banner_end:

cpmfs_filename:
    .ascii "CPMFS"
    .byte 13

; --- BIOS entrypoints ------------------------------------------------------

; BIOS entry point. Parameter is in XA, function in Y.
biosentry:
    pha
    lda biostable_lo, y
    sta ptr+0
    lda biostable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

biostable_lo:
    .byte entry_CONST@mos16lo
    .byte entry_CONIN@mos16lo
    .byte OSWRCH@mos16lo
    .byte entry_SELDSK@mos16lo
    .byte entry_SETSEC@mos16lo
    .byte entry_SETDMA@mos16lo
    .byte entry_READ@mos16lo
    .byte entry_WRITE@mos16lo
    .byte entry_RELOCATE@mos16lo
    .byte entry_GETTPA@mos16lo
    .byte entry_SETTPA@mos16lo
    .byte entry_GETZP@mos16lo
    .byte entry_SETZP@mos16lo
    .byte entry_SETBANK@mos16lo
biostable_hi:
    .byte entry_CONST@mos16hi
    .byte entry_CONIN@mos16hi
    .byte OSWRCH@mos16hi
    .byte entry_SELDSK@mos16hi
    .byte entry_SETSEC@mos16hi
    .byte entry_SETDMA@mos16hi
    .byte entry_READ@mos16hi
    .byte entry_WRITE@mos16hi
    .byte entry_RELOCATE@mos16hi
    .byte entry_GETTPA@mos16hi
    .byte entry_SETTPA@mos16hi
    .byte entry_GETZP@mos16hi
    .byte entry_SETZP@mos16hi
    .byte entry_SETBANK@mos16hi

; Blocks and waits for the next keypress; returns it in A.

zproc entry_CONIN
    lda pending_key
    zif_eq
        zrepeat
            lda #$81
            ldx #$ff
            ldy #$7f
            jsr OSBYTE
        zuntil_cc
        txa
        rts
    zendif

    ldx #0
    stx pending_key
    rts
zendproc

zproc entry_CONST
    lda pending_key
    zif_eq
        lda #$81
        ldx #0
        ldy #0
        jsr OSBYTE
        zif_cs
            lda #0
            rts
        zendif
        stx pending_key
    zendif
    lda #$ff
    rts
zendproc

; Sets the current DMA address.

zproc entry_SETDMA
    sta dma+0
    stx dma+1
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc entry_SELDSK
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

zproc entry_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil_mi
    rts
zendproc

entry_READ:
    jsr init_control_block
    lda #3              ; read bytes using pointer
    jmp do_gbpb

entry_WRITE:
    jsr init_control_block
    lda #1              ; write bytes using pointer
do_gbpb:
    ldx #<osgbpb_block
    ldy #>osgbpb_block
    jsr OSGBPB
    lda #0
    rol a
    rts

zproc init_control_block
    ldy #(osgbpb_block_end - osgbpb_block - 1)
    lda #0
    zrepeat
        sta osgbpb_block, y
        dey
    zuntil_mi

    lda filehandle
    sta osgbpb_block+0
    lda dma+0
    sta osgbpb_block+1
    lda dma+1
    sta osgbpb_block+2
    lda #128
    sta osgbpb_block+5

    ldy #2
    zrepeat
        lda sector_num+0, y
        sta osgbpb_block+10, y
        dey
    zuntil_mi

    clc
    ldx #3
    zrepeat
        ror osgbpb_block+9, x
        dex
    zuntil_mi
    
    rts
zendproc

zproc entry_GETTPA
    lda mem_base
    ldx mem_end
    rts
zendproc

zproc entry_SETTPA
    sta mem_base
    stx mem_end
    rts
zendproc

zproc entry_GETZP
    lda zp_base
    ldx zp_end
    rts
zendproc

zproc entry_SETZP
    sta zp_base
    stx zp_end
    rts
zendproc

zproc entry_SETBANK
    rts
zendproc

    .data
zp_base: .byte __USERZEROPAGE_START__
zp_end:  .byte __USERZEROPAGE_END__

; DPH for drive 0 (our only drive)

define_drive dph, $600, 1024, 64, 0

NOINIT

mem_base: .byte 0
mem_end:  .byte 0

filehandle:  .byte 0    ; file handle of disk image
pending_key: .byte 0    ; pending keypress from system
dma:         .word 0    ; current DMA
sector_num:  .fill 3    ; current absolute sector number

directory_buffer: .fill 128

osgbpb_block:           ; block used by entry_READ and entry_WRITE
    .fill $0d
osgbpb_block_end:

; vim: filetype=asm sw=4 ts=4 et

