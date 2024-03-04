; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65.inc"
#include "zif.inc"
#include "bdos.inc"

; When called by the BIOS, it passes in the BIOS entrypoint address in XA.

zproc main
    sta bios+0
    stx bios+1

    ; Update memory region.

    lda #BANK_EXTRA
    jsr bios_SETBANK

    jsr bios_GETZP
    clc
    adc cpm_header + COMHDR_ZP_USAGE
    jsr bios_SETZP

    jsr bios_GETTPA
    clc
    adc cpm_header + COMHDR_TPA_USAGE
    jsr bios_SETTPA

    jmp bdos_core
zendproc

zproc bdos_GETBIOS
    lda bios+0
    sta param+0
    ldx bios+1
    stx param+1
    rts
zendproc

zproc bios_SETBANK
    ldy #BIOS_SETBANK
    jmp (bios)
zendproc

zproc bios_NEWLINE
    lda #13
    jsr bios_CONOUT
    lda #10
zendproc
    ; fall through
zproc bios_CONOUT
    ldy #BIOS_CONOUT
    jmp (bios)
zendproc

zproc bios_CONIN
    ldy #BIOS_CONIN
    jmp (bios)
zendproc

zproc bios_CONST
    ldy #BIOS_CONST
    jmp (bios)
zendproc

zproc bios_GETTPA
    ldy #BIOS_GETTPA
    jmp (bios)
zendproc

zproc bios_SETTPA
    ldy #BIOS_SETTPA
    jmp (bios)
zendproc

zproc bios_GETZP
    ldy #BIOS_GETZP
    jmp (bios)
zendproc

zproc bios_SETZP
    ldy #BIOS_SETZP
    jmp (bios)
zendproc

zproc bios_SETDMA
    ldy #BIOS_SETDMA
    jmp (bios)
zendproc

zproc bios_RELOCATE
    ldy #BIOS_RELOCATE
    jmp (bios)
zendproc

zproc bios_SETSEC
    ldy #BIOS_SETSEC
    jmp (bios)
zendproc

zproc bios_READ
    ldy #BIOS_READ
    jmp (bios)
zendproc

zproc bios_WRITE
    ldy #BIOS_WRITE
    jmp (bios)
zendproc

zproc bios_SELDSK
    ldy #BIOS_SELDSK
    jmp (bios)
zendproc

NOINIT

.global bios
bios: .fill 2

