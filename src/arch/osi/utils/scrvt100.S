; -------------------------------------------------------------------------
;
; VT100 Serial Screen Driver for Ohio Scientific serial systems
;
; Copyright © 2024 Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; -------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

drv_zp_begin:

ptr:            .fill 2
val:            .fill 1

drv_zp_end:

; -------------------------------------------------------------------------

zproc main
    jmp init
zendproc

; -------------------------------------------------------------------------

defdriver SCREEN, DRVID_SCREEN, drv_screen_strat, 0

zproc drv_screen_strat
    jmpdispatch drv_screen_jump_lo, drv_screen_jump_hi

drv_screen_jump_lo:
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

drv_screen_jump_hi:
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

; -------------------------------------------------------------------------

zproc init
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

; register new driver

    lda #<drv_SCREEN
    ldx #>drv_SCREEN
    ldy #BIOS_ADDDRV
    jsr BIOS

; claim memory

    ldy #BIOS_GETTPA
    jsr BIOS
    lda #>(reserve_tpa_end+256)
    ldy #BIOS_SETTPA
    jsr BIOS

    ldy #BIOS_GETZP
    jsr BIOS
    clc
    adc #drv_zp_end-drv_zp_begin
    ldy #BIOS_SETZP
    jsr BIOS

; display banner

    lda #<banner
    ldx #>banner
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    rts
zendproc

; -------------------------------------------------------------------------

zproc screen_version
    lda #0
    rts
zendproc

zproc screen_getsize
    lda #80-1
    ldx #24-1
    rts
zendproc

zproc screen_clear
    lda #<clshome
    ldx #>clshome
    jmp screen_putstring
zendproc

zproc screen_cleartoeol
    lda #<cleartoeol
    ldx #>cleartoeol
    jmp screen_putstring
zendproc

; entry: A=number [0-79], exit: Y=decades A=remainder, YA [1-80], X unaffected
zproc _convert_to_screen_decimal
    ldy #0
    clc
    adc #1
    zloop
        cmp #10
        zbreakif_cc
        sbc #10
        iny
    zendloop
    rts
zendproc

; A = xpos [0-width), X = ypos [0-height) --> ^[ [ ypos+1 ; xpos+1 f
zproc screen_setcursor
    jsr _convert_to_screen_decimal
    ora #$30
    sta setcursor+6
    tya
    ora #$30
    sta setcursor+5

    txa
    jsr _convert_to_screen_decimal
    ora #$30
    sta setcursor+3
    tya
    ora #$30
    sta setcursor+2

    ldx #0
    zrepeat
        lda setcursor,x
        jsr screen_putchar
        inx
        cpx #8
    zuntil_eq
    rts
zendproc

; entry: A=terminator character, exit: X=value-1
zproc _parse_decimal
    sta 1f+1
    lda #0
    sta val
    zloop
        jsr screen_getchar
1:
        cmp #';'
        zbreakif_eq
        pha

        ldy #9
        lda val
        clc
        zrepeat
            adc val
            dey
        zuntil_eq
        sta val

        pla
        sec
        sbc #$30
        clc
        adc val
        sta val
    zendloop
    ldx val
    dex
    rts
zendproc

; exit: A = xpos [0-width), X = ypos [0-height]
zproc screen_getcursor
    lda #<getcursor
    ldx #>getcursor
    jsr screen_putstring

; parse result: ^[ [ vertical ; horizontal R

    zloop
        jsr screen_getchar
        cmp #27
    zuntil_eq

    jsr screen_getchar
    cmp #'['
    zif_eq
        lda #';'
        jsr _parse_decimal
        stx 2f+1
        lda #'R'
        jsr _parse_decimal
        stx 1f+1
    zendif

1:
    lda #0
2:
    ldx #0
    rts
zendproc

zproc screen_setstyle
    cmp #STYLE_REVERSE
    zif_eq
        lda #'7'
    zelse
        lda #'0'
    zendif
    sta style+2
    lda #<style
    ldx #>style
    jmp screen_putstring
zendproc

zproc screen_putchar
    ldy #BIOS_CONOUT
    jmp BIOS
zendproc

zproc screen_putstring
    sta 1f+1
    stx 1f+2

    ldx #0
    zloop
    1:
        lda $1234,x
        zbreakif_eq

        jsr screen_putchar
        inx
    zendloop

    rts
zendproc

zproc screen_getchar
    ldy #BIOS_CONIN
    jsr BIOS
    clc
    rts
zendproc

zproc screen_scrollup
    lda #<scrollup
    ldx #>scrollup
    jmp screen_putstring
zendproc

zproc screen_scrolldown
    lda #<scrolldown
    ldx #>scrolldown
    jmp screen_putstring
zendproc

zproc screen_showcursor
    cmp #0
    zif_eq
        lda #<hidecursor
        ldx #>hidecursor
    zelse
        lda #<showcursor
        ldx #>showcursor
    zendif
    jmp screen_putstring
zendproc

; -------------------------------------------------------------------------

; Trampoline

zproc BIOS
    jmp $1234
zendproc

; -------------------------------------------------------------------------

; MISCELLANEOUS DATA

    .data

banner:
    .ascii "vt100 screen driver loaded."
    .byte 13, 10, 0

clshome:
    .byte 27
    .ascii "[2J"
    .byte 27
    .ascii "[H"
    .byte 0
cleartoeol:
    .byte 27
    .ascii "[K"
    .byte 0
style:
    .byte 27
    .ascii "[0m"
    .byte 0
scrollup:
    .byte 27
    .ascii "[24;1f"
    .byte 27, 'D', 0
scrolldown:
    .byte 27
    .ascii "[1;1f"
    .byte 27, 'M', 0
hidecursor:
    .byte 27
    .ascii "[?25l"                  ; le hidden (it's french)
    .byte 0
showcursor:
    .byte 27
    .ascii "[?25h"                  ; honestlyvisible
    .byte 0
setcursor:
    .byte 27
    .ascii "[vv;hhf"
    .byte 0
getcursor:
    .byte 27
    .ascii "[6n"
    .byte 0

; -------------------------------------------------------------------------

; UNINITIALIZED

    .bss

reserve_tpa_end:

; -------------------------------------------------------------------------
