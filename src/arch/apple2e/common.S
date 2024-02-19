#include "zif.inc"
#include "apple2e.inc"
#include "cpm65.inc"

ZEROPAGE

.global ptr
.global ptr1

ptr:    .word 0
ptr1:   .word 0

.data

; Writes the character in A.

zproc conout
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
        jsr prepare_for_screen_write
        lda #0xa0
        sta (ptr), y
        rts
    zendif
    cmp #10
    beq write_nl

    pha
    jsr prepare_for_screen_write
    pla
    eor #0x80
    sta (ptr), y

    inc cursorx
    lda cursorx
    cmp #SCREEN_WIDTH
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
    cmp #SCREEN_HEIGHT
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
        jsr calculate_screen_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        inx
        txa
        jsr calculate_screen_address ; ptr is source pointer

        ldy #39
        zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
            sta SCREEN_PAGE2OFF
            lda (ptr), y
            sta (ptr1), y
            sta SCREEN_PAGE2ON
#endif
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #23
    zuntil_eq

    ldy #39
    lda #32|0x80
    zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
        sta SCREEN_PAGE2OFF
        sta (ptr), y
        sta SCREEN_PAGE2ON
#endif
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

; Sets ptr to the current cursor row address; also sets up the page stuff.
; Leaves Y to the screen line offset.

zproc prepare_for_screen_write
    lda cursory
    jsr calculate_screen_address
    lda cursorx
#if TTY_MODE == TTY_MODE_80COLUMNS
    lsr a
#endif
    tay
    lda #0
    rol
    eor #1
    tax
#if TTY_MODE == TTY_MODE_80COLUMNS
    sta SCREEN_PAGE2OFF, x
#endif
    rts
zendproc

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
#if TTY_MODE == TTY_MODE_80COLUMNS
            sta SCREEN_PAGE2ON
            sta (ptr), y
            sta SCREEN_PAGE2OFF
#endif
            sta (ptr), y
        zuntil_eq

        dec ptr1
    zuntil_mi
    lda #0
    sta cursorx
    sta cursory
    rts
zendproc

zproc cursor_on
    ldx cursorvisible
    cpx #1
    zif_eq
        jsr prepare_for_screen_write
        lda (ptr), y
        sta cursork
        lda #0x60           ; flashing block
        sta (ptr), y
    zendif
    rts
zendproc

zproc cursor_off
    ldx cursorvisible
    cpx #1
    zif_eq
        tax
        lda cursork
        sta (ptr), y
        txa
    zendif
    rts
zendproc

.bss

.global cursorx
.global cursory
.global cursork
.global cursorvisible
.global cursorstylemask
.global conout
cursorx:            .fill 1
cursory:            .fill 1
cursork:            .fill 1
cursorvisible:      .fill 1
cursorstylemask:    .fill 1
