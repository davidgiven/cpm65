; ----------------------------------------------------------------------------
;
; ADM-3A Terminal Driver
;
; Copyright © 2024 Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; -------------------------------------------------------------------------

#include "zif.inc"

; force clang version and not the asm.com version

#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

; -------------------------------------------------------------------------

zproc main
    jmp init
zendproc

; -------------------------------------------------------------------------

drv_adm3a:
    .word DRVID_TTY
    .word drv_adm3a_strat
    .word 0
    .ascii "ADM3ATTY"
    .byte 0

zproc drv_adm3a_strat
    cpy #TTY_CONOUT
    beq adm3a_conout
    jmp next_tty
zendproc

; -------------------------------------------------------------------------

zproc adm3a_conout
    pha

    ldy #SCREEN_GETCURSOR
    jsr SCREEN
    sta xpos
    stx ypos

    lda state
    cmp #0
    beq state0
    cmp #1
    beq state1
    cmp #2
    beq state2

state3:         ; read column, --> state 0
    pla
    sec
    sbc #$20
    sta xpos
    ldx #0
    stx state
    jmp LEAVE

state2:         ; read row, --> state 3
    pla
    sec
    sbc #$20
    sta ypos
    inc state
    jmp LEAVE

state1:         ; char after ESC, if '=' --> state 2, otherwise --> state 0
    pla
    cmp #'='
    zif_eq
        inc state
        rts
    zendif
    ; ignore other escape sequences
    dec state
    rts

state0:
    pla
    cmp #127    ; DEL/RUB (rubout)
    zif_eq
        inc rubout
        jmp do_rubout
    zendif
    cmp #32
    zif_cs      ; normal ASCII
        ldy #SCREEN_PUTCHAR
        jsr SCREEN

advance_position:
        inc xpos
        lda xpos
        cmp width
        zif_cs
            lda #0
            sta xpos
            inc ypos
            lda ypos
            cmp height
            zif_cs
                dec ypos
                ldy #SCREEN_SCROLLUP
                jsr SCREEN
            zendif
        zendif
        jmp LEAVE
    zendif

    cmp #$08
    zif_eq          ; ^H backspace, move cursor to the left
do_rubout:
        dec xpos
        lda xpos
        zif_mi
            ldx width
            dex
            stx xpos
            dec ypos
            lda ypos
            zif_mi
                inc ypos
                lda #0
                sta xpos
            zendif
        zendif
        lda xpos
        ldx ypos
        ldy #SCREEN_SETCURSOR
        jsr SCREEN
        lda rubout              ; check flag
        zif_ne
            lda #' '
            ldy #SCREEN_PUTCHAR
            jsr SCREEN
            dec rubout          ; unset flag
            jmp LEAVE
        zendif
        rts
    zendif

    cmp #$0a
    zif_eq          ; ^J line feed, move cursor down one line, optional scroll
        inc ypos
        lda ypos
        cmp height
        zif_cs
            dec ypos
            ldy #SCREEN_SCROLLUP
            jsr SCREEN
        zendif
        jmp LEAVE
    zendif

    cmp #$0b
    zif_eq          ; ^K upline, move cursor up one line, bump against top
        dec ypos
        zif_mi
            inc ypos
        zendif
        jmp LEAVE
    zendif

    cmp #$0c
    zif_eq          ; ^L forward space, move cursor to the right, opt. scroll
        jmp advance_position
    zendif

    cmp #$0d
    zif_eq          ; ^M carriage return, move cursor to begin of line
        lda #0
        sta xpos
        jmp LEAVE
    zendif

    cmp #$1a
    zif_eq          ; ^Z clear screen, (home cursor?)
        ldy #SCREEN_CLEAR
        jsr SCREEN
        jmp home_cursor
    zendif

    cmp #$1e
    zif_eq          ; ^^ home cursor
home_cursor:
        lda #0
        sta xpos
        sta ypos
        jmp LEAVE
    zendif

    cmp #$1b        ; ESC --> state 1
    zif_eq
        inc state
        rts
    zendif

    rts             ; ignore everything else
zendproc

zproc LEAVE
    lda xpos
    ldx ypos
    ldy #SCREEN_SETCURSOR
    jmp SCREEN
zendproc

; -------------------------------------------------------------------------

zproc init
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    ; find current driver which we reuse for keyboard input

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta next_tty+1
    stx next_tty+2

    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV
    jsr BIOS

    zif_cs
        lda #<noscreen
        ldx #>noscreen
        ldy #BDOS_WRITE_STRING
        jmp BDOS
    zendif

    sta SCREEN+1
    stx SCREEN+2

    ; register new driver

    lda #<drv_adm3a
    ldx #>drv_adm3a
    ldy #BIOS_ADDDRV
    jsr BIOS

    zif_cc
        ; claim memory

        ldy #BIOS_GETTPA
        jsr BIOS
        lda #>reserve_tpa_end
        ldy #BIOS_SETTPA
        jsr BIOS

        ; Set values we need

        ldy #SCREEN_GETSIZE
        jsr SCREEN
        sta lastcol     ; width counting from 0
        tay
        iny
        sty width       ; true width, counting from 1
        inx
        stx height      ; true height
        lda #0
        sta state
        sta rubout

        ; Say hello

        lda #<banner
        ldx #>banner
        ldy #BDOS_WRITE_STRING
        jmp BDOS
    zelse
        lda #<error
        ldx #>error
        ldy #BDOS_WRITE_STRING
        jmp BDOS
    zendif
zendproc

; -------------------------------------------------------------------------

; Trampolines

zproc BIOS
    jmp $1234
zendproc

zproc next_tty
    jmp $1234
zendproc

zproc SCREEN
    jmp $1234
zendproc

; -------------------------------------------------------------------------

    .data

banner:
    .ascii "ADM-3A TTY Loaded"
    .byte 13,10,0

noscreen:
    .ascii "No screen driver found"
    .byte 13,10,0

error:
    .ascii "Can't register new driver"
    .byte 13,10,0

; -------------------------------------------------------------------------

    .bss

width:      .fill 1
lastcol:    .fill 1
height:     .fill 1
xpos:       .fill 1
ypos:       .fill 1
state:      .fill 1
rubout:     .fill 1

    .align 0x0100

reserve_tpa_end:

; -------------------------------------------------------------------------
