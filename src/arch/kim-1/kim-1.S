; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "kim-1.inc"

ZEROPAGE

.global ptr
.global ptr1
.global tmp1
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
        zbreakif eq
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
    zif eq
        inc srcp+1
    zendif

    inc destp+0
    zif eq
        inc destp+1
    zendif

    lda destp+0
    cmp #<__bios_end
    bne 1b

    lda destp+1
    cmp #>__bios_end
    bne 1b

    ; System initialisation
    lda #0
    sta pending_key
    sta buffer_dirty

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
zendproc

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
    bne 1f

    lda SBD             ; Supress echo
    and #0xfe
    sta SBD

    jsr _tty_bgetch

    pha                 ; Restore echo
    lda SBD
    ora #1
    sta SBD
    pla

1:  ldy #0
    sty pending_key

    clc
    rts
zendproc

zproc tty_conout
    cmp #127
    zif eq
        lda #8
        jsr OUTCH
        lda #' '
        jsr OUTCH
        lda #8
    zendif
    jsr OUTCH
    clc
    rts
zendproc

zproc tty_const
    lda pending_key
    zif eq
        jsr _tty_nbgetch
        sta pending_key
        zif eq
            clc
            rts
        zendif
    zendif

    lda #0xff
    clc
    rts
zendproc

; Blocking tty read. Wait until char ready, then
; put it into A

zproc _tty_bgetch
    lda #1
    zrepeat
        bit SAD         ; Check start bit
        bne 1f
    zuntil pl
    bpl _tty_getch      ; Always jump
1:  lda #0
    rts
zendproc

; Non-blocking tty read. If there is a char ready,
; put it into A. Otherwise, return 0x00. Adapted
; from the KIM-1 ROM

zproc _tty_nbgetch
    lda #1
    bit SAD             ; Check start bit
    bne 1b
    bmi 1b              ; No start bit
zendproc
;
; Fall through
;
zproc _tty_getch
    ldx #8              ; Set up 8 bit count
    lda #1
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
    zuntil eq
    jsr DEHALF
    lda CHAR
    rol a               ; Shift off parity
    lsr a
    rts
zendproc

; --- BIOS entrypoints ------------------------------------------------------

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
    zif cs
        rts
    zendif

    ; Transfer data from FDC into disk buffer

    jsr set_disk_buffer_offset

    ldy #0x7f
    zrepeat
        lda (ptr), y
        sta (dma), y
        dey
    zuntil mi
    clc
    rts
zendproc

zproc bios_WRITE
    pha
    jsr change_sector
    pla

    zif cc
        pha

        ; Calculate offset in DISK_BUFFER

        jsr set_disk_buffer_offset

        ldy #0x7f
        zrepeat
            lda (dma), y
            sta (ptr), y
            dey
        zuntil mi

        lda #0x80
        sta buffer_dirty

        clc
        pla
        zif ne
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

.global mem_end

.bss

directory_buffer:       .fill 128   ; used by the BDOS

.global directory_buffer

pending_key:            .fill 1
buffer_dirty:           .fill 1     ; top bit set if the buffer was modified

.global buffer_dirty
