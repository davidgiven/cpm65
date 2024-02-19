; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; 40/80 columns TTY/SCREEN driver for the Apple ][
; Copyright © 2024 Andreas Baumann
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "apple2e.inc"
#include "driver.inc"
#include "jumptables.inc"

; -------------------------------------------------------------------------

zproc main
    jmp init
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
    jmptablo screen_showcursor
    jmptablo screen_scrollup
    jmptablo screen_scrolldown
    jmptablo screen_cleartoeol
    jmptablo screen_setstyle

screen_jmptable_hi:
    jmptabhi screen_version
    jmptabhi screen_getsize
    jmptabhi screen_clear
    jmptabhi screen_setcursor
    jmptabhi screen_getcursor
    jmptabhi screen_putchar
    jmptabhi screen_putstring
    jmptabhi screen_getchar
    jmptabhi screen_showcursor
    jmptabhi screen_scrollup
    jmptabhi screen_scrolldown
    jmptabhi screen_cleartoeol
    jmptabhi screen_setstyle
zendproc

zproc fail
    sec
    rts
zendproc

; -------------------------------------------------------------------------

; INITIALIZE DRIVER

zproc init

; BDOS: where is the BIOS
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

; register new driver
    lda #<drv_SCREEN
    ldx #>drv_SCREEN
    ldy #BIOS_ADDDRV
    jsr BIOS
    
; claim memory for our driver (TODO: compute this)
    zif_cc
        ldy #BIOS_GETTPA
        jsr BIOS
        clc
        adc #4
        ldy #BIOS_SETTPA
        jsr BIOS

        ldy #BIOS_GETZP
        jsr BIOS
        clc
        adc #4
        ldy #BIOS_SETZP
        jsr BIOS
        
        zif_cc
; print that we are loaded
            lda #<banner
            ldx #>banner
            ldy #BDOS_WRITE_STRING
            jsr BDOS

; just returning works
            rts
        zendif
    zendif

; print we failed to load
    lda #<failed
    ldx #>failed
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    
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
    jmp clear_screen
zendproc

zproc screen_setcursor
    sta cursorx
    stx cursory
    rts
zendproc

zproc screen_getcursor
    lda cursorx
    ldx cursory
    rts
zendproc

zproc screen_getchar
    jsr cursor_on
    
    ; A,X contain the timeout, TODO: respect timeout
    
    zrepeat
        lda KBD_READ
    zuntil_mi
    bpl nokey
    sta KBD_STROBERESET
    and #0x7f
   
nokey:
    jsr cursor_off
    
    ; return character in A
    ; TODO: carry clear on keyboard event, carry set on timeout?
    clc
    rts
zendproc

zproc screen_showcursor
    sta cursorvisible
    rts
zendproc

zproc screen_putchar
    ;~ ; TODO: we have to check how the various machines do this,
    ;~ ; especially for lower-case characters
    ;~ ;sec
    ;~ ;sbc stylemask
    jmp conout
zendproc

zproc screen_putstring
    sta ptr1+0
    stx ptr1+1
    zrepeat
        ldy #0
        lda (ptr1), y
        zbreakif_eq
        jsr screen_putchar
        inc ptr1+0
        zif_eq
            inc ptr1+1
        zendif
    zuntil_eq
    rts
zendproc

zproc screen_scrollup
    jmp scroll_up
zendproc

zproc screen_scrolldown
    jmp scroll_down
zendproc

zproc screen_cleartoeol
    lda cursory
    jsr calculate_screen_address ; ptr is source pointer
    ldy cursorx
    lda #32|0x80
    zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
        sta SCREEN_PAGE2OFF
        sta (ptr), y
        sta SCREEN_PAGE2ON
#endif
        sta (ptr), y
        iny
        cpy #40
    zuntil_eq
    rts
zendproc

zproc setcolour
    ; colours, are you kidding? ;-)
    rts
zendproc

zproc screen_setstyle
    ; TODO: see "Using 6502 Assembly Language, appendix A-2"
    ; TODO: see how we handle inverse with lowercase in Apple IIe and clone case
    and #STYLE_REVERSE
    zif_eq
        lda #0x00
        sta cursorstylemask
    zelse
        lda #0x80
        sta cursorstylemask
    zendif
    rts
zendproc

zproc scroll_down
    ldx #22              ; current line
    zrepeat
        txa
        jsr calculate_screen_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        dex
        txa
        jsr calculate_screen_address ; ptr is source pointer

        ldy #39
        zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
            sta SCREEN_PAGE2OFF
            lda (ptr), y
            sta (ptr1), y
            sta SCREEN_PAGE2ON
#endif
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #0
    zuntil_eq

    ldy #39
    lda #32|0x80
    zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
        sta SCREEN_PAGE2OFF
        sta (ptr), y
        sta SCREEN_PAGE2ON
#endif
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc BIOS
    jmp $1234
zendproc

.data

banner:
    .ascii "Apple II screen driver loaded."
    .byte 13, 10, 0

failed:
    .ascii "Failed!"
    .byte 13, 10, 0

; Increase TPA bottom to here

reserve_tpa_end:
