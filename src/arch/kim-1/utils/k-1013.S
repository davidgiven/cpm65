; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

; Reduced version of the k-1013 library for the format commmand

#include "zif.inc"
#include "kim-1.inc"
#include "k-1013.inc"

DMA_AREA = $f4                  ; We are using the 256-byte page just below the disk
                                ; buffer ($fd00), which encodes to $f4. See K-1013 manual.

zproc fdc_exec_specify, .text.fdc_exec_specify
    ; Save cylinder for later check

    ldx #fdc_specify-fdc_commands ; Command index into X
    jsr fdc_exec_command
    rts
zendproc

; Drive in Y

zproc fdc_exec_recal, .text.fdc_exec_recal
    ; Save cylinder for later check

    lda #0
    pha

    ; Put drive in second byte of command

    sty fdc_recal+2

    ldx #fdc_recal-fdc_commands ; Command index into X
    jsr fdc_exec_command
    zif_cs
1:      pla
        rts
    zendif

    jsr fdc_exec_senseint
    bcs 1b

    ; Compare cylinder number with desired one in ST1

    pla
    cmp disk_status+1
    zif_ne
        sec
        rts
    zendif
    clc
    rts
zendproc

; Seek track in A, drive in Y

zproc fdc_exec_seek, .text.fdc_exec_seek

    ; Save cylinder for later check

    pha

    ; Put new cylinder number into third byte of seek command

    sta fdc_seek+3
    sty fdc_seek+2              ; Put drive in second byte of command

    ldx #fdc_seek-fdc_commands  ; Command index into X
    jsr fdc_exec_command
    bcs 1b

    jsr fdc_exec_senseint
    bcs 1b

    ; Compare cylinder number with desired one in ST1

    pla
    cmp disk_status+1
    bne fdc_fail

    clc
    rts
zendproc

zproc fdc_exec_senseint, .text.fdc_exec_senseint
    ; Wait until FDC interrupt

    zrepeat
        lda HSRC
    zuntil_pl

    ; Execute Sense Interrupt command

    ldx #fdc_senseint-fdc_commands
    jsr fdc_exec_command
    zif_cc
        ; Read results into memory

        jsr fdc_read_result
        zif_cc
            ; Look for error in the status registers

            lda disk_status     ; Check ST0
            and #0xf8           ; Delete don't care bits
            cmp #0x20           ; Result must be "Seek Completed"
            bne fdc_fail
            clc
        zendif
    zendif
    rts
zendproc

zproc fdc_fail, .text.fdc_fail, local
    sec
    rts
zendproc

; Format track
; Drive in Y, track data in area pointed by ADMA

zproc fdc_exec_format, .text.fdc_exec_format

    sty fdc_format+2              ; Put drive in second byte of command

    lda #DMA_AREA
    sta ADMA

    ldx #fdc_format-fdc_commands  ; Command index into X
    jsr fdc_exec_command
    zif_cs
        rts
    zendif

    ; Wait until IRQ from FDC

    zrepeat
        lda HSRC            ; Wait until IRQ from FDC
    zuntil_pl

    ; Read results into memory

    jsr fdc_read_result
    zif_cs
        rts
    zendif

    ; Look for error in the status registers

    lda disk_status     ; Check ST0
    and #0xd8           ; Delete don't care bits
    bne fdc_fail        ; Error if any remainder set
    lda disk_status+1   ; Check ST1
    and #0x35           ; Delete don't care bits
    bne fdc_fail        ; Error if any remainder set
    lda disk_status+2   ; Check ST2
    and #0x33           ; Mask out non-error bits
    bne fdc_fail        ; Error if any remainder set

    clc
    rts

zendproc

; Command index in X

zproc fdc_exec_command, .text.fdc_exec_command, local
    lda MSTR                ; Load Main Status Register
    and #0x10               ; Check if busy
    bne fdc_fail

    ldy fdc_commands, x     ; Load command length
    inx

    zloop
        zrepeat
            lda MSTR        ; Wait until RQM from controller
        zuntil_mi
        and #0x40           ; Test data direction bit
        bne fdc_fail        ; Error if controller wants to talk

        lda fdc_commands, x ; Get command byte
        sta DATR            ; Store into FDC data register
        inx                 ; Next command byte
        dey
    zuntil_eq

    clc
    rts
zendproc

zproc fdc_read_result, .text.fdc_read_result, local
    ldx #0
    zloop
        zrepeat
            lda MSTR        ; Wait until RQM from controller
        zuntil_mi
        and #0x40           ; Test data direction bit
        beq fdc_fail        ; Error if controller wants to listen

        lda DATR            ; Get status byte from data register
        sta disk_status, x  ; Put it into memory
        inx                 ; Next byte
        nop                 ; Give the controller time to update
        nop                 ; the MSTR with a valid busy status
        lda #0x40           ; Check if still talking and go get another
        and MSTR            ; byte while so
    zuntil_eq

    clc
    rts
zendproc

.data

; NEC-765 pre-formatted command strings

fdc_commands:
fdc_specify:
    .byte 3             ; Command length
    .byte 3             ; Specify  
    .byte 0x6f          ; Step Rate Time   = 10ms, Head Unload Time = 240ms
    .byte 0x20          ; Head Load Time   = 32ms
                                            
fdc_recal:
    .byte 2             ; Command length
    .byte 7             ; Recalibrate
    .byte 0             ; Drive

fdc_senseint:
    .byte 1             ; Command length
    .byte 8             ; Sense Interrupt Status

fdc_seek:
    .byte 3             ; Command length
    .byte 0xf           ; Command code
    .byte 0             ; Drive number in bits 0-1, side number in bit 2
    .byte 0             ; NCN: New cylinder number

fdc_format:
    .byte 6             ; Command length
    .byte 0x4d          ; Format a double density track command
    .byte 0             ; Drive number in bits 0-1, side number in bit 2
    .byte 1             ; Specify 256 bytes/sector
    .byte 0x1a          ; Specify 26 sectors/track
    .byte 0x36          ; Gap length for 26 sectors, 256 bytes/sect
    .byte 0xe5          ; Data field filler byte

.bss

disk_status:            .fill 8     ; Result phase readouts from NEC-765
