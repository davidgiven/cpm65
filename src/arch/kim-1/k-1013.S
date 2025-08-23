; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "kim-1.inc"
#include "k-1013.inc"

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
    bcs fdc_pla_ret

    jsr fdc_exec_senseint
    bcs fdc_pla_ret

    ; Compare cylinder number with desired one in ST1

    pla
    cmp disk_status+1
    zif ne
        sec
        rts
    zendif
    clc
    rts
zendproc

zproc fdc_pla_ret, .text.fdc_pla_ret, local
    pla
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
    bcs fdc_pla_ret

    jsr fdc_exec_senseint
    bcs fdc_pla_ret

    ; Compare cylinder number with desired one in ST1

    pla
    cmp disk_status+1
    bne fdc_fail

    clc
    rts
zendproc

; Sector num in A, cylinder in X, drive in Y

zproc fdc_exec_write, .text.fdc_exec_write
    pha

    ; Put READ DATA command code into command byte

    lda #$45            ; Write, no multitrack, MFM, don't skip deleted
    sta fdc_rw+1

    ; Set FDC DMA read mode

    lda #0
    sta HSRC

    pla
zendproc
;
; Fall through
;
zproc fdc_exec_rw, .text.fdc_exec_rw, local

    stx fdc_rw+3        ; Put cylinder in third byte of command
    sta fdc_rw+5        ; Put sector in fifth byte of command
    sta fdc_rw+7        ; Put last sector in seventh byte of command
    sty fdc_rw+2        ; Put drive in second byte of command

    ; Encode read/write buffer address into the DMA address register
    ; DISK_BUFFER is in the higher half of the FDC system RAM, at page 0xfe
    ; Bit 7 and 6: 11  ->  Upper half of system RAM, sys. RAM starts in even boundary
    ; Bits 5-0: Bits 11-6 of the buffer address

    lda #BUFFER_DMA
    sta ADMA

    ; Read/Write data into/from disk buffer

    ldx #fdc_rw-fdc_commands ; Command index into X
    jsr fdc_exec_command
    zif cs
        rts
    zendif

    ; Wait until IRQ from FDC

    zrepeat
        lda HSRC        ; Wait until IRQ from FDC
    zuntil pl

    ; Read results into memory

    jsr fdc_read_result
    zif cs
        rts
    zendif

    ; Look for error in the status registers

    lda disk_status     ; Check ST0
    and #0xd8           ; Delete don't care bits
    zif ne
        ; ST0 is not clear, dig further
        cmp #0x40           ; Test if abnormal termination
        bne fdc_fail        ; Real error if not
        lda disk_status+1   ; If abnormal termination, check ST1 for end of cylinder
        bpl fdc_fail        ; Nope, then it is an error
    zendif
    lda disk_status+1   ; Check ST1
    and #0x37           ; Mask out non-error bits
    bne fdc_fail        ; Error if any remainder set
    lda disk_status+2   ; Check ST2
    and #0x33           ; Mask out non-error bits
    bne fdc_fail        ; Error if any remainder set

    clc
    rts
zendproc

zproc fdc_exec_senseint, .text.fdc_exec_senseint
    ; Wait until FDC interrupt

    zrepeat
        lda HSRC
    zuntil pl

    ; Execute Sense Interrupt command

    ldx #fdc_senseint-fdc_commands
    jsr fdc_exec_command
    zif cc
        ; Read results into memory

        jsr fdc_read_result
        zif cc
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

; Sector num in A, cylinder in X, drive in Y

zproc fdc_exec_read, .text.fdc_exec_read
    pha

    ; Put READ DATA command code into command byte

    lda #$46            ; Read, no multitrack, MFM, don't skip deleted
    sta fdc_rw+1

    ; Set FDC DMA write mode

    lda #1
    sta HSRC

    pla

    jmp fdc_exec_rw
zendproc

zproc fdc_fail, .text.fdc_fail, local
    sec
    rts
zendproc

zproc fdc_exec_sensestatus, .text.fdc_exec_sensestatus

    sty fdc_status+2    ; Put drive in second byte of command

    ; Execute command

    ldx #fdc_status-fdc_commands
    jsr fdc_exec_command
    zif cc
        ; Read results into memory

        jsr fdc_read_result
        zif cc
            ; And return status in A

            lda disk_status     ; Load ST3
        zendif
    zendif
    rts
zendproc

; Command index in X

zproc fdc_exec_command, .text.fdc_exec_command, local
    zloop
        lda #0x10           ; Check if uPD765 is busy processing a command
        and MSTR            ;   (should not occur, but happens)
        zbreakif eq         ; Not busy, go execute command
                            ; Yes, execute recovery procedure
        zrepeat
            bit MSTR        ; wait until ready to read or write
        zuntil mi

        zif vc              ; Data register ready to write
            lda #$00        ; Try to complete command sequence
            sta DATR
            beq 1f          ; And try again
        zendif
                            ; Else, data register needs to be read
        lda DATR            ; Read status register
1:      nop                 ; Wait a few cycles
        nop
    zendloop

    ldy fdc_commands, x     ; Load command length
    inx

    zrepeat
        zrepeat
            lda MSTR        ; Wait until RQM from controller
        zuntil mi
        and #0x40           ; Test data direction bit
        bne fdc_fail        ; Error if controller wants to talk

        lda fdc_commands, x ; Get command byte
        sta DATR            ; Store into FDC data register
        inx                 ; Next command byte
        dey
    zuntil eq

    clc
    rts
zendproc

zproc fdc_read_result, .text.fdc_read_result, local
    ldx #0
    zloop
        zrepeat
            lda MSTR        ; Wait until RQM from controller
        zuntil mi
        and #0x40           ; Test data direction bit
        beq fdc_fail        ; Error if controller wants to listen

        lda DATR            ; Get status byte from data register
        sta disk_status, x  ; Put it into memory
        inx                 ; Next byte
        nop                 ; Give the controller time to update
        nop                 ; the MSTR with a valid busy status
        lda MSTR            ; Check if still busy and get next
        and #0x10           ; byte while so
    zuntil eq

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

fdc_rw:
    .byte 9             ; Command length
    .byte 0             ; Read or write command code. Updated by function
    .byte 0             ; Drive number in bits 0-1, side number in bit 2
    .byte 0             ; C: Present cylinder number. Must match current track
    .byte 0             ; H: Head
    .byte 0             ; R: Sector number to read
    .byte 1             ; N: Code for 256 bytes per sector
    .byte 0             ; EOT: Last sector to read
    .byte 0xe           ; GPL: Gap length for 26 sectors, 256 bytes/sect
    .byte 0xff          ; DTL: Data length = 0xff since N is non-zero

fdc_status:
    .byte 2             ; Command length
    .byte 4             ; Sense Drive Status command
    .byte 0             ; Drive number in bits 0-1, head number in bit 2

.bss

.global disk_status

disk_status:            .fill 8     ; Result phase readouts from NEC-765
