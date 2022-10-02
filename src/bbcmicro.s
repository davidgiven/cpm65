; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

    .include "zif.inc"
    .include "mos.inc"
    .include "cpm65.inc"

    .import __ZEROPAGE_LOAD__
    .import __ZEROPAGE_SIZE__

    .zeropage

ptr: .word 0

    .code

; --- Initialisation code ---------------------------------------------------

; Called once on startup and then never again.
; TODO: figure out a way to discard this after startup.

    ; Print banner.

    ldy #banner_end - banner
:
    lda banner - 1, y
    jsr OSWRCH
    dey
    bne :-

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
    lda #4-1            ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump

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
    .byte "BDOS", 13

banner:
    .byte 13, 10, "56-M/PC" ; reversed!
banner_end:

cpmfs_filename:
    .byte "CPMFS", 13

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
    .lobytes entry_CONST
    .lobytes entry_CONIN
    .lobytes OSWRCH
    .lobytes entry_SELDSK
    .lobytes entry_SETSEC
    .lobytes entry_SETDMA
    .lobytes entry_READ
    .lobytes entry_WRITE
    .lobytes entry_RELOCATE
    .lobytes entry_GETTPA
    .lobytes entry_SETTPA
    .lobytes entry_GETZP
    .lobytes entry_SETZP
biostable_hi:
    .hibytes entry_CONST
    .hibytes entry_CONIN
    .hibytes OSWRCH
    .hibytes entry_SELDSK
    .hibytes entry_SETSEC
    .hibytes entry_SETDMA
    .hibytes entry_READ
    .hibytes entry_WRITE
    .hibytes entry_RELOCATE
    .hibytes entry_GETTPA
    .hibytes entry_SETTPA
    .hibytes entry_GETZP
    .hibytes entry_SETZP

; Blocks and waits for the next keypress; returns it in A.

.proc entry_CONIN
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
.endproc

.proc entry_CONST
    lda pending_key
    bne @yes
    lda #$81
    ldx #0
    ldy #0
    jsr OSBYTE
    bcs @no
    stx pending_key
@yes:
    lda #$ff
    rts
@no:
    lda #0
    rts
.endproc

; Sets the current DMA address.

entry_SETDMA:
    sta dma+0
    stx dma+1
    rts

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

.proc entry_SELDSK
    cmp #0
    zif_ne
        sec                 ; invalid drive
        rts
    zendif

    lda #<dph
    ldx #>dph
    clc
    rts
.endproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

.proc entry_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil_mi
    rts
.endproc

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

.include "relocate.inc" ; standard entry_RELOCATE

.proc init_control_block
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
.endproc

entry_GETTPA:
    lda mem_base
    ldx mem_end
    rts

entry_SETTPA:
    sta mem_base
    stx mem_end
    rts

entry_GETZP:
    lda zp_base
    ldx zp_end
    rts

entry_SETZP:
    sta zp_base
    stx zp_end
    rts

    .data
zp_base: .byte <(__ZEROPAGE_LOAD__ + __ZEROPAGE_SIZE__)
zp_end:  .byte $90

; DPH for drive 0 (our only drive)

dph: define_drive $600, 1024, 64, 0

    .bss
mem_base: .byte 0
mem_end:  .byte 0

filehandle:  .byte 0    ; file handle of disk image
pending_key: .byte 0    ; pending keypress from system
dma:         .word 0    ; current DMA
sector_num:  .res 3     ; current absolute sector number

directory_buffer: .res 128

osgbpb_block:           ; block used by entry_READ and entry_WRITE
    .res $0d
osgbpb_block_end:

; vim: filetype=asm sw=4 ts=4 et

