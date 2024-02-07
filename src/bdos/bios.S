; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65.inc"
#include "zif.inc"
#include "bdos.inc"

; Calls the BIOS entrypoint.

zproc callbios
.global bios
bios = callbios + 1
    jmp 0
zendproc

zproc bios_NEWLINE
    lda #13
    jsr bios_CONOUT
    lda #10
zendproc
    ; fall through
zproc bios_CONOUT
    ldy #BIOS_CONOUT
    jmp callbios
zendproc

zproc bios_CONIN
    ldy #BIOS_CONIN
    jmp callbios
zendproc

zproc bios_CONST
    ldy #BIOS_CONST
    jmp callbios
zendproc

zproc bios_GETTPA
    ldy #BIOS_GETTPA
    jmp callbios
zendproc

zproc bios_GETZP
    ldy #BIOS_GETZP
    jmp callbios
zendproc

zproc bios_SETDMA
    ldy #BIOS_SETDMA
    jmp callbios
zendproc

