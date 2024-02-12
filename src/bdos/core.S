; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65.inc"
#include "zif.inc"
#include "jumptables.inc"

CPM_MACHINE_TYPE = $f ; 6502!
CPM_SYSTEM_TYPE = 0
CPM_VERSION = $22 ; CP/M 2.2 (compatible)

ZEROPAGE

.global temp, tempb, user_dma, param

param:            .word 0 ; current user input parameter
user_dma:         .word 0 ; current user DMA address

temp:             .fill 4 ; temporary storage
tempb:            .byte 0 ; more temporary storage

; --- Initialisation --------------------------------------------------------
; TODO: figure out how to discard this.

zproc bdos_core

    ; Reset persistent state.

    lda #0
    sta current_user
    sta current_drive
    
    jmp bdos_EXIT
zendproc

; --- Misc ------------------------------------------------------------------

zproc bdos_GETVERSION
    lda #CPM_VERSION
    ldx #(CPM_MACHINE_TYPE<<4) | CPM_SYSTEM_TYPE
    rts
zendproc

zproc bdos_GETIOBYTE
    lda #0x94               ; %10010100
    clc
    rts
zendproc

; --- Reset disk system -----------------------------------------------------

zproc bdos_RESET
    jsr internal_RESETFILESYSTEM
    lda #0
    sta buffered_key
    sta output_paused
    sta entry_stack
    rts
zendproc

zproc bdos_GETDRIVE
    lda current_drive
    sta param+0
    rts
zendproc

zproc bdos_GETSETUSER
    clc
    lda param+0
    zif_mi
        lda current_user
        rts
    zendif
    sta current_user
    rts
zendproc

zproc bdos_SETDMAADDRESS
    lda param+0
    sta user_dma+0
    lda param+1
    sta user_dma+1
    rts
zendproc

; Sets the random access pointer to whereever the FCB is currently
; pointing.

zproc bdos_COMPUTEPOINTER
    ldy #FCB_EX
    lda (param), y              ; get EX
    lsr a                       ; bottom bit -> C
    sta temp+1                  ; store high byte
    lda #0
    ror a                       ; C -> top bit
    ; low byte in A (the top bit)

    ldy #FCB_CR
    ora (param), y              ; merge in record count
    ldy #FCB_R0
    sta (param), y              ; finished with low byte

    ldy #FCB_S2                ; get S2
    lda (param), y
    asl a
    asl a
    asl a
    asl a
    ora temp+1
    ldy #FCB_R1                ; finished with high byte
    sta (param), y

    clc
    rts
zendproc

; --- Utilities -------------------------------------------------------------

NOINIT

; State preserved between BDOS invocations.

.global current_drive, current_user
current_drive:          .byte 0 ; current working drive
current_user:           .byte 0 ; current working user

; State used by BDOS invocation. Reset to zero every time the BDOS
; is initialised.

buffered_key:           .byte 0
output_paused:          .byte 0 ; top bit set if paused
entry_stack:            .byte 0 ; saved stack on system call entry

; vim: filetype=asm sw=4 ts=4 et

