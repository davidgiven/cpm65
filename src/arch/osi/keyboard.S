; Ohio Scientific Instruments polled keyboard routines.
; Copyright © 2024 by Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

ZEROPAGE

cur_char:   .fill 1
wait_cntr:  .fill 1
last_char:  .fill 1
modifiers:  .fill 1
tmpval:     .fill 1

KEYBD = $df00

#ifdef OSI500
    .macro STA_KEYBD
        sta KEYBD
    .endm
    .macro LDA_KEYBD
        lda KEYBD
    .endm
#endif
#ifdef OSI600
    .macro STA_KEYBD
        eor #$ff
        sta KEYBD
        eor #$ff
    .endm
    .macro LDA_KEYBD
        lda KEYBD
        eor #$ff
    .endm
#endif

; ----------------------------------------------------------------------------

    .section .text, "ax"

scan_keyboard:

scan_again:
    lda #1                  ; Row mask
    ldy #0                  ; Row counter
    sty modifiers
    dey

    zloop
        STA_KEYBD

        pha
        LDA_KEYBD
        tax                     ; Key pressed in X
        pla

        cpx #0
        bne key_pressed

    next:
        iny                     ; Increase row counter
        asl
    zuntil_eq

    sta last_char               ; no key pressed...
    sta cur_char
    lda #$80
    rts

key_pressed:
    lsr                     ; check if row 0 ($01)

    zif_cs                  ; modifier key(s) or ESC pressed
        rol                 ; correct back to $01
        stx modifiers       ; save modifiers

        pha
        txa
        and #$20
        tax
        pla
        cpx #$20
        bne next

        lda #$1b                ; ESC
        bne lookup_done
    zendif

    lda matrix_index_tab,y
    sta tmpval              ; store "corrected" row*7

    txa                     ; A=column
    ldy #7                  ; convert to index 0-7
    zloop
        dey
        asl
    zuntil_cs

    tya                     ; A=column
    adc tmpval              ; add saved row*7 + 1 (carry always set)
    tay

    lda keyboard_matrix-1,y ; retrieve ASCII from table (-1 compensates C)

lookup_done:
    cmp cur_char
    zif_ne
        sta cur_char
        lda #2
        sta wait_cntr
        bne scan_again      ; branch always
    zendif

    dec wait_cntr
    beq debounce_done

    ldy #$10
    zloop
        ldx #$40
        zloop
            dex
        zuntil_eq
        dey
    zuntil_eq

    beq scan_again

debounce_done:
    ldx #$64                ; long delay on first character
    cmp last_char

    zif_eq
        ldx #$0f            ; shorter repeat rate
    zendif

    stx wait_cntr
    sta last_char
    sta tmpval

; Apply key modifiers --------------------------------------------------------

    lda modifiers
    tay                         ; save modifiers in Y

    and #7                      ; shift or caps
    tax
    zif_ne                      ; handle shift or caps
        lda tmpval
        cmp #$7f                ; RUB, case modifiers have no effect
        beq getkey_done

        cmp #$61                ; >= 0x61 always toupper()
        zif_cs
            eor #$20
            bne case_adjust_done
        zendif

        cpx #1                  ; just CAPS?
        beq case_adjust_done    ; for < 0x60, CAPS has no effect

        cmp #$30                ; special case, add #$10
        zif_eq
            clc
            adc #$10
            bne case_adjust_done
        zendif

        cmp #$21                ; don't adjust space (0x20) and below
        zif_cs
            eor #$10            ; all other keys with lshift or rshift
        zendif

    case_adjust_done:
        sta tmpval
    zendif

    tya                     ; restore saved modifiers
    and #$40                ; control key?
    zif_ne
        lda tmpval
        and #$1f
        rts
    zendif

getkey_done:
    lda tmpval
    rts

; ----------------------------------------------------------------------------

keyboard_matrix:
    .ascii "p;/ zaq"
    .ascii ",mnbvcx"
    .ascii "kjhgfds"
    .ascii "iuytrew"
    .byte $0d,$0a       ; removed unused columns
    .ascii "ol."
    .byte $7F           ; idem      (RUB as $7f instead of $5f)
    .ascii "-:098"
    .ascii "7654321"

matrix_index_tab:
    .byte 0, 7, 14, 21, 26, 32, 39 ; corrected indeces for removed unused keys

; vim: filetype=asm sw=4 ts=4 et
