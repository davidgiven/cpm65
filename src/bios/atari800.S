; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; Atari 800 XL/XE Port Copyright © 2023 Ivo van Poorten

; Disk layout SS SD 40 tracks x 18 sectors = 720 sectors.
; or
; 455 tracks x 18 sectors = 8190 sectors (CP/M FS uses 8176)

; First three tracks are reserved for BIOS and BDOS so there is room to grow.
; Use Atari OS bootloader to load BDOS instead of requiring DOS.SYS, which
; is pretty big and useless afterwards as it has no ftell()/fseek()

#include "zif.inc"
#include "cpm65.inc"
#include "atari800.inc"

ZEROPAGE

.global ptr
save_y:
ptr: .word 0

    .text

.global _start
_start:

    ; Boot sector

    .byte 0
#ifdef ATARI_HD
    .byte 8 + 28  ; 8 + 28 (BIOS+BDOS) (BIOS must be multiple of 2, one page)
#else
    .byte 6 + 28  ; 6 + 28 (BIOS+BDOS) (BIOS must be multiple of 2, one page)
#endif
    .word $0700
    .word init      ; just use init and never return

init:
    lda MEMTOP+1
    sta mem_end

    lda #0
    sta LMARGN
    sta COLCRS      ; leftover cursor will be overwritten by banner
    sta COLCRS+1
    lda #$b0        ; green
    sta COLOR2      ; background
    lda #$0f        ; luma only
    sta COLOR1      ; foreground

    ; IOCB0 E: is already open

    ; Print banner.

    ldy #banner_end - banner
    zrepeat
        lda banner - 1, y
        sty save_y
        jsr entry_CONOUT
        ldy save_y
        dey
    zuntil_eq

    ; Open IOCB1 for K device (no direct OS call hack)

    ldx #1*16
    lda #4
    sta ICAX1,x
    lda #0
    sta ICAX2,x
    lda #COPEN
    sta ICCOM,x
    lda #<kdevice
    sta ICBAL,x
    lda #>kdevice
    sta ICBAH,x

    jsr CIOV

    ; Figure out the start and end of the TPA.
    ; mem_base, mem_end are already set correctly for where BDOS loads

    ; Load the BDOS image to mem_base
    ; BDOS is already loaded at mem_base by the Atari OS bootloader

    ; Relocate it.

    lda mem_base
    ldx zp_base
    jsr entry_RELOCATE

    ; Compute the entry address and jump.

    lda mem_base
    pha
    lda #COMHDR_ENTRY-1 ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump to BDOS
zendproc

banner: ; reversed!
    .byte 13
    .ascii "008 iratA eht rof 56-M/PC"
banner_end:

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
    .byte entry_CONOUT@mos16lo
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
    .byte entry_CONOUT@mos16hi
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
    ldx #1*16
    lda #CGBIN
    sta ICCOM,x
    lda #1
    sta ICBLL,x
    lda #0
    sta ICBLH,x
    lda #<charin
    sta ICBAL,x
    lda #>charin
    sta ICBAH,x

    jsr CIOV

    lda charin

    cmp #ATARI_EOL
    zif_eq
        lda #13
        rts
    zendif

    cmp #ATARI_BS
    zif_eq
        lda #8
        rts
    zendif

    cmp #ATARI_TAB
    zif_eq
        lda #9
;        rts    [[fallthrough]]
    zendif

    rts
zendproc

zproc entry_CONST
    lda #0
    clc
    rts
zendproc

; Output character in A

zproc entry_CONOUT

    cmp #TERM_LF
    zif_eq
        lda #ATARI_EOL
        bne conout
    zendif

    cmp #TERM_CR
    zif_eq
        lda #0
        sta COLCRS
        rts
    zendif

    cmp #TERM_BS
    zif_eq
        lda #ATARI_BS
        bne conout
    zendif

    cmp #TERM_TAB
    zif_eq
        lda #ATARI_TAB
        bne conout
    zendif

    cmp #TERM_DEL
    zif_eq
;        lda #ATARI_DEL
        lda #ATARI_BS       ; DEL=BS apparently
        bne conout
    zendif

    cmp #TERM_CLS
    zif_eq
        lda #ATARI_CLS
;        bne conout         ; fallthrough
    zendif

conout:
    sta charout

    ldx #0          ; IOCB number $00, $10, etc...
    lda #CPBIN
    sta ICCOM,x
    lda #1          ; length
    sta ICBLL,x
    lda #0
    sta ICBLH,x
    lda #<charout
    sta ICBAL,x
    lda #>charout
    sta ICBAH,x
    jmp CIOV
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

    sta drive_number

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

; BDOS looks at DPH to see how many sectors to skip.

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
    lda #$40        ; data direction receive
    sta DSTATS
    lda #SIO_READ_SECTOR
    bne do_SIO

entry_WRITE:
    lda #$80        ; data direction send
    sta DSTATS
    lda #SIO_WRITE_SECTOR

do_SIO:
    sta DCOMND
    lda #$31
    clc
    adc drive_number
    sta DDEVIC
    and #$0f
    sta DUNIT

    lda dma
    sta DBUFLO
    lda dma+1
    sta DBUFHI

    lda #128
    sta DBYTLO
    lda #0
    sta DBYTHI

    lda sector_num      ; Atari starts counting at sector 1
    clc
    adc #1
    sta DAUX1
    lda sector_num+1
    adc #0
    sta DAUX2

    jsr SIOV

    lda #0
    rts

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

mem_base: .byte __USERTPA_START__@mos16hi
mem_end:  .byte __USERTPA_END__@mos16hi

kdevice: .ascii "K"
         .byte 155

; DPH for drive 0 (our only drive)

; number of sectors, blocksize, direntries, reserved _sectors_

; 54 reserved sectors = 6912 bytes for BIOS and BDOS

#ifdef ATARI_HD
define_drive dph, 8190, 2048, 128, 54
#else
define_drive dph, 720, 1024, 64, 54
#endif

NOINIT

charin:
charout: .byte 0

drive_number: .byte 0

dma:        .word 0     ; current DMA
sector_num: .fill 3     ; current 24-bit sector number

directory_buffer: .fill 128

; vim: filetype=asm sw=4 ts=4 et

