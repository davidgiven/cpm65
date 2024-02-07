; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"

.global drvtop

.zeropage ptr
.zeropage ptr1

; BIOS entry point. Parameter is in XA, function in Y.
zproc biosentry
    jmpdispatch biostable_lo, biostable_hi

biostable_lo:
    jmptablo bios_CONST
    jmptablo bios_CONIN
    jmptablo bios_CONOUT
    jmptablo bios_SELDSK
    jmptablo bios_SETSEC
    jmptablo bios_SETDMA
    jmptablo bios_READ
    jmptablo bios_WRITE
    jmptablo bios_RELOCATE
    jmptablo bios_GETTPA
    jmptablo bios_SETTPA
    jmptablo bios_GETZP
    jmptablo bios_SETZP
    jmptablo bios_SETBANK
    jmptablo bios_ADDDRV
    jmptablo bios_FINDDRV
biostable_hi:
    jmptabhi bios_CONST
    jmptabhi bios_CONIN
    jmptabhi bios_CONOUT
    jmptabhi bios_SELDSK
    jmptabhi bios_SETSEC
    jmptabhi bios_SETDMA
    jmptabhi bios_READ
    jmptabhi bios_WRITE
    jmptabhi bios_RELOCATE
    jmptabhi bios_GETTPA
    jmptabhi bios_SETTPA
    jmptabhi bios_GETZP
    jmptabhi bios_SETZP
    jmptabhi bios_SETBANK
    jmptabhi bios_ADDDRV
    jmptabhi bios_FINDDRV
zendproc

zproc bios_ADDDRV
    sta ptr+0           ; save new driver address
    stx ptr+1

    ldy #DRVSTRUCT_NEXT
    lda drvtop+0        ; get old driver address
    sta (ptr), y
    iny
    lda drvtop+1
    sta (ptr), y

    ldy ptr+0           ; update address
    sty drvtop+0
    ldy ptr+1
    sty drvtop+1

    pha
    txa
    pha
    jsr initdrivers
    pla
    tax
    pla
    rts
zendproc

zproc bios_FINDDRV
    sta ptr1+0
    stx ptr1+1

    ora ptr1+1
    zif_eq
        ; input ID is 0; return first driver structure

        lda drvtop+0
        ldx drvtop+1
        clc
        rts
    zendif

    lda drvtop+0
    sta ptr+0
    lda drvtop+1
    sta ptr+1

    zloop
        ; Stop if no more drivers.

        lda ptr+0
        ora ptr+1
        zif_eq
            sec
            rts
        zendif

        ; Check this driver's ID.

        ldy #DRVSTRUCT_ID
        lda (ptr), y
        cmp ptr1+0
        zif_eq
            iny
            lda (ptr), y
            cmp ptr1+1
            zif_eq
                ; Found a matching driver, so return its strategy routine.

                iny
                iny
                lda (ptr), y
                tax
                dey
                lda (ptr), y
                clc
                rts
            zendif
        zendif

        ; This driver doesn't match, so continue on down the list.

        ldy #DRVSTRUCT_NEXT
        lda (ptr), y
        tax
        iny
        lda (ptr), y
        sta ptr+1
        stx ptr+0
    zendloop
zendproc

; Recache driver pointers.

zproc initdrivers
    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    jsr bios_FINDDRV
    sta TTY+1
    stx TTY+2
    rts
zendproc

; TTY routine implementations which delegate to a driver.

zproc bios_CONST
    ldy #TTY_CONST
    jmp TTY
zendproc

zproc bios_CONIN
    ldy #TTY_CONIN
    jmp TTY
zendproc

zproc bios_CONOUT
    ldy #TTY_CONOUT
zendproc
    ; fall through
zproc TTY
    jmp 0xffff
zendproc
