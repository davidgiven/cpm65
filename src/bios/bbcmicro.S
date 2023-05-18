; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "mos.inc"
#include "cpm65.inc"
#include "driver.inc"

ZEROPAGE

.global ptr
.global ptr1
ptr: .word 0
ptr1: .word 0

; --- Initialisation code ---------------------------------------------------

; Called once on startup and then never again.
; Will eventually be overwritten by the directory buffer.

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

    ; BIOS initialisation.

    jsr initdrivers

    lda #0xca
    ldx #0x30
    ldy #0x00
    jsr OSBYTE          ; caps lock off

    lda #0xe5
    ldx #1
    jsr OSBYTE          ; disable ESCAPE handling

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

; Everything above here is overwritten by the directory buffer, so make sure
; it's bigger than 0x80 bytes (currently: 0x87).

; --- SCREEN driver ---------------------------------------------------------

defdriver SCREEN, DRVID_SCREEN, drvstrat_SCREEN, 0

; SCREEN driver strategy routine.
; Y=SCREEN opcode.
zproc drvstrat_SCREEN
    pha
    lda screen_jmptable_lo, y
    sta ptr+0
    lda screen_jmptable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

screen_jmptable_lo:
    .byte screen_version@mos16lo
    .byte screen_getsize@mos16lo
    .byte screen_clear@mos16lo
    .byte screen_setcursor@mos16lo
    .byte screen_getcursor@mos16lo
    .byte screen_putchar@mos16lo
    .byte screen_putstring@mos16lo
    .byte screen_getchar@mos16lo
    .byte fail@mos16lo
    .byte screen_scrollup@mos16lo
    .byte screen_scrolldown@mos16lo
    .byte screen_cleartoeol@mos16lo
    .byte OSNEWL@mos16lo
    .byte screen_backspace@mos16lo
screen_jmptable_hi:
    .byte screen_version@mos16hi
    .byte screen_getsize@mos16hi
    .byte screen_clear@mos16hi
    .byte screen_setcursor@mos16hi
    .byte screen_getcursor@mos16hi
    .byte screen_putchar@mos16hi
    .byte screen_putstring@mos16hi
    .byte screen_getchar@mos16hi
    .byte fail@mos16hi
    .byte screen_scrollup@mos16hi
    .byte screen_scrolldown@mos16hi
    .byte screen_cleartoeol@mos16hi
    .byte OSNEWL@mos16hi
    .byte screen_backspace@mos16hi
zendproc

zproc screen_version
    lda #0
    rts
zendproc

zproc screen_getsize
    lda #0xa0           ; read VDU variable
    ldx #0x0a           ; text window, right column
    jsr OSBYTE
    stx ptr+0
    ldx #0x09           ; text window, bottom row
    jsr OSBYTE
    lda ptr+0
    rts
zendproc

zproc screen_clear
    lda #12             ; clear screen
    jmp OSWRCH
zendproc

zproc screen_setcursor
    pha
    lda #31             ; set cursor
    jsr OSWRCH
    pla
    jsr OSWRCH
    txa
    jmp OSWRCH
zendproc

zproc screen_getcursor
    lda #0x86           ; get cursor
    jsr OSBYTE
    sty ptr+0
    txa
    ldx ptr+0
    rts
zendproc

zproc screen_getchar
    pha
    txa
    and #0x7f
    tay
    pla
    tax
    lda #0x81           ; read key with timeout
    jsr OSBYTE
    txa
    zif_cc
        cmp #127
        zif_eq
            lda #8
        zendif
        clc
    zendif
    rts
zendproc

zproc screen_putchar
    cmp #32
    zif_cc
        rts
    zendif
    cmp #127
    zif_cs
        rts
    zendif
    jmp OSWRCH
zendproc

zproc screen_putstring
    sta ptr+0
    stx ptr+1
    ldy #0
    zrepeat
        lda (ptr), y
        zbreakif_eq
        jsr OSWRCH
        iny
    zuntil_eq ; never 0
    clc
    rts
zendproc

zproc screen_scrollup
    jsr screen_getsize
    lda #0
    jsr screen_setcursor
    lda #10
    jmp OSWRCH
zendproc

zproc screen_scrolldown
    lda #30             ; home
    jsr OSWRCH
    lda #11             ; cursor up
    jmp OSWRCH
zendproc

zproc screen_cleartoeol
    lda #28             ; set up window
    jsr OSWRCH

    jsr screen_getcursor
    sta ptr+0
    stx ptr+1

    jsr OSWRCH          ; left
    txa
    jsr OSWRCH          ; top
    jsr screen_getsize
    jsr OSWRCH          ; right
    lda ptr+1
    jsr OSWRCH          ; bottom
    lda #12             ; clear window
    jsr OSWRCH
    lda #26             ; reset window
    jsr OSWRCH

    lda ptr+0
    ldx ptr+1
    jmp screen_setcursor
zendproc

zproc screen_backspace
    lda #127
    jmp OSWRCH
zendproc

; --- TTY driver ------------------------------------------------------------

defdriver TTY, DRVID_TTY, drvstrat_TTY, drv_SCREEN

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
    .byte OSWRCH@mos16lo
jmptable_hi:
    .byte tty_const@mos16hi
    .byte tty_conin@mos16hi
    .byte OSWRCH@mos16hi
zendproc

; Blocks and waits for the next keypress; returns it in A.

zproc tty_conin
    lda pending_key
    zif_eq
        zrepeat
            ldx #$7f
            lda #$ff
            jsr screen_getchar
        zuntil_cc
        rts
    zendif

    ldx #0
    stx pending_key
    rts
zendproc

zproc tty_const
    lda pending_key
    zif_eq
        ldx #0
        lda #0
        jsr screen_getchar
        zif_cs
            lda #0
            rts
        zendif
        sta pending_key
    zendif
    lda #$ff
    rts
zendproc

; --- Rest of the BIOS ---------------------------------------------------

zproc fail
    sec
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
    bne fail                ; invalid drive

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

zproc entry_READ
    jsr init_control_block
    lda #3              ; read bytes using pointer
    jmp do_gbpb
zendproc

zproc entry_WRITE
    jsr init_control_block
    lda #1              ; write bytes using pointer
do_gbpb:
    ldx #<osgbpb_block
    ldy #>osgbpb_block
    jsr OSGBPB
    lda #0
    rol a
    rts
zendproc

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

.global drvtop
drvtop: .word drv_TTY

; DPH for drive 0 (our only drive)

define_drive dph, 0x600, 1024, 64, 0

directory_buffer = _start

NOINIT

mem_base: .byte 0
mem_end:  .byte 0

filehandle:  .byte 0    ; file handle of disk image
pending_key: .byte 0    ; pending keypress from system
dma:         .word 0    ; current DMA
sector_num:  .fill 3    ; current absolute sector number

ZEROPAGE

osgbpb_block:           ; block used by entry_READ and entry_WRITE
    .fill $0d
osgbpb_block_end:

; vim: filetype=asm sw=4 ts=4 et

