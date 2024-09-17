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

    ; The CCP.SYS is always loaded from user 0; switch users (but save the old one).

    lda current_user
    pha
    lda #0
    sta current_user

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

    jsr compute_ccp_start_address
    zif_cc
        lda #BANK_MAIN
        jsr bios_SETBANK
        jsr compute_ccp_start_address
        bcc 1b
    zendif

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

    ldy #COMHDR_BDOS
    lda #<ENTRY
    sta (temp), y
    iny
    lda #>ENTRY
    sta (temp), y

    ; Relocate.

    ldx temp+3              ; load start zero page address, saved earlier
    lda temp+1              ; start of TPA, in pages
    jsr bios_RELOCATE

    ; Restore the old user.

    pla
    sta current_user

    ; Execute the CCP.

    lda #BANK_MAIN
    jsr bios_SETBANK

    lda #COMHDR_ENTRY      ; start address is 256-byte aligned
    sta temp+0
calltemp:
    jmp (temp)
    
; user_dma points at the first sector of the CPP; this sets temp to the start
; address that the CCP should be loaded at. Returns with C *CLEAR* if there's no
; room.
;
; temp+3 is set to the start ZP address page.
compute_ccp_start_address:
    jsr bios_GETZP          ; top of ZP in X
    sta temp+2              ; bottom of ZP
    txa
    sec
    ldy #COMHDR_ZP_USAGE
    sbc (user_dma), y
    cmp temp+2              ; check that there's room
    bcc 1f
    sta temp+3              ; store ZP address for later

    jsr bios_GETTPA         ; top of TPA page number in X
    sta temp+2              ; bottom of TPA
    txa
    sec
    ldy #COMHDR_TPA_USAGE
    sbc (user_dma), y
    sta temp+1
    cmp temp+2
    bcc 1f
    lda #0
    sta temp+0
    sec
1:
    rts

    .data
ccp_fcb:
    .byte 1                 ; drive A:
    .ascii "CCP     SYS"    ; filename: CCP.SYS
    .byte 0, 0, 0, 0        ; EX, S1, S2, RC
    .fill 16, 1, 0          ; allocation block
    .byte 0                 ; CR
zendproc
