; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

PIA1    = 0xe810
PIA1_PA = PIA1 + 0
PIA1_PB = PIA1 + 2

PIA2    = 0xe820
PIA2_PA = PIA2 + 0
PIA2_PB = PIA2 + 2

VIA     = 0xe840
VIA_PB  = VIA + 0
VIA_PCR = VIA + 12

CRTC    = 0xe880
CRTC_ADDR = CRTC+0
CRTC_STATUS = CRTC+1
CRTC_DATA = CRTC+1

VIDEO   = 0x8000

ZEROPAGE

.global ptr
ptr:        .word 0
ptr1:       .word 0
dma:        .word 0    ; current DMA

.section header, "ax"
    .word $0401
    .word 1f, 1
    .byte $9e
    .asciz "1037"
1:
    .word 0
    jmp _start

.section relocator, "ax"
.global _start
_start:
    ; Goodbye interrupts, we'll never use you again...

    cli

    ldx #0xff
    txs                     ; reset stack

    ; Copy the BIOS to its final location at 0x200. This overwrites the current
    ; memory image, so care needs to be taken. This routine is _last_ in the
    ; file, so it doesn't get overwritten.

    ; Relocate the BIOS to the top of memory.

    zrepeat
        load = .
        lda bios_load_addr
        store = .
        sta bios_exec_addr

        inc load+1
        zif_eq
            inc load+2
        zendif

        inc store+1
        zif_eq
            inc store+2
        zendif

        lda store+1
        cmp #<bios_end_addr
        zcontinueif_ne
        lda store+2
        cmp #>bios_end_addr
    zuntil_eq
    
    ; Initialise the screen.

    jsr clear_screen

    lda #14
    sta VIA_PCR             ; lowercase

    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr entry_CONOUT
        pla
        tay
        dey
    zuntil_eq

    jmp _realstart

banner: ; reversed!
    .byte 13, 10
    .ascii "56-M/PC"
banner_end:

; Executes once the BIOS is at location.

zproc _realstart
    jmp .
zendproc

; --- Screen handling -------------------------------------------------------

; Writes the character in A.

zproc entry_CONOUT
    cmp #13
    zif_eq
        lda #0
        sta cursorx
        rts
    zendif
    cmp #127
    zif_eq
        dec cursorx
        zif_mi
            inc cursorx
        zendif
        jsr calculate_cursor_address
        lda #' '
        sta (ptr), y
        rts
    zendif
    cmp #10
    beq write_nl

    pha
    jsr calculate_cursor_address
    pla
    ;jsr topetscii
    sta (ptr), y

    inc cursorx
    lda cursorx
    cmp #40
    zif_eq
        lda #0
        sta cursorx
        jmp write_nl
    zendif
    rts
zendproc

zproc write_nl
    inc cursory
    lda cursory
    cmp #24
    zif_eq
        dec cursory
        jmp scroll_up
    zendif
    rts
zendproc

zproc scroll_up
    ldx #0              ; current line
    zrepeat
        txa
        jsr calculate_cursor_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        inx
        txa
        jsr calculate_cursor_address ; ptr is source pointer

        ldy #39
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #23
    zuntil_eq

    ldy #39
    lda #' '
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc clear_screen
    lda #0
    zrepeat
        pha
        jsr calculate_line_address

        ldy #39
        lda #' '
        zrepeat
            sta (ptr), y
            dey
        zuntil_mi

        pla
        clc
        adc #1
        cmp #25
    zuntil_eq

    lda #0
    sta cursorx
    sta cursory
    rts
zendproc

; Sets (ptr), y to the location of the cursor.
zproc calculate_cursor_address
    ldy cursorx
    lda cursory
    ; fall through
zendproc
; Sets ptr to the address of screen line A.
zproc calculate_line_address
    ; x*40 = x*8 + x*32.

    ; We have 25 lines. As 25*8 will fit in a byte, we can do this easily.

    asl a               ; a = y*2
    asl a               ; a = y*4
    asl a               ; a = y*8
    sta ptr+0           ; store y*8

    ; Anything more than this needs to be 16-bit arithmetic.

    asl a               ; = y*16
    rol ptr+1

    asl a               ; = y*13
    rol ptr+1

    ; Add.

    clc
    adc ptr+0
    sta ptr+0
    zif_cs
        inc ptr+1
    zendif

    ; Or in the video address.

    lda ptr+1
    and #0b00000011
    ora #>VIDEO
    sta ptr+1

    rts
zendproc

.bss

cursorx: .fill 1
cursory: .fill 1

; vim: sw=4 ts=4 et ft=asm

