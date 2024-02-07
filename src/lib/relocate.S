; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65.inc"
#include "zif.inc"

.zeropage ptr

; Relocate an image. High byte of memory address is in A,
; zero page address is in X.

zproc bios_RELOCATE
    pha                 ; store memory start
    sta ptr+1
    lda #0
    sta ptr+0

    ; X preserved in next chunk
    ldy #COMHDR_REL_OFFSET ; add relocation table offset
    lda (ptr), y
    clc
    adc ptr+0
    sta reloptr$+0
    iny
    lda (ptr), y
    adc ptr+1
    sta reloptr$+1

    jsr relocate_loop$  ; relocate zero page (in X)

    lda #0
    sta ptr+0
    pla                 ; get memory start
    sta ptr+1
    tax
    ; fall through

    ; ptr points at the beginning of the image
    ; reloptr points at the relocation table
    ; x is value to add
relocate_loop$:
    ldy #0
    zloop
        reloptr$ = . + 1
        lda $ffff           ; get relocation byte
        inc reloptr$+0      ; add one to pointer
        zif_eq
            inc reloptr$+1
        zendif

        sta byte$
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #$0f
        zbreakif_eq
        jsr relocate$

        byte$ = . + 1
        lda #$ff
        and #$0f
        cmp #$0f
        zbreakif_eq
        jsr relocate$
    zendloop
    rts

; Enter with an offset in A.
; Preserves x and y.
relocate$:
    pha
    clc
    adc ptr+0
    sta ptr+0
    zif_cs
        inc ptr+1
    zendif
    pla

    cmp #$0e
    zif_ne
        ; ptr is pointing at the address to fix up.

        clc
        txa
        adc (ptr), y
        sta (ptr), y
    zendif
    rts
zendproc

; vim: filetype=asm sw=4 ts=4 et

