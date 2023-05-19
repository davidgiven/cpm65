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
#include "driver.inc"

ZEROPAGE

.global ptr
.global ptr1
save_y:
ptr: .word 0
ptr1: .word 0

    .text

; Boot code and initialization is ran only once. Eventually it is overwritten
; by the directory buffer/

.global _start
_start:

    ; Boot sector

    .byte 0
#ifdef ATARI_HD
    .byte 8 + 28  ; 8 + 28 (BIOS+BDOS) (BIOS must be multiple of 2, one page)
#else
    .byte 8 + 28  ; 8 + 28 (BIOS+BDOS) (BIOS must be multiple of 2, one page)
#endif
    .word $0600
    .word init      ; just use init and never return

init:
    ldx MEMTOP+1
    stx mem_end
    stx ptr+1

    lda #0
    sta ptr
    sta LMARGN
    sta COLCRS      ; leftover cursor will be overwritten by banner
    sta COLCRS+1
    sta SHFLOK      ; start lower case
    sta COLOR2      ; background (black)
;    stx COLOR1      ; foreground a tad brighter (luma only)

    ; IOCB0 E: is already open

    ; ptr points to the last kilobyte of RAM before ROM (48+kB machines) or
    ; a gap (<48kB machines). This is _always_ true for all models.
    ; This block contains 32 empty bytes, 32 bytes of display list (DL),
    ; after which the screen memory starts.

    ; Adjust display list to have a scanline of space between text lines to
    ; avoid ascenders and descenders touching eachother when we load a
    ; proper 7x8 font from user space.

    sta SDMCTL      ; turn off screen gracefully while we adjust the DL
    sta DMACTL      ; hardware register, too, VBI might not occur during SIO
    sta SDLSTL      ; set DL pointer to MEMTOP+1
    stx SDLSTL+1
    tay

    stx dl_prologue+4
    lda #$40
    sta dl_prologue+3

    zrepeat
        lda dl_prologue,y
        sta (ptr),y
        iny
        cpy #5
    zuntil_eq

    ldx #23
    zrepeat
        lda #0      ; 1 black line
        sta (ptr),y
        iny
        lda #2      ; Mode 2
        sta (ptr),y
        iny
        dex
    zuntil_eq

    lda #$41
    sta (ptr),y
    txa
    iny
    sta (ptr),y
    iny
    lda MEMTOP+1
    sta (ptr),y

    lda #$22
    sta SDMCTL      ; turn on screen again

    ; Print banner.

    ldy #banner_end - banner
    zrepeat
        lda banner - 1, y
        sty save_y
        jsr tty_conout
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

    ; BIOS initialisation

    jsr initdrivers

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

; Everything above here is overwritten by the directory buffer, so make sure
; it's bigger than 0x80 bytes (currently: 0xa3).

directory_buffer = _start

; Below are 34 bytes that become available for overwrite during init. We use
; them for variables afterwards.

overwrite_after_display_stretch:        ; 5 bytes

dl_prologue:
    .byte $70, $30, $42, 0, 0

overwrite_after_banner:                 ; 27 bytes

banner: ; reversed!
    .byte 10,13
    .ascii "008 iratA eht rof 56-M/PC"
banner_end:

overwrite_after_keyboard_init:          ; 2 bytes

kdevice: .ascii "K"
         .byte 155

charin       = overwrite_after_display_stretch
charout      = overwrite_after_display_stretch
drive_number = overwrite_after_display_stretch + 1
sector_num   = overwrite_after_display_stretch + 2 ; (and +3, and +4, full)

dma          = overwrite_after_banner   ; (and +1

; --- BIOS entrypoints ------------------------------------------------------

; TTY DRIVER

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

zproc tty_const
    lda #$00
    clc
    rts
zendproc

; Output character in A

zproc tty_conout

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
        bne conout
    zendif

; The following two ATARI_ codes need to be escaped to actually print the 
; associated glyph. The glyph of 127 (which also needs escaping) is not
; available because it's already interceptede as ASCII DEL.

    ldx #esc_tab_last_idx
    zrepeat
        cmp esc_tab,x
        bne next
        pha
        lda #ATARI_ESC
        jsr conout          ; do not call tty_conout, because of endless loop
        pla
        bvc conout
next:
        dex
    zuntil_mi

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

esc_tab:
    .byte ATARI_ESC, ATARI_UP_ARROW, ATARI_DOWN_ARROW, ATARI_LEFT_ARROW
    .byte ATARI_RIGHT_ARROW, ATARI_CLS, ATARI_BS, ATARI_TAB

esc_tab_last_idx = . - esc_tab - 1

; ---------------------------------------------------------------------------

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

zproc entry_READ
    lda #$40        ; data direction receive
    sta DSTATS
    lda #SIO_READ_SECTOR
    bne do_SIO
zendproc            ; fallthrough

zproc entry_WRITE
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

; ---------------------------------------------------------------------------

    .data
zp_base: .byte __USERZEROPAGE_START__
zp_end:  .byte __USERZEROPAGE_END__

mem_base: .byte __USERTPA_START__@mos16hi
mem_end:  .byte __USERTPA_END__@mos16hi

; DPH for drive 0 (our only drive)

; number of sectors, blocksize, direntries, reserved _sectors_

; 54 reserved sectors = 6912 bytes for BIOS and BDOS

#ifdef ATARI_HD
define_drive dph, 8190, 2048, 128, 54
#else
define_drive dph, 720, 1024, 64, 54
#endif

NOINIT

; Nothing left for .bss

; vim: filetype=asm sw=4 ts=4 et

