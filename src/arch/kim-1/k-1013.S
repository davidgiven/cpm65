; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "kim-1.inc"

; K-1013 FDC registers

HSRC = 0xffe8           ; R/W   - K-1003 Hardware Status Register
ADMA = 0xffea           ; Write - K-1013 Set DMA Address Register
MSTR = 0xffee           ; Read  - NEC-765 Main Status Register
DATR = 0xffef           ; R/W   - NEC-765 Data Register

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
        pla
        rts
    zendif

    bcc fdc_exec_senseint
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
    zif_cs
        pla
        rts
    zendif
    ; Fallthrough
zendproc
zproc fdc_exec_senseint, .text.fdc_exec_senseint, local
    ; Wait until FDC interrupt

1:  lda HSRC
    bmi 1b

    ; Execute Sense Interrupt command

    ldx #fdc_senseint-fdc_commands
    jsr fdc_exec_command
    bcs 2f

    ; Read results into memory

    jsr fdc_read_result
    zif_cs
  2:    pla
        rts
    zendif

    ; Compare cylinder number with desired one in ST1

    pla
    cmp disk_status+1
    bne fdc_fail

    ; Look for error in the status registers

    lda disk_status     ; Check ST0
    and #0xf8           ; Delete don't care bits
    cmp #0x20           ; Result must be "Seek Completed"
    bne fdc_fail

    clc
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

    ; Fallthrough
zendproc
zproc fdc_exec_rw, .text.fdc_exec_rw, local

    stx fdc_rw+3        ; Put cylinder in third byte of command
    sta fdc_rw+5        ; Put sector in fifth byte of command
    sta fdc_rw+7        ; Put last sector in seventh byte of command
    sty fdc_rw+2        ; Put drive in second byte of command

    ; Encode read/write buffer address into the DMA address register
    ; DISK_BUFFER is in the higher half of the FDC system RAM, at page 0xfe
    ; Bit 7 and 6: 11  ->  Upper half of system RAM, sys. RAM starts in even boundary
    ; Bits 5-0: Bits 11-6 of the buffer address

    lda #$f8
    sta ADMA

    ; Read/Write data into/from disk buffer

    ldx #fdc_rw-fdc_commands ; Command index into X
    jsr fdc_exec_command
    zif_cs
        rts
    zendif

    ; Wait until IRQ from FDC

1:  lda HSRC            ; Wait until IRQ from FDC
    bmi 1b

    ; Read results into memory

    jsr fdc_read_result
    zif_cs
        rts
    zendif

    ; Look for error in the status registers

    lda disk_status     ; Check ST0
    and #0xd8           ; Delete don't care bits
    beq 2f              ; Jump ahead if ST0 clear
    cmp #0x40           ; Test if abnormal termination
    bne fdc_fail        ; Real error if not
    lda disk_status+1   ; If abnormal termination, check ST1 for end of cylinder
    bpl fdc_fail        ; Nope, then it is an error
2:  lda disk_status+1   ; Check ST1
    and #0x35           ; Mask out non-error bits
    bne fdc_fail        ; Error if any remainder set
    lda disk_status+2   ; Check ST2
    and #0x33           ; Mask out non-error bits
    bne fdc_fail        ; Error if any remainder set

    clc
    rts
zendproc

zproc fdc_fail, .text.fdc_fail, local
    sec
    rts
zendproc

; Command index in X

zproc fdc_exec_command, .text.fdc_exec_command, local
    lda MSTR            ; Load Main Status Register
    and #0x10           ; Check if busy
    bne fdc_fail

    ldy fdc_commands, x ; Load command length
    inx

    zloop
1:      lda MSTR            ; Load Main Status Register again
        bpl 1b              ; Wait until RQM from controller
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
1:      lda MSTR            ; Load Main Status Register again
        bpl 1b              ; Wait until RQM from controller
        and #0x40           ; Test data direction bit
        beq fdc_fail        ; Error if controller wants to listen

        lda DATR            ; Get status byte from data register
        sta disk_status, x  ; Put it into memory
        inx                 ; Next byte
        nop                 ; Give the controller time to update
        nop                 ; the MSTR with a valid busy status
        lda #0x10           ; Check if busy and go get another
        and MSTR            ; byte while so
    zuntil_eq

    clc
    rts
zendproc

.data

; NEC-765 pre-formatted command strings

fdc_commands:
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

.bss

disk_status:            .fill 8     ; Result phase readouts from NEC-765
