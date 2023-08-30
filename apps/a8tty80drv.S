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

;    defdriver tty80, DRVID_TTY, drv_tty80_strat, 0

drv_tty80:
    .word DRVID_TTY
    .word drv_tty80_strat
    .word 0
    .ascii "TTY80"
    .byte 0

zproc drv_tty80_strat
;    jmp _next_tty-1
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

zproc tty80_const
    nop
zendproc
zproc tty80_conin
    nop
zendproc
zproc tty80_conout
_next_tty = . + 1
    jmp $1234
zendproc

; -------------------------------------------------------------------------

zproc init
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta _bios
    stx _bios+1

; find current drivers which we reuse for keyboard input

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta _next_tty
    stx _next_tty+1

; register new drivers

    lda #<drv_tty80
    ldx #>drv_tty80
    ldy #BIOS_ADDDRV
    jsr BIOS

; reserve memory

    ldy #BIOS_GETTPA
    jsr BIOS
    clc
    adc #1              ; reserve 1 page
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

zproc BIOS
_bios = . + 1
    jmp $1234
zendproc

; -------------------------------------------------------------------------

    .data

banner:
    .ascii "tty80/screen80 driver loaded."
    .byte 13, 10, 0

; -------------------------------------------------------------------------

