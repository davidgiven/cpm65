; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "bdos.inc"

.data
buffered_key: 			.byte 0
column_position:        .byte 0

zproc bdos_CONIN
    lda buffered_key
    zif_eq
        jsr bios_CONIN
        tax
    zelse
        ldx #0
        stx buffered_key
    zendif
    txa
    pha
    cmp #31
    zif_cs
        jsr bdos_CONOUT
    zendif
    rts
zendproc

; Prints the character in param+0.
zproc bdos_CONOUT
    lda param+0
    ; fall through
zendproc
zproc internal_CONOUT
    pha
    jsr bios_CONST
    cmp #0
    zif_ne                  ; is there a key pending?
        jsr bios_CONIN      ; read it
        cmp #19             ; was it ^S?
        zif_eq
            jsr bios_CONIN  ; wait for another key press
            cmp #3
            beq reboot$
            jmp continue$
        zendif
        cmp #3              ; was it ^C?
        beq reboot$
        sta buffered_key
    zendif
continue$:
    pla

    ; Actually print it.

    jsr bios_CONOUT

    ; Compute column position?

    ldx column_position
    cmp #8
    beq backspace$
    cmp #127
    beq backspace$
    cmp #9
    zif_eq
        inx
        tax
        and #<~7
        sta column_position
        rts
    zendif
    cmp #32
    bcc zero_column$
    inx
    jmp exit$

backspace$:
    dex
    bpl exit$
zero_column$:
    ldx #0
exit$:
    stx column_position
    rts
reboot$:
    jmp bdos_EXIT
zendproc

zproc bdos_GETCONSOLESTATUS
    lda buffered_key
    zif_eq
        jsr bios_CONST
    zendif
    clc
    rts
zendproc

; If param+1 == $ff, returns a character without waiting and without echo.
; If param+1 == $fd, returns a character while waiting and without echo.
; If otherwise, prints param+0.

zproc bdos_DIRECTIO
    ldx param+1
    cpx #$ff    
    zif_eq
        lda buffered_key
        ; A is either a character, or zero
        zif_eq
            jsr bios_CONST
            cmp #$ff
            zif_eq
                jsr bios_CONIN
            zendif
            ; A is either a character, or zero
        zendif
        clc
        rts
    zendif

    cpx #$fd
    zif_eq
        jmp bios_CONIN
    zendif

    lda param+0
    jsr bios_CONOUT
    clc
    rts
zendproc

zproc internal_WRITESTRING
    sta param+0
    stx param+1
zendproc
	; fall through
zproc bdos_WRITESTRING
    zloop
        ldy #0
        lda (param), y
        zbreakif_eq
        cmp #'$'
        zbreakif_eq

        jsr internal_CONOUT

        inc param+0
        zif_eq
            inc param+1
        zendif
    zendloop
    rts
zendproc

; Read a line from the keyboard. Buffer is at param, size at param+0.
zproc bdos_READLINE
    start_column_position = temp+0
    buffer_pos = temp+1
    buffer_max = temp+2
    count = temp+3
    current_column_position = temp+4

    lda column_position
    sta start_column_position
    sta current_column_position
    lda #2
    sta buffer_pos
    ldy #0
    lda (param), y
    sta buffer_max

    zloop
        ; Read a key without echo.

        lda buffered_key
        zif_eq
            jsr bios_CONIN
            tax
        zendif
        ldx #0
        stx buffered_key

        ; Delete?

        cmp #8
        zif_eq
            lda #127
        zendif
        cmp #127
        zif_eq
            ldy buffer_pos
            cpy #2
            zif_ne
                dec buffer_pos
                dec current_column_position
                jsr bios_CONOUT
            zendif
            zcontinue
        zendif

        ; Reboot?

        cmp #3
        zif_eq
            ldy buffer_pos
            cpy #2
            zif_eq
                jmp bdos_EXIT
            zendif
            zcontinue
        zendif

        ; Retype line?

        cmp #18
        zif_eq
            jsr indent_new_line
            ldy #1
            sty count
            zloop
                ldy count
                cpy buffer_pos
                zbreakif_eq

                lda (param), y
                jsr bios_CONOUT
                inc current_column_position
                inc count
            zendloop
            zcontinue
        zendif

        ; Delete line?

        cmp #21
        zif_eq
            lda #'#'
            jsr bios_CONOUT
            jsr indent_new_line

            lda #2
            sta buffer_pos
            zcontinue
        zendif

        ; Finished?

        cmp #13
        zbreakif_eq
        cmp #10
        zbreakif_eq

        ; Graphic character?

        cmp #32
        zif_cs
            ldy buffer_max
            cpy buffer_pos
            zif_cs
                ldy buffer_pos
                sta (param), y
                jsr bios_CONOUT
                inc buffer_pos
                inc current_column_position
            zendif
        zendif
    zendloop

    lda #13
    jsr internal_CONOUT
    ldx buffer_pos
    dex
    dex
    txa
    ldy #1
    sta (param), y
    rts

indent_new_line:
    jsr bios_NEWLINE
    lda #0
    sta current_column_position
    zloop
        lda current_column_position
        cmp start_column_position
        zbreakif_eq
        lda #' '
        jsr bios_CONOUT
        inc current_column_position
    zendloop
    rts
zendproc
