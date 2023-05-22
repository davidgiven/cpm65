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
#include "jumptables.inc"

ZEROPAGE

.global ptr
.global ptr1

ptr = FMSZPG
ptr1 = FMSZPG+2

save_x = FMSZPG+4
save_y = FMSZPG+5

; 1 byte of FMSZPG left, and PTEMP

SCREEN_WIDTH = 40
SCREEN_HEIGHT = 24

cursorx = COLCRS
cursory = ROWCRS

    .text

; Boot code and initialization is ran only once. Eventually it is overwritten
; by the directory buffer/

.global _start
_start:

    ; Boot sector

    .byte 0
#ifdef ATARI_HD
    .byte 12
#else
    .byte 12
#endif
    .word $0500
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

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy #>__USERTPA_START__
    jsr loadfile

    ; Relocate it.

    lda #>__USERTPA_START__
    ldx #__USERZEROPAGE_START__
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

.global directory_buffer
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

bdos_filename:
    .ascii "BDOS    SYS"

charin       = overwrite_after_display_stretch
charout      = overwrite_after_display_stretch
drive_number = overwrite_after_display_stretch + 1
sector_num   = overwrite_after_display_stretch + 2 ; (and +3, and +4, full)

dma          = overwrite_after_banner   ; (and +1

; --- BIOS entrypoints ------------------------------------------------------

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, drv_SCREEN

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    jmpdispatch jmptable_lo, jmptable_hi

jmptable_lo:
    jmptablo tty_const
    jmptablo tty_conin
    jmptablo tty_conout
jmptable_hi:
    jmptabhi tty_const
    jmptabhi tty_conin
    jmptabhi tty_conout
zendproc

; --- SCREEN driver ---------------------------------------------------------

defdriver SCREEN, DRVID_SCREEN, drvstrat_SCREEN, 0

; SCREEN driver strategy routine.
; Y=SCREEN opcode.
zproc drvstrat_SCREEN
    jmpdispatch screen_jmptable_lo, screen_jmptable_hi

screen_jmptable_lo:
    jmptablo screen_version
    jmptablo screen_getsize
    jmptablo screen_clear
    jmptablo screen_setcursor
    jmptablo screen_getcursor
    jmptablo screen_putchar
    jmptablo screen_putstring
    jmptablo screen_getchar
    jmptablo fail
    jmptablo screen_scrollup
    jmptablo screen_scrolldown
    jmptablo screen_cleartoeol
    jmptablo fail
screen_jmptable_hi:
    jmptabhi screen_version
    jmptabhi screen_getsize
    jmptabhi screen_clear
    jmptabhi screen_setcursor
    jmptabhi screen_getcursor
    jmptabhi screen_putchar
    jmptabhi screen_putstring
    jmptabhi screen_getchar
    jmptabhi fail
    jmptabhi screen_scrollup
    jmptabhi screen_scrolldown
    jmptabhi screen_cleartoeol
    jmptabhi fail
zendproc

zproc fail
    sec
    rts
zendproc

zproc screen_version
    lda #0
    rts
zendproc

zproc screen_getsize
    lda #SCREEN_WIDTH-1
    ldx #SCREEN_HEIGHT-1
    rts
zendproc

zproc screen_clear
    lda #0
    zrepeat
        pha
        jsr calculate_line_address

        ldy #SCREEN_WIDTH-1
        lda #0                      ; screen memory space
        zrepeat
            sta (ptr), y
            dey
        zuntil_mi

        pla
        clc
        adc #1
        cmp #SCREEN_HEIGHT
    zuntil_eq

    ; SCREEN doesn't specify where the cursor ends up, but this code is used by
    ; TTY and homing the cursor here simplifies things.

    lda #0
    sta cursorx
    sta cursory
    jmp show_cursor 
zendproc

zproc screen_setcursor
    pha
    jsr hide_cursor
    pla
    sta cursorx
    stx cursory
    jmp show_cursor
zendproc

zproc screen_getcursor
    lda cursorx
    ldx cursory
    rts
zendproc

zproc screen_getchar
    jsr tty_conin
    clc
    rts
zendproc

zproc screen_putchar
    pha
    jsr calculate_cursor_address
    pla
    jsr convert_ascii_to_screencode
    sta (ptr), y

    lda cursorx
    cmp #SCREEN_WIDTH-1
    zif_ne
        inc cursorx
    zendif

    rts
zendproc

zproc screen_putstring
    sta 1f+0
    stx 1f+1

    jsr calculate_cursor_address
    ldx #0
    zloop
    1:
        lda 0xffff, x
        zbreakif_eq

        jsr convert_ascii_to_screencode
        sta (ptr), y
        iny
        inx
    zendloop
    rts
zendproc

zproc screen_scrollup
    ldx #0              ; current line
    zrepeat
        txa
        jsr calculate_line_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer
        inx
        txa
        jsr calculate_line_address ; ptr is source pointer

        ldy #SCREEN_WIDTH-1
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #SCREEN_HEIGHT-1
    zuntil_eq

    ldy #SCREEN_WIDTH-1
    lda #0                  ; screen memory space
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc screen_scrolldown
    ldx #39             ; current line
    zrepeat
        txa
        jsr calculate_line_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        dex
        txa
        jsr calculate_line_address ; ptr is source pointer

        ldy #SCREEN_WIDTH-1
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #0
    zuntil_eq

    ldy #SCREEN_WIDTH-1
    lda #' '
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc screen_cleartoeol
; cursor is overwritten
    jsr calculate_cursor_address

    lda #0                          ; screen memory space
    zrepeat
        sta (ptr), y
        iny
        cpy #SCREEN_WIDTH
    zuntil_eq

    jmp show_cursor
zendproc

; --- TTY DRIVER ------------------------------------------------------------

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
        lda #127            ; DEL not BS
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
    pha
    jsr hide_cursor
    pla
    cmp #13
    zif_eq
        lda #0
        sta cursorx
        jmp show_cursor
    zendif
    cmp #127
    zif_eq
        dec cursorx
        zif_mi
            lda #SCREEN_WIDTH-1
            sta cursorx

            dec cursory
            zif_mi
                lda #0
                sta cursory
                jsr screen_scrolldown
            zendif
        zendif
        jsr calculate_cursor_address
        lda #$80            ; screen memory inverse space saves show_cursor
        sta (ptr), y
        rts
    zendif
    cmp #10
    beq write_nl

    tax
    lda cursorx
    pha
    txa
    jsr screen_putchar

    pla
    cmp #SCREEN_WIDTH-1
    beq write_nl

    jmp show_cursor
zendproc

zproc write_nl
    lda #0
    sta cursorx

    inc cursory
    lda cursory
    cmp #SCREEN_HEIGHT
    zif_eq
        dec cursory
        jmp screen_scrollup
    zendif
    jmp show_cursor
zendproc

; Preserves X and Y.
zproc convert_ascii_to_screencode
    cmp #32
    zif_cc
        clc
        adc #64
        rts
    zendif
    cmp #96
    zif_cc
        sec
        sbc #32
        rts
    zendif
    rts
zendproc

; Sets (ptr), y to the location of the cursor.
zproc calculate_cursor_address
    ldy cursorx
    lda cursory
    ; fall through
zendproc
; Sets ptr to the address of screen line A.
zproc calculate_line_address
    ; x*40 = x*8 + x*32.

    ; We have 24 lines. As 24*8 will fit in a byte, we can do this easily.

    asl a               ; a = y*2
    asl a               ; a = y*4
    asl a               ; a = y*8
    sta ptr+0           ; store y*8

    ; Anything more than this needs to be 16-bit arithmetic.

    asl a               ; = y*16
    rol ptr+1

    asl a               ; = y*13
    rol ptr+1

    ; Add.

    clc
    adc ptr+0
    sta ptr+0
    zif_cs
        inc ptr+1
    zendif

    lda ptr+0
    clc
    adc SAVMSC
    sta ptr+0
    lda ptr+1
    and #3
    adc SAVMSC+1
    sta ptr+1

    rts

zproc hide_cursor
    jsr calculate_cursor_address
    lda (ptr),y
    and #$7f
    sta (ptr),y
    rts
zendproc

zproc show_cursor
    jsr calculate_cursor_address
    lda (ptr),y
    ora #$80
    sta (ptr),y
    rts
zendproc

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
define_drive dph, 8190, 2048, 128, 18
#else
define_drive dph, 720, 1024, 64, 18
#endif

NOINIT

; Nothing left for .bss

; vim: filetype=asm sw=4 ts=4 et

