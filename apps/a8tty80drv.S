; -------------------------------------------------------------------------
;
; 80 columns TTY/SCREEN driver for the Atari 400/800 and XL/XE
;
; Copyright © 2023 Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; -------------------------------------------------------------------------

#include "zif.inc"

; force to include the clang version and not the asm.com version
#include "include/cpm65.inc"

#include "atari800.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

drv_zp_begin:

ptr:    .fill 2

drv_zp_end:

; -------------------------------------------------------------------------

zproc main
    jmp init
zendproc

; -------------------------------------------------------------------------

drv_screen80:
    .word DRVID_SCREEN
    .word drv_screen80_strat
    .word 0
    .ascii "SCREEN80"
    .byte 0

zproc drv_screen80_strat
    jmpdispatch drv_screen80_jump_lo, drv_screen80_jump_hi

drv_screen80_jump_lo:
    jmptablo screen80_version
    jmptablo screen80_getsize
    jmptablo screen80_clear
    jmptablo screen80_setcursor
    jmptablo screen80_getcursor
    jmptablo screen80_putchar
    jmptablo screen80_putstring
    jmptablo screen80_getchar
    jmptablo fail                   ; show cursor
    jmptablo screen80_scrollup
    jmptablo screen80_scrolldown
    jmptablo screen80_cleartoeol
    jmptablo fail                   ; set style

drv_screen80_jump_hi:
    jmptabhi screen80_version
    jmptabhi screen80_getsize
    jmptabhi screen80_clear
    jmptabhi screen80_setcursor
    jmptabhi screen80_getcursor
    jmptabhi screen80_putchar
    jmptabhi screen80_putstring
    jmptabhi screen80_getchar
    jmptabhi fail
    jmptabhi screen80_scrollup
    jmptabhi screen80_scrolldown
    jmptabhi screen80_cleartoeol
    jmptabhi fail
zendproc

zproc fail
    sec
    rts
zendproc

; -------------------------------------------------------------------------

drv_tty80:
    .word DRVID_TTY
    .word drv_tty80_strat
    .word 0
    .ascii "TTY80"
    .byte 0

zproc drv_tty80_strat
    jmpdispatch drv_tty80_jump_lo, drv_tty80_jump_hi

drv_tty80_jump_lo:
    jmptablo tty80_const
    jmptablo tty80_conin
    jmptablo tty80_conout

drv_tty80_jump_hi:
    jmptabhi tty80_const
    jmptabhi tty80_conin
    jmptabhi tty80_conout

zendproc

; -------------------------------------------------------------------------

zproc init
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

; find current drivers which we reuse for keyboard input

    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta next_screen
    stx next_screen+1

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta next_tty
    stx next_tty+1

; register new drivers

    lda #<drv_screen80
    ldx #>drv_screen80
    ldy #BIOS_ADDDRV
    jsr BIOS

    lda #<drv_tty80
    ldx #>drv_tty80
    ldy #BIOS_ADDDRV
    jsr BIOS

; claim memory

    ldy #BIOS_GETTPA
    jsr BIOS
; reserve 2 pages for now, later calculate total new screen memory and code
    clc
    adc #2
    ldy #BIOS_SETTPA
    jsr BIOS

    ldy #BIOS_GETZP
    jsr BIOS
    clc
    adc #drv_zp_end-drv_zp_begin
    ldy #BIOS_SETZP
    jsr BIOS

    lda #<banner
    ldx #>banner
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    rts
zendproc

; -------------------------------------------------------------------------

zproc screen80_version
    jmp (next_screen)
zendproc
zproc screen80_getsize
    jmp (next_screen)
zendproc
zproc screen80_clear
    jmp (next_screen)
zendproc
zproc screen80_setcursor
    jmp (next_screen)
zendproc
zproc screen80_getcursor
    jmp (next_screen)
zendproc
zproc screen80_putchar
    jmp (next_screen)
zendproc
zproc screen80_putstring
    jmp (next_screen)
zendproc
zproc screen80_getchar
    jmp (next_screen)
zendproc
zproc screen80_scrollup
    jmp (next_screen)
zendproc
zproc screen80_scrolldown
    jmp (next_screen)
zendproc
zproc screen80_cleartoeol
    jmp (next_screen)
zendproc

; -------------------------------------------------------------------------

zproc tty80_const
    jmp (next_tty)
zendproc
zproc tty80_conin
    jmp (next_tty)
zendproc
zproc tty80_conout
    jmp (next_tty)
zendproc

; -------------------------------------------------------------------------

zproc BIOS
    jmp $1234
zendproc

; -------------------------------------------------------------------------

    .data

banner:
    .ascii "tty80/screen80 driver loaded."
    .byte 13, 10, 0

    .bss

next_tty:
    .word 0
next_screen:
    .word 0

; -------------------------------------------------------------------------

