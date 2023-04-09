; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

.global _start
ZEROPAGE

ptr:    .word 0
ptr1:   .word 0

; --- Initialisation code ---------------------------------------------------

; Boot sector and relocator. Loaded at 0x0800 when the disk boots. Called once
; on startup and then never again.
.section loader, "ax"
	.byte BIOS_SECTOR_COUNT ; boot loader loads this many sectors
_start:
    cli
	lda	0xc088, x			; turn off disk motor
    sta 0xc08b              ; R/W 0xe000 RAM; bank 1 in 0xd000
    sta 0xc08b              ; yes, I'm sure
    ldx #0xff
    txs                     ; reset stack

    ; Relocate the BIOS to the top of memory.

    zloop
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
            zbreakif_eq
        zendif
    zendloop

    jmp _init

banner: ; reversed!
    .byte 13, 10
    .ascii "56-M/PC"
banner_end:

    ; One byte to spare here. This must be at offset 0x3f in the disk
    ; image in order to spoof emulators into thinking this is a ProDOS
    ; format.

    .org 0x3a
    .ascii "PRODOS"

_init:
    ; Print the startup banner.

    jsr clear_screen
    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr write_char
        pla
        tay
        dey
    zuntil_eq


    ; Build the GCR tables.

    ldy #0
    ldx #0x16
    zrepeat
        stx ptr
        txa
        asl a
        bit ptr
        zif_ne
            ora ptr
            eor #0xff
            and #0x7e
            zrepeat
                bcs skipthis
                lsr a
            zuntil_eq
                
            tya
            sta decode_tab - 0x16, x

            txa
            ora #0x80
            sta encode_tab, y

            iny
        skipthis:
        zendif
        inx
    zuntil_mi

	jmp .

; Given a row number in A, set ptr to the address of that
; row of video memory.
;
; Given a row 000abcde, the address is 000001cd eabab000.
; Preserves X and Y.
zproc calculate_screen_address
    pha
    lsr a
    and #0x03
    ora #0x04
    sta ptr+1
    pla

    lsr a           ; 0000abcd, e -> carry
    php
    and #0x0c       ; 0000ab00
    sta ptr+0
    lsr a
    lsr a           ; 000000ab
    ora ptr+0       ; 0000abab
    asl a
    asl a
    asl a
    asl a           ; abab0000
    plp
    ror a           ; eabab000
    sta ptr+0
    rts
zendproc

zproc clear_screen
    lda #24
    sta ptr1
    zrepeat
        lda ptr1
        jsr calculate_screen_address
        ldy #40
        lda #32|0x80
        zrepeat
            dey
            sta (ptr), y
        zuntil_eq

        dec ptr1
    zuntil_mi
    lda #0
    sta cursorx
    sta cursory
    rts
zendproc

.bss
cursorx:    .fill 1
cursory:    .fill 1

; Returns the next keyboard character in A.

zproc read_char
    zrepeat
        lda 0xc000
    zuntil_mi
    sta 0xc010
    and #0x7f
    rts
zendproc

; Writes the character in A.

zproc write_char
    cmp #13
    zif_eq
        lda #0
        sta cursorx
        rts
    zendif
    cmp #10
    beq write_nl

    tay
    lda cursory
    jsr calculate_screen_address
    tya
    ldy cursorx
    eor #0x80
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
    cmp #25
    zif_eq
        dec cursory
        jmp scroll_up
    zendif
    rts
zendproc

zproc scroll_up
    lda #0              ; current line
    zrepeat
        tax
        jsr calculate_screen_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        inx
        txa
        jsr calculate_screen_address ; ptr is source pointer

        pha             ; push current line
        ldy #39
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi
        pla

        cmp #24
    zuntil_eq

    ldy #39
    lda #32|0x80
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc bios
    rts
zendproc

.bss

encode_tab: .fill 64
decode_tab: .fill 20

; This must go last --- it's the three 6502 vectors.
.text
nmi_handler:
reset_handler:
irq_handler:
    rti

.text
    .word nmi_handler
    .word reset_handler
    .word irq_handler

; vim: filetype=asm sw=4 ts=4 et

