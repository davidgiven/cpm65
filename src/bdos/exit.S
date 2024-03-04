; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "jumptables.inc"
#include "bdos.inc"

; Prints the message in XA and performs a warm boot.

zproc harderror
    jsr internal_WRITESTRING
zendproc
    ; fall through
zproc bdos_EXIT
    ldx #$ff                ; reset stack point
    txs

    jsr bios_NEWLINE
    jsr bdos_RESET

    ; Open the CCP.SYS file.

    lda #0
    sta ccp_fcb + FCB_EX
    sta ccp_fcb + FCB_S2
    sta ccp_fcb + FCB_CR
    lda #1
    sta ccp_fcb + FCB_DR

    lda #<ccp_fcb
    sta param+0
    lda #>ccp_fcb
    sta param+1
    jsr bdos_OPENFILE
    zif_cs
        lda #<1f
        ldx #>1f
        jsr internal_WRITESTRING
        jmp .
    1:
        .ascii "Couldn't open CCP"
        .byte 13, 10, 0
    zendif

    ; Read the first sector.

    jsr bios_GETTPA
    dex
    stx user_dma+1
    lda #0
    sta user_dma+0
    jsr internal_READSEQUENTIAL ; load one record

    ; Compute the load address.

    lda #BANK_EXTRA
    jsr bios_SETBANK

    jsr bios_GETZP          ; top of ZP in X
    txa
    sec
    ldy #COMHDR_ZP_USAGE
    sbc (user_dma), y
    pha

    jsr bios_GETTPA         ; top of TPA page number in X
    txa
    sec
    ldy #COMHDR_TPA_USAGE
    sbc (user_dma), y
    sta temp+1
    pha                     ; store load address for later
    lda #0
    sta temp+0

    ; Copy the first record into memory.
        
    ldy #127
    zrepeat
        lda (user_dma), y
        sta (temp), y
        dey
    zuntil_mi

    ; Read the CCP into memory.

    lda #0x80
    sta user_dma+0
    lda temp+1
    sta user_dma+1

    zloop
        ; param remains set from above
        jsr internal_READSEQUENTIAL
        zbreakif_cs

        lda user_dma+0
        eor #$80
        sta user_dma+0
        zif_eq
            inc user_dma+1
        zendif
    zendloop

    ; Patch the BDOS entry vector in the file header.

    lda #0                  ; pop start address, saved earlier
    sta temp+0
    pla
    sta temp+1

    ldy #COMHDR_BDOS
    lda #<ENTRY
    sta (temp), y
    iny
    lda #>ENTRY
    sta (temp), y

    ; Relocate.

    pla                     ; pop start zero page address, saved earlier
    tax
    lda temp+1              ; start of TPA, in pages
    jsr bios_RELOCATE

    ; Execute it.

    lda #BANK_MAIN
    jsr bios_SETBANK

    lda #COMHDR_ENTRY      ; start address is 256-byte aligned
    sta temp+0
calltemp:
    jmp (temp)

    .data
ccp_fcb:
    .byte 1                 ; drive A:
    .ascii "CCP     SYS"    ; filename: CCP.SYS
    .byte 0, 0, 0, 0        ; EX, S1, S2, RC
    .fill 16, 1, 0          ; allocation block
    .byte 0                 ; CR
zendproc
