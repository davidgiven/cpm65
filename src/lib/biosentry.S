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
    jmptablo entry_CONST
    jmptablo entry_CONIN
    jmptablo entry_CONOUT
    jmptablo entry_SELDSK
    jmptablo entry_SETSEC
    jmptablo entry_SETDMA
    jmptablo entry_READ
    jmptablo entry_WRITE
    jmptablo entry_RELOCATE
    jmptablo entry_GETTPA
    jmptablo entry_SETTPA
    jmptablo entry_GETZP
    jmptablo entry_SETZP
    jmptablo entry_SETBANK
    jmptablo entry_ADDDRV
    jmptablo entry_FINDDRV
biostable_hi:
    jmptabhi entry_CONST
    jmptabhi entry_CONIN
    jmptabhi entry_CONOUT
    jmptabhi entry_SELDSK
    jmptabhi entry_SETSEC
    jmptabhi entry_SETDMA
    jmptabhi entry_READ
    jmptabhi entry_WRITE
    jmptabhi entry_RELOCATE
    jmptabhi entry_GETTPA
    jmptabhi entry_SETTPA
    jmptabhi entry_GETZP
    jmptabhi entry_SETZP
    jmptabhi entry_SETBANK
    jmptabhi entry_ADDDRV
    jmptabhi entry_FINDDRV
zendproc

zproc entry_ADDDRV
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

zproc entry_FINDDRV
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
    jsr entry_FINDDRV
    sta TTY+1
    stx TTY+2
    rts
zendproc

; TTY routine implementations which delegate to a driver.

zproc entry_CONST
    ldy #TTY_CONST
    jmp TTY
zendproc

zproc entry_CONIN
    ldy #TTY_CONIN
    jmp TTY
zendproc

zproc entry_CONOUT
    ldy #TTY_CONOUT
zendproc
    ; fall through
zproc TTY
    jmp 0xffff
zendproc
