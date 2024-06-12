; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

OUTCH = $1ea0
GETCH = $1e5a

ZEROPAGE

.global ptr
.global ptr1
ptr: .fill 2
ptr1: .fill 2
dma: .fill 2 ; current DMA address

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
        jsr OUTCH
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

    ; BIOS initialisation.

    jsr initdrivers

    ; Open the BDOS file (using low level disk access).

    ; Read the BDOS.

    jmp .

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
    .byte 13, 10
    .ascii "CP/M-65 for the KIM-1"
    .byte 13, 0

bdos_filename:
    .ascii "BDOS    SYS"

; Actual BIOS code.

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
            jsr GETCH
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
    jsr OUTCH
    clc
    rts
zendproc

zproc tty_const
    lda pending_key
    zif_eq
        jsr GETCH
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

.text
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
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc bios_SETTPA
    sta mem_base
    txa
    sta mem_end
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

zproc bios_READ
    jsr seek_to_sector

    ; Read the data.

    clc
    rts
zendproc

zproc bios_WRITE
    jsr seek_to_sector

    ; Write the data.

    clc
    rts
zendproc

; Seeks the CPMFS file to the current sector.

zproc seek_to_sector
    clc
    rts
zendproc

.data

pending_key:      .byte 0

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi

; DPH for drive 0 (our only drive)

define_drive dph, 128*64, 2048, 128, 0

NOINIT

cpmfs_offset:     .fill 4 ; offset of sector in CPMFS file

.global directory_buffer

directory_buffer: .fill 128

