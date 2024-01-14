; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65.inc"
#include "driver.inc"
#include "zif.inc"

zproc _call_screen, .text._call_screen
    jmp 0
zendproc

zproc screen_init, .text.screen_init
    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta _call_screen+1
    stx _call_screen+2
    lda #0
    ror a
    eor #0x80
    rts
zendproc

zproc screen_clear, .text.screen_clear
    ldy #SCREEN_CLEAR
    jmp _call_screen
zendproc

zproc _screen_getsize, .text.screen_getsize
    ldy #SCREEN_GETSIZE
    jmp _call_screen
zendproc

zproc _screen_setcursor, .text.screen_setcursor
    ldy #SCREEN_SETCURSOR
    jmp _call_screen
zendproc

zproc _screen_getcursor, .text.screen_getcursor
    ldy #SCREEN_GETCURSOR
    jmp _call_screen
zendproc

zproc screen_putchar, .text.screen_putchar
    ldy #SCREEN_PUTCHAR
    jmp _call_screen
zendproc

zproc screen_putstring, .text.screen_putstring
    ldy #SCREEN_PUTSTRING
    jmp _call_screen
zendproc

zproc screen_scrollup, .text.screen_scrollup
    ldy #SCREEN_SCROLLUP
    jmp _call_screen
zendproc

zproc screen_scrolldown, .text.screen_scrolldown
    ldy #SCREEN_SCROLLDOWN
    jmp _call_screen
zendproc

zproc screen_clear_to_eol, .text.screen_clear_to_eol
    ldy #SCREEN_CLEARTOEOL
    jmp _call_screen
zendproc

zproc screen_waitchar, .text.screen_waitchar
    zrepeat
        lda #0xff
        ldx #0x7f
        ldy #SCREEN_GETCHAR
        jsr _call_screen
    zuntil_cc
    rts
zendproc

zproc screen_setstyle, .text.screen_setstyle
    ldy #SCREEN_SETSTYLE
    jmp _call_screen
zendproc

zproc screen_showcursor, .text.screen_showcursor
    ldy #SCREEN_SHOWCURSOR
    jmp _call_screen
zendproc
