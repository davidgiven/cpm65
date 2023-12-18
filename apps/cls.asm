\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"
.include "drivers.inc"

.expand 1

\ --- Resident part starts at the top of the file ---------------------------

.zproc start
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV
    jsr BIOS
    .zif cs
        rts
    .zendif
    sta SCREEN+1
    stx SCREEN+2

    ldy #SCREEN_CLEAR
    jmp SCREEN

BIOS:
    jmp 0
SCREEN:
    jmp 0

\ vim: sw=4 ts=4 et



