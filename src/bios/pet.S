; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

PIA1    = 0xe810
PIA1_PA = PIA1 + 0
PIA1_CA = PIA1 + 1
PIA1_PB = PIA1 + 2
PIA1_CB = PIA1 + 3

PIA1_PA_EOI_IN = 1<<6
PIA1_CA_EOI_OUT = 1<<2

PIA2    = 0xe820
PIA2_PA = PIA2 + 0
PIA2_CA = PIA2 + 1
PIA2_PB = PIA2 + 2
PIA2_CB = PIA2 + 3

PIA2_CA_NDAC_OUT = 1<<3

PIA2_CB_SRQ_IN = 1<<1
PIA2_CB_DAV_OUT = 1<<3

VIA     = 0xe840
VIA_PB  = VIA + 0
VIA_PCR = VIA + 12

VIA_PB_NDAC_IN  = 1<<0
VIA_PB_NRFD_OUT = 1<<1
VIA_PB_ATN_OUT  = 1<<2
VIA_PB_NRFD_IN  = 1<<6
VIA_PB_DAV_IN   = 1<<7

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

    jsr assert_atn
    lda #0x28               ; LISTEN device 8
    jsr ieee_putb
    lda #0xf0               ; OPEN channel 2
    jsr ieee_putb
    jsr release_atn

    lda #'$'
    jsr ieee_putlastb

    jsr assert_atn
    lda #0x3f               ; UNLISTEN
    jsr ieee_putb
    jsr release_atn

    jsr assert_atn
    lda #0x48               ; TALK device 8
    jsr ieee_putb
    lda #0x60               ; SECOND channel 2
    jsr ieee_putb
    jsr release_atn

    zrepeat
        jsr ieee_getb
        php
        jsr print_hex_number
        lda #' '
        jsr entry_CONOUT
        plp
    zuntil_cs

    lda #'!'
    jsr entry_CONOUT

    jmp _realstart

banner: ; reversed!
    .byte 13, 10
    .ascii "56-M/PC"
banner_end:

print_hex_number:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr print
        pla
print:
        and #0x0f
        ora #48
        cmp #58
    zif_cs
        adc #6
    zendif
        pha
        jsr entry_CONOUT
        pla
        rts

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

; --- Disk handling ---------------------------------------------------------

.macro set1 port, bit
    lda \port
    ora #\bit
    sta \port
.endm

.macro set0 port, bit
    lda \port
    and #(~(\bit)) & 0xff
    sta \port
.endm

; See http://www.6502.org/users/andre/petindex/local/pet-io-2.txt
; https://www.pagetable.com/?p=1023
; http://www.primrosebank.net/computers/pet/documents/PET_and_the_IEEE488_Bus_text.pdf
; (appendix E)

zproc ieee_putlastb
    ; Assert EOI and then send.

    ldx #0x34
    stx PIA1_CA
zendproc
    ; fall through
zproc ieee_putb
    ; Deassert our own NRFD and wait for NRFD=0 (i.e. ready for data)

    pha
    set1 VIA_PB, VIA_PB_NRFD_OUT
    zrepeat
        lda VIA_PB
        and #VIA_PB_NRFD_IN
    zuntil_ne
    pla

    ; Send data, inverted.

    eor #0xff
    sta PIA2_PB

    ; Set DAV to 0 (i.e. data is available)

    set0 PIA2_CB, PIA2_CB_DAV_OUT

    ; Wait for acknowledgement.

    zrepeat
        lda VIA_PB
        and #VIA_PB_NDAC_IN
    zuntil_ne

    ; Release DAV, EOI and the data bus.

    set1 PIA2_CB, PIA2_CB_DAV_OUT
    ldx #0x3c
    stx PIA1_CA
    lda #0xff
    sta PIA2_PB

    rts
zendproc

; Receives a byte into A. Sets C on EOI.

zproc ieee_getb
    ; Set NRFD = 1 (indicating we are ready for data).
    ; Set NDAC = 0 (no data acknowledgement).

    set1 VIA_PB, VIA_PB_NRFD_OUT
    set0 PIA2_CA, PIA2_CA_NDAC_OUT

    ; Wait for DAV.

    zrepeat
        lda VIA_PB
        and #VIA_PB_DAV_IN
    zuntil_eq

    ; Not ready for data.

    set0 VIA_PB, VIA_PB_NRFD_OUT
    
    ; Get the data.

    lda PIA2_PA
    eor #0xff
    pha

    ; Check for EOI.

    lda PIA1_PA
    and #PIA1_PA_EOI_IN
    sec
    zif_ne
        clc
    zendif

    ; Acknowledge the data.

    set1 PIA2_CA, PIA2_CA_NDAC_OUT

    ; Wait for !DAV.

    zrepeat
        lda VIA_PB
        and #VIA_PB_DAV_IN
    zuntil_ne

    ; Release NDAC and the data bus.

    set0 PIA2_CA, PIA2_CA_NDAC_OUT
    lda #0xff
    sta PIA2_PB

    pla
    rts
zendproc

; Asserts ATN.

zproc assert_atn
    lda VIA_PB
    and #(~VIA_PB_ATN_OUT) & 0xff
    sta VIA_PB
    rts
zendproc

; Deasserts ATN.

zproc release_atn
    lda VIA_PB
    ora #VIA_PB_ATN_OUT
    sta VIA_PB
    rts
zendproc
    
.bss

cursorx: .fill 1
cursory: .fill 1

; vim: sw=4 ts=4 et ft=asm
