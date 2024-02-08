; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

READST = $ffb7
SETLFS = $ffba
SETNAM = $ffbd
OPEN = $ffc0
CLOSE = $ffc3
CHKIN = $ffc6
CHKOUT = $ffc9
CHRIN = $ffcf
CHROUT = $ffd2
LOAD = $ffd5
SAVE = $ffd8
CLALL = $ffe7
SETMSG = $ff90
ACPTR = $ffa5
CIOUT = $ffa8
UNTALK = $ffab
UNLSN = $ffae
LISTEN = $ffb1
TALK = $ffb4
SECOND = $ff93
TALKSA = $ff96
CLRCHN = $ffcc
GETIN = $ffe4
SCREEN_MODE = $ff5f
STATUS = $0287

ZEROPAGE

.global ptr
.global ptr1
ptr: .fill 2
ptr1: .fill 2
dma: .fill 2 ; current DMA address

; BASIC loader and relocator. Needs to start at 0x7ff.
.section loader, "ax"

    .word $0801
    .word 1f, 1
    .byte $9e
    .asciz "2061"
1:
    .word 0
.global _start
_start:
    ; Initialise.

    clc
    lda #1
    jsr SCREEN_MODE

    ; Print the startup banner (directly with CHROUT).

    ldy #0
    zloop
        lda loading_msg, y
        zbreakif_eq
        jsr CHROUT
        iny
    zendloop

    ; Relocate the high-memory part of the BIOS into, um, high memory.

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

    ; BIOS initialisation.

    jsr initdrivers

    ; Open the BDOS file (using low level disk access).

    lda #8
    jsr LISTEN
    lda #$f0            ; open channel 0
    jsr SECOND

    ldx #0x100 - bdos_filename_len
    zrepeat
        lda bdos_filename_end - 0x100, x
        jsr CIOUT

        inx
    zuntil_eq

    jsr UNLSN

    ; Read the data.

    lda #<__TPA1_START__
    sta ptr+0
    lda #>__TPA1_START__
    sta ptr+1

    lda #8
    jsr TALK
    lda #$60            ; emit channel 0
    jsr TALKSA

    ldy #0
    sty STATUS
    zrepeat
        jsr ACPTR       ; read a byte
        sta (ptr), y

        inc ptr+0
        zif_eq
            inc ptr+1
        zendif

        lda STATUS      ; check for EOF
    zuntil_ne
    ; The drive will UNTALK automatically on EOF.

    lda #8
    jsr LISTEN
    lda #$e0            ; close channel 0
    jsr SECOND
    jsr UNLSN

    ; Open the CPMFS file.

    lda #8
    jsr LISTEN
    lda #$f2            ; open channel 2
    jsr SECOND

    ldx #0x100 - cpmfs_filename_len
    zrepeat
        lda cpmfs_filename_end - 0x100, x
        jsr CIOUT

        inx
    zuntil_eq

    jsr UNLSN

    ; Relocate the BDOS.

    lda #>__TPA1_START__
    ldx #__ZP1_START__
    jsr bios_RELOCATE

    ; Compute the entry address and jump.

    lda #>__TPA1_START__
    pha
    lda #COMHDR_ENTRY-1 ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump

loading_msg:
    .byte 147, 14, 5
    .ascii "cp/m-65 FOR THE x16"
    .byte 13, 0

bdos_filename:
    .ascii "BDOS,P,R"
bdos_filename_end:
bdos_filename_len = bdos_filename_end - bdos_filename

cpmfs_filename:
    .ascii "CPMFS,P,M"
cpmfs_filename_end:
cpmfs_filename_len = cpmfs_filename_end - cpmfs_filename

; Actual BIOS code.

.text

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

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
        zrepeat
            jsr GETIN
            tax
        zuntil_ne
    zendif
    ldx #0
    stx pending_key

    cmp #20         ; DEL
    zif_eq
        lda #8
    zendif

    clc
    rts
zendproc

zproc tty_conout
    jsr topetscii
    jsr CHROUT
    clc
    rts
zendproc

zproc tty_const
    lda pending_key
    zif_eq
        jsr GETIN
        sta pending_key
        zif_eq
            lda #0
            clc
            rts
        zendif
    zendif

    lda #$ff
    clc
    rts
zendproc

; Sets the current DMA address.

zproc bios_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
zendproc

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

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte sector number.

zproc bios_SETSEC
    sta ptr+0
    stx ptr+1

    ldy #2
    lda (ptr), y
    lsr a
    sta cpmfs_offset+3

    dey
    lda (ptr), y
    ror a
    sta cpmfs_offset+2

    dey
    lda (ptr), y
    ror a
    sta cpmfs_offset+1

    lda #0
    ror a
    sta cpmfs_offset+0
    clc
    rts
zendproc

zproc bios_GETTPA
    ldy current_bank
    lda mem_base, y
    ldx mem_end, y
    clc
    rts
zendproc

zproc bios_SETTPA
    ldy current_bank
    sta mem_base, y
    txa                 ; BUG: stx mem_end, y - invalid 6502 instruction
    sta mem_end, y
    clc
    rts
zendproc

zproc bios_GETZP
    ldy current_bank
    lda zp_base, y
    ldx zp_end, y
    clc
    rts
zendproc

zproc bios_SETZP
    ldy current_bank
    sta zp_base, y
    stx zp_end, y
    clc
    rts
zendproc

zproc bios_SETBANK
    sta current_bank
    rts
zendproc

zproc bios_READ
    jsr seek_to_sector

    ; Read the data.

    lda #8                  ; start reading from file channel
    jsr TALK
    lda #$62                ; channel 2
    jsr TALKSA

    ldy #0
    zrepeat
        jsr ACPTR
        sta (dma), y
        iny
        cpy #$80
    zuntil_eq

    jsr UNTALK
    clc
    rts
zendproc

zproc bios_WRITE
    jsr seek_to_sector

    ; Write the data.

    lda #8                  ; start writing to file channel
    jsr LISTEN
    lda #$62                ; channel 2
    jsr SECOND

    ldy #0
    zrepeat
        lda (dma), y
        jsr CIOUT
        iny
        cpy #$80
    zuntil_eq

    jsr UNLSN
    clc
    rts
zendproc

; Seeks the CPMFS file to the current sector.

zproc seek_to_sector
    lda #8                  ; start writing to command channel
    jsr LISTEN
    lda #$6f                ; channel 15
    jsr SECOND

    lda #'P'                ; seek command
    jsr CIOUT

    lda #2                  ; seek on channel 2
    jsr CIOUT

    ldy #0                  ; send file offset
    zrepeat
        lda cpmfs_offset, y
        jsr CIOUT
        iny
        cpy #4
    zuntil_eq

    jmp UNLSN
zendproc

.data

pending_key:      .byte 0
current_bank:     .byte 0

zp_base:    .byte __ZP0_START__,          __ZP1_START__
zp_end:     .byte __ZP0_END__,            __ZP1_END__
mem_base:   .byte __TPA0_START__@mos16hi, __TPA1_START__@mos16hi
mem_end:    .byte __TPA0_END__@mos16hi,   __TPA1_END__@mos16hi

; DPH for drive 0 (our only drive)

define_drive dph, 128*64, 2048, 128, 0

NOINIT

cpmfs_offset:     .fill 4 ; offset of sector in CPMFS file

directory_buffer: .fill 128

