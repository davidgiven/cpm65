; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "driver.inc"
#include "kim-1.inc"

ZEROPAGE

.global ptr
.global ptr1
ptr: .fill 2
ptr1: .fill 2
dma: .fill 2            ; current DMA address
tmp1: .fill 1
tmp2: .fill 1

; BASIC loader and relocator. Needs starts at 0xc000 (K-1013 user ram )

.section loader, "ax"

.global _start
_start:
    ; Initialise.

    clc

    ; Print the startup banner (directly with OUTCH).

    ldy #0
    zloop
        lda loading_msg, y
        zbreakif_eq
        sty tmp1
        jsr OUTCH
        ldy tmp1
        iny
    zendloop

    ; Relocate the bios into low ram.

1:
    srcp = . + 1
    lda __bios_data_start
    destp = . + 1
    sta __bios_start

    inc srcp+0
    zif_eq
        inc srcp+1
    zendif

    inc destp+0
    zif_eq
        inc destp+1
    zendif

    lda destp+0
    cmp #<__bios_end
    bne 1b

    lda destp+1
    cmp #>__bios_end
    bne 1b

    jsr system_init

    ; BIOS initialisation.

    jsr initdrivers

    ; Open the BDOS file (using low level disk access).

    ; Read the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy #>__TPA_START__
    jsr loadfile

    ; Relocate it.

    lda #>__TPA_START__
    ldx #__ZEROPAGE_START__
    jsr bios_RELOCATE

    ; Compute the entry address and jump.

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA_START__ + COMHDR_ENTRY

loading_msg:
    .byte 13, 10, 10
    .ascii "CP/M-65 for the KIM-1"
    .byte 13, 10, 0

bdos_filename:
    .ascii "BDOS    SYS"

; Actual BIOS code.

; --- TTY driver ------------------------------------------------------------

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

.text

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    pha
    lda jmptable_lo, y
    sta ptr+0
    lda jmptable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

jmptable_lo:
    .byte tty_const@mos16lo
    .byte tty_conin@mos16lo
    .byte tty_conout@mos16lo
jmptable_hi:
    .byte tty_const@mos16hi
    .byte tty_conin@mos16hi
    .byte tty_conout@mos16hi
zendproc

; Blocks and waits for the next keypress; returns it in A.

zproc tty_conin
    lda pending_key
    zif_eq
        sty tmp1        ; Save Y
        lda SBD         ; Supress echo
        and #0xfe
        sta SBD
        jsr GETCH
        pha
        lda SBD         ; Restore echo
        ora #1
        sta SBD
        pla
        cmp #0x20       ; Echo control characters
        zif_cc
            pha
            jsr OUTCH
            pla
        zendif
        ldy tmp1        ; Restore Y
    zendif
    ldx #0
    stx pending_key

    cmp #20             ; DEL
    zif_eq
        lda #8
    zendif

    clc
    rts
zendproc

zproc tty_conout
    sty tmp1            ; Save Y
    cmp #'\n'
    zif_eq
        pha
        lda #'\r'
        jsr OUTCH
        pla
    zendif
    jsr OUTCH
    ldy tmp1            ; Restore Y
    clc
    rts
zendproc

zproc tty_const
    lda pending_key
    zif_eq
        jsr tty_nbgetch
        sta pending_key
        zif_eq
            clc
            rts
        zendif
    zendif

    lda #0xff
    clc
    rts
zendproc

; Non-blocking tty read. If there is a char ready,
; put it into A. Otherwise, return 0x00. Adapted
; from the KIM-1 ROM

zproc tty_nbgetch
    sty tmp1            ; Save XY
    stx tmp2
    ldx #8              ; Set up 8 bit count
    lda #1
    bit SAD             ; Check start bit
    bne 1f
    bmi 1f              ; No start bit
    jsr DELAY           ; Delay 1 bit
    jsr DEHALF          ; Delay 1/2 bit time
    zrepeat             ; Get 8 bits loop
        lda SAD
        and #0x80       ; Mask off low order bits
        lsr CHAR        ; Shift bit into CHAR
        ora CHAR
        sta CHAR
        jsr DELAY
        dex
    zuntil_eq
    jsr DEHALF
    lda CHAR
    rol a               ; Shift off parity
    lsr a
    bne 2f
1:  lda #0
2:  ldx tmp2            ; Restore XY
    ldy tmp1
    rts
zendproc

; --- BIOS entrypoints ------------------------------------------------------

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc bios_SELDSK
    cmp #0
    zif_ne
        sec                 ; invalid drive
        rts
    zendif

    sta current_drive

    lda #<dph0
    ldx #>dph0
    clc
    rts
zendproc

zproc bios_GETTPA
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc bios_SETTPA
    sta mem_base
    stx mem_end
    clc
    rts
zendproc

zproc bios_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc

zproc bios_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc bios_SETBANK
    rts
zendproc


; Sets the current DMA address.

zproc bios_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
zendproc

zproc bios_READ
    jsr change_sector
    zif_cs
        rts
    zendif

    ; Transfer data from FDC into disk buffer

    jsr set_disk_buffer_offset

    ldy #0x7f
    zrepeat
        lda (ptr), y
        sta (dma), y
        dey
    zuntil_mi
    clc
    rts
zendproc

zproc bios_WRITE
    pha
    jsr change_sector
    pla

    zif_cc
        pha

        ; Calculate offset in DISK_BUFFER

        jsr set_disk_buffer_offset

        ldy #0x7f
        zrepeat
            lda (dma), y
            sta (ptr), y
            dey
        zuntil_mi

        lda #0x80
        sta buffer_dirty

        clc
        pla
        zif_ne
            jsr flush_buffer
        zendif
    zendif
    rts
zendproc

; --- Data ------------------------------------------------------------------

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi

.bss

directory_buffer:       .fill 128   ; used by the BDOS

.global directory_buffer

pending_key:            .byte 0
current_drive:          .fill 1     ; Current selected disk drive number
buffer_dirty:           .fill 1     ; top bit set if the buffer was modified
buffer_offset:          .fill 1     ; Offset of CP/M sector into host sector buffer
