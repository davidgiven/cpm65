; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

ZEROPAGE

.zeropage ptr
.zeropage ptr1

ieee_has_buffered_char: .fill 1
ieee_buffered_char:     .fill 1

; Initialises the IEEE488 library.

zproc io_init, .init
    lda #0
    sta ieee_has_buffered_char
    sta ieee_buffered_char
    rts
zendproc

; Writes a single character in A with buffering.
; Preserves X and Y.

zproc ieee_write
    pha
    lda ieee_has_buffered_char
    zif ne
        lda ieee_buffered_char
        jsr ieee_putb
    zendif
    lda #1
    sta ieee_has_buffered_char
    pla
    sta ieee_buffered_char
    rts
zendproc

; Flushes the last character with EOI asserted.
; Preserves X and Y.

zproc ieee_flush
    lda ieee_has_buffered_char
    zif ne
        lda ieee_buffered_char
        jsr ieee_puteoib
        lda #0
        sta ieee_has_buffered_char
    zendif
    rts
zendproc

; See http://www.6502.org/users/andre/petindex/local/pet-io-2.txt
; https://www.pagetable.com/?p=1023
; http://www.primrosebank.net/computers/pet/documents/PET_and_the_IEEE488_Bus_text.pdf
; (appendix E)

; A is the secondary address (0xfX for OPEN).

zproc ieee_talk
    pha
    jsr ieee_computer_atn
    lda #0x48               ; TALK device 8
    jsr ieee_putb
    pla
    ora #0x60               ; SECOND
    jsr ieee_putb
    jmp ieee_computer_listening
zendproc

zproc ieee_untalk
    jsr ieee_computer_atn
    lda #0x5f               ; UNTALK
    jsr ieee_putb
    jmp ieee_computer_idle
zendproc

; A is the secondary address.

zproc ieee_listen
    pha
    jsr ieee_computer_atn
    lda #0x28               ; LISTEN device 8
    jsr ieee_putb
    pla
    ora #0x60               ; SECOND
    jsr ieee_putb
    jmp ieee_computer_talking
zendproc

zproc ieee_unlisten
    jsr ieee_flush
    jsr ieee_computer_atn
    lda #0x3f               ; UNLISTEN
    jsr ieee_putb
    jmp ieee_computer_idle
zendproc
