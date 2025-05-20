\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"
.include "drivers.inc"

.expand 1

.label entry
.label next

\ --- Resident part starts at the top of the file ---------------------------

zproc start
    jmp entry
zendproc

driver:
    .word DRVID_TTY
    .word strategy
    .word 0
    .byte "CapsTTY", 0

zproc strategy
    cpy #TTY_CONOUT
    zif eq
        cmp #'a'
        zif cs
            cmp #'z'+1
            zif cc
                and #0xdf
            zendif
        zendif
    zendif
    jmp (next)
zendproc

next: .word 0

\ --- Resident part stops here -------------------------------------------

zproc entry
    lda #<banner
    ldx #>banner
    ldy #BDOS_PRINTSTRING
    jsr BDOS

    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    \ Find the old TTY driver strategy routine and save it.

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    zif cc
        sta next+0
        stx next+1

        \ Register the new TTY driver.

        lda #<driver
        ldx #>driver
        ldy #BIOS_ADDDRV
        jsr BIOS
        zif cc

            \ Our driver uses no ZP, so we don't need to adjust that. But it does use
            \ TPA.

            ldy #BIOS_GETTPA
            jsr BIOS
            clc
            adc #1 \ Allocate one page. We should be using entry to calculate this, but
                   \ the assembler can't do that yet.
            ldy #BIOS_SETTPA
            jsr BIOS

            \ Finished --- don't even need to warm boot.

            rts
        zendif
    zendif

    lda #<failed
    ldx #>failed
    ldy #BDOS_PRINTSTRING
    jmp BDOS
    
banner:
    .byte "Everything is in capital letters now", 13, 10, 0
failed:
    .byte "Failed!", 13, 10, 0
BIOS:
    jmp 0

\ vim: sw=4 ts=4 et


