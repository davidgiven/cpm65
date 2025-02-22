; ---------------------------------------------------------------------------
;
; K-1013 format utility
;
; Copyright © 2024 Eduardo Casino
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; The low-level disk routines are basically copied from MTU's K-1013
; diagnostics.
;
; ---------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"
#include "k-1013.inc"

NSTAG = 8                   ; Number of sectors to stagger per track

DMA_BUFFER = $fd00          ; We are using the 256-byte page just below the disk
                            ; buffer ($fd00), which encodes to $f4. See K-1013 manual.

    .bss

; Uninitiaized program variables

drive:          .fill 1
drive_letter:   .fill 1
track:          .fill 1
side:           .fill 1
sector:         .fill 1
stagger:        .fill 1

    .text

zproc format
    ; Put the disk controller in a sane state

    lda HSRC                ; Test if an interrupt is pending
    zif_pl
        jsr fdc_exec_senseint
    zendif

    ; Recalibrate (send heads to track 0)

    ldy drive
    jsr fdc_exec_recal
    zif_cs
        jmp recal_error
    zendif

    lda #0                  ; Set DMA read mode, unprotect SYSRAM
    sta HSRC
    sta side                ; Initialize disk side,
    sta track               ; track number
    sta stagger             ; and stagger factor

    ; Create formatting data area for next track

    zloop
        jsr print_dot

        ldx stagger         ; Initialize sector number pointer
        ldy #0              ; Initialize pointer into format data area
        zrepeat
            lda track       ; Put track number,
            sta DMA_BUFFER,Y
            iny
            lda side        ; side number
            sta DMA_BUFFER,Y
            iny
            lda alttab,X    ; Lookup sector number in alternate table
            sta DMA_BUFFER,Y
            iny
            lda #1          ; 256 bytes per sector
            sta DMA_BUFFER,Y
            iny
            inx             ; Increment sector number pointer
            txa             ; Mod 26
            jsr mod26
            tax
            cpy #26*4       ; Test if 26 sectors gone through
        zuntil_eq

        ldy drive
        jsr fdc_exec_format
        zif_cs
            jmp format_error
        zendif

        ldy #0              ; Wait at least 500uS after write to allow the write
        zrepeat             ; current to decay before seeking again
            dey
        zuntil_eq

        lda stagger         ; Add in stagger factor for next track
        clc
        adc #26-NSTAG
        jsr mod26           ; Sum mod 26
        sta stagger         ;

        inc track           ; Increment track number
        lda track
        cmp #77             ; Test if all tracks formatted
        zbreakif_eq         ; If so, finished

        ldy drive           ; Seek to the new track
        jsr fdc_exec_seek
        zif_cs
            jmp seek_error
        zendif
    zendloop

    clc
    rts
zendproc

; Calculate modulo 26 of A
;
zproc mod26
    zloop
        cmp     #26         ; Return a mod 26
        zbreakif_cc
        sbc     #26         ; If not, substract 26
    zendloop
    rts
zendproc

zproc main
    ; Get drive from command line

    lda cpm_fcb+1
    cmp #' '                ; File name must be empty
    bne usage
	lda cpm_fcb
    cmp #0                  ; Drive number can't be default
    beq usage

    ; Get drive number in base 0 and drive leter

    sec
    sbc #1
    sta drive
    clc
    adc #'A'
    sta drive_letter

    ; Check if the drive exists

    lda drive
    ldy #BIOS_SELDSK
    jsr BIOS
    bcs invalid

    ; Warning message

    lda drive_letter
    sta warning_drv
    lda #<warning_msg
    ldx #>warning_msg
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    ; Get confirmation

    ldy #BDOS_CONSOLE_INPUT
    jsr BDOS
    cmp #'y'
    bne abort

    lda #<crlf
    ldx #>crlf
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    jsr format

    zif_cc
        lda #<done_msg
        ldx #>done_msg
        ldy #BDOS_WRITE_STRING
        jmp BDOS
    zendif

    rts

zendproc

; Error routines
;
zproc usage
    lda #<usage_msg
    ldx #>usage_msg
    ldy #BDOS_WRITE_STRING
    jmp BDOS
zendproc

zproc recal_error
    lda #<recal_msg
    ldx #>recal_msg
    jmp print_err
zendproc

zproc seek_error
    lda #<seek_msg
    ldx #>seek_msg
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    lda track
    jsr print_byte
    lda #<seek_msg2
    ldx #>seek_msg2
    jmp print_err
zendproc

zproc invalid
    lda drive_letter
    sta invalid_drv
    lda #<invalid_msg
    ldx #>invalid_msg
    ldy #BDOS_WRITE_STRING
    jmp BDOS
zendproc

zproc abort
    lda #<abort_msg
    ldx #>abort_msg
    ldy #BDOS_WRITE_STRING
    jmp BDOS
zendproc

zproc print_dot
    lda #'.'
    ldy #BIOS_CONOUT
    jmp BIOS
zendproc

zproc format_error
    lda #<format_msg
    ldx #>format_msg
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    lda track
    jsr print_byte
    lda #<format_msg2
    ldx #>format_msg2
zendproc
; Fall through
zproc print_err
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    sec
    rts
zendproc

; This routine assumes A < 100 (disk has 77 tracks)
;
; Derived from https://beebwiki.mdfs.net/Number_output_in_6502_machine_code
;
zproc print_byte
    ldx #$ff
    sec
    zrepeat
        inx                 ; Count number of 10s
        sbc #10
    zuntil_cc
    adc #10
    pha                     ; Save units
    txa
    zif_ne
        jsr print_digit
    zendif
    pla                     ; Restore units
zendproc
; Fall through
zproc print_digit
    ora #'0'
    ldy #BIOS_CONOUT
    jmp BIOS
zendproc

    .rodata

; Constants

alttab: .byte   0,  13, 1,  14  ; Table of interleaved sector numbers
        .byte   2,  15, 3,  16  ; Interleave factor = 2
        .byte   4,  17, 5,  18
        .byte   6,  19, 7,  20
        .byte   8,  21, 9,  22
        .byte   10, 23, 11, 24
        .byte   12, 25

    .data

; Messages

invalid_msg:    .ascii "Error: invalid drive '"
invalid_drv:    .byte 0
                .ascii "'."
crlf:           .byte 13,10,0

usage_msg:      .ascii "Syntax: format <drive>"
                .byte 13,10,0

warning_msg:    .ascii "Warning: about to format drive '"
warning_drv:    .byte 0
                .ascii "',\n\rdestroying everything on it."
                .byte 13,10
                .ascii "Press Y to proceed, anything else to cancel: "
                .byte 0

abort_msg:      .byte 13,10
                .ascii "Aborted by user."
                .byte 13,10,0

done_msg:       .byte 13,10
                .ascii "Done."
                .byte 13,10,0

format_msg:     .byte 13,10
                .ascii "Error: Unable to format track "
                .byte 0
format_msg2:    .byte '.',13,10,0

recal_msg:      .ascii "Error: Unable to retract head to track 0."
                .byte 13,10,0

seek_msg:       .byte 13,10
                .ascii "Error: Unable to position head over cylinder "
                .byte 0
seek_msg2:      .byte '.',13,10,0