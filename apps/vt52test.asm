\ Screen driver tester for CP/M-65 - Copyright (C) 2023 Henrik Lofgren
\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"
.include "drivers.inc"

.expand 1

.label string_init
.label string_up
.label string_down
.label string_right
.label string_left
.label string_home
.label string_rev_lf
.label string_cl_end
.label string_cl_line
.label string_cur_addr 

.zproc start

help:
    \ Print help
    lda #<string_init
    ldx #>string_init
    ldy #BDOS_PRINTSTRING
    jsr BDOS

mainloop:
    \ Get and parse command
    ldx #0xfd
    ldy #BDOS_CONIO
    jsr BDOS
    
    \ Convert to uppercase
    cmp #0x61
    bcc case_done
    cmp #0x7a
    bcs case_done
    sec
    sbc #0x20    

case_done:
    \ Cursor left
    cmp #'A'
    .zif eq
        lda #<string_left
        ldx #>string_left
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif
    
    \ Cursor right
    cmp #'D'
    .zif eq
        lda #<string_right
        ldx #>string_right
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif
   
    \ Cursor up 
    cmp #'W'
    .zif eq
        lda #<string_up
        ldx #>string_up
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif
   
    \ Cursor down 
    cmp #'S'
    .zif eq
        lda #<string_down
        ldx #>string_down
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif

    \ Cursor home
    cmp #'H'
    .zif eq
        lda #<string_home
        ldx #>string_home
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif

    \ Reverse linefeed
    cmp #'I'
    .zif eq
        lda #<string_rev_lf
        ldx #>string_rev_lf
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif

    \ Clear to end of screen
    cmp #'J'
    .zif eq
        lda #<string_cl_end
        ldx #>string_cl_end
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif

    \ Clear to end of line
    cmp #'K'
    .zif eq
        lda #<string_cl_line
        ldx #>string_cl_line
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif

    \ Cursor addressing
    cmp #'Y'
    .zif eq
        lda #<string_cur_addr
        ldx #>string_cur_addr
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        jmp mainloop
    .zendif

    \ Tab
    cmp #'T'
    .zif eq
        lda #0x09
        ldy #BDOS_CONOUT
        jsr BDOS
        jmp mainloop
    .zendif

    \ Backspace
    cmp #'B'
    .zif eq
        lda #0x08
        ldy #BDOS_CONOUT
        jsr BDOS
        jmp mainloop
    .zendif
  
    \ CR
    cmp #'C'
    .zif eq
        lda #0x0d
        ldy #BDOS_CONOUT
        jsr BDOS
        jmp mainloop
    .zendif
    
    \ LF
    cmp #'L'
    .zif eq
        lda #0x0a
        ldy #BDOS_CONOUT
        jsr BDOS
        jmp mainloop
    .zendif

    \ Print help 
    cmp #'P'
    beq help

    \ Quit 
    cmp #'Q'
    .zif eq
        rts
    .zendif
    
    jmp mainloop
.zendproc

string_init:
    .byte "CP/M-65 VT52 driver tester\r\n\r\n"
    .byte "W,A,S,D - Move cursor\r\n"
    .byte "H - Cursor home\r\n"
    .byte "I - Reverse linefeed\r\n"
    .byte "J - Clear to end of screen\r\n"
    .byte "K - Clear to end of line\r\n"
    .byte "Y - Cursor addressing\r\n"
    .byte "T - Tab\r\n"
    .byte "B - Backspace\r\n"
    .byte "C - Carriage return\r\n"
    .byte "L - Linefeed\r\n"
    .byte "P - Print this help\r\n"
    .byte "Q - Quit\r\n"
    .byte 0

string_up:
    .byte 27,'A',0
string_down:
    .byte 27,'B',0
string_right:
    .byte 27,'C',0
string_left:
    .byte 27,'D',0
string_home:
    .byte 27,'H',0
string_rev_lf:
    .byte 27,'I',0
string_cl_end:
    .byte 27,'J',0
string_cl_line:
    .byte 27,'K',0
string_cur_addr:
    .byte 27,'Y',46,63,0

