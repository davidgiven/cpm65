\ Screen driver tester for CP/M-65 - Copyright (C) 2023 Henrik Lofgren
\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"
.include "drivers.inc"

.expand 1

.zp cur_x, 1
.zp cur_y, 1
.zp max_x, 1
.zp max_y, 1
.zp cur_vis, 1
.zp style, 1
.zp ptr1, 2
.zp ptr2, 2
.zp kbd_blocking, 1
.zp spinner_pos, 1
.label string_init
.label string_a
.label chars_spinner
.label BIOS
.label SCREEN
.label update_cursor
.label printi
.label print16
.label putchar
.label print_h8

zproc start

    \ Find screen driver

    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV
    jsr BIOS
    
    \ Exit if no driver is found
    zif cs
        rts
    zendif
    sta SCREEN+1
    stx SCREEN+2

    \ Get screen size and initalize variables

    ldy #SCREEN_GETSIZE
    jsr SCREEN
    sta max_x
    stx max_y
    
    lda #1
    sta cur_vis
    ldy #SCREEN_SHOWCURSOR
    jsr SCREEN

    lda #0
    sta style
    sta spinner_pos
    
    lda #1
    sta kbd_blocking

help:
    \ Clear screen and print help
    ldy #SCREEN_CLEAR
    jsr SCREEN

    jsr printi
    .byte "CP/M-65 Screen driver tester\r\n\r\nScreen size: ", 0

    lda max_x
    ldx #0
    jsr print16

    jsr printi
    .byte ", ", 0

    lda max_y
    ldx #0
    jsr print16

    jsr printi
    .byte "\r\n", 0

    lda #<string_init
    ldx #>string_init
    ldy #BDOS_PRINTSTRING
    jsr BDOS

mainloop:
    \ Get and store current cursor position
    ldy #SCREEN_GETCURSOR
    jsr SCREEN
    sta cur_x
    stx cur_y

timeout:
    \ Show spinnig bar to test non-blocking keyboard read
    lda #39
    ldx #0
    ldy #SCREEN_SETCURSOR
    jsr SCREEN
    ldy spinner_pos
    iny
    tya
    cmp #4
    .zif eq
        ldy #0
    .zendif
    sty spinner_pos
    \ldx kbd_blocking
    \.zif ne
    \    lda #'*'
    \.zendif
    ldx kbd_blocking
    \.zif eq
        lda chars_spinner, y
    \.zendif
    ldy #SCREEN_PUTCHAR
    jsr SCREEN 

    lda #39
    ldx #1
    ldy #SCREEN_SETCURSOR
    jsr SCREEN
    lda #32
    ldy #SCREEN_PUTCHAR
    jsr SCREEN 
       
    lda cur_x
    ldx cur_y
    ldy #SCREEN_SETCURSOR
    jsr SCREEN

    \ Get and parse command
    
    ldy kbd_blocking
    .zif ne
        lda #0xff
        ldx #0x7f
    .zendif
    ldy kbd_blocking
    .zif eq
        lda #10          \ 0.1 second timeout
        ldx #0x0
    .zendif
    ldy #SCREEN_GETCHAR
    jsr SCREEN
    bcs timeout \ make sure we don't have consecutive key presses because of short timeouts
    
    \ Convert to uppercase
    cmp #0x61
    bcc case_done
    cmp #0x7a
    bcs case_done
    sec
    sbc #0x20    

case_done:
    \ Cursor left
    cmp #SCREEN_KEY_LEFT
    zif eq
        lda #'A'
    zendif
    cmp #'A'
    zif eq
        lda #0
        cmp cur_x
        zif ne
            dec cur_x
        zendif
        jsr update_cursor
        jmp mainloop
    zendif
    
    \ Cursor right
    cmp #SCREEN_KEY_RIGHT
    zif eq
        lda #'D'
    zendif
    cmp #'D'
    zif eq
        lda max_x
        cmp cur_x
        zif ne
            inc cur_x
        zendif
        jsr update_cursor
        jmp mainloop
    zendif
   
    \ Cursor up
    cmp #SCREEN_KEY_UP
    zif eq
        lda #'W'
    zendif 
    cmp #'W'
    zif eq
        lda #0
        cmp cur_y
        zif ne
            dec cur_y
        zendif
        jsr update_cursor
        jmp mainloop
    zendif
   
    \ Cursor down
    cmp #SCREEN_KEY_DOWN
    zif eq
        lda #'S'
    zendif 
    cmp #'S'
    zif eq
        lda max_y
        cmp cur_y
        zif ne
            inc cur_y
        zendif
        jsr update_cursor
        jmp mainloop
    zendif

    \ Put string
    cmp #'P'
    zif eq
        lda #<string_a
        ldx #>string_a
        ldy #SCREEN_PUTSTRING
        jsr SCREEN
        jmp mainloop
    zendif

    \ Put character
    cmp #'C'
    zif eq
        lda #'C'
        ldy #SCREEN_PUTCHAR
        jsr SCREEN
    zendif

    \ Toggle cursor
    cmp #'V'
    zif eq
        lda #0
        cmp cur_vis
        zif ne
            sta cur_vis
            ldy #SCREEN_SHOWCURSOR
            jsr SCREEN
            jmp mainloop 
        zendif
        lda #1
        sta cur_vis
        ldy #SCREEN_SHOWCURSOR
        jsr SCREEN
        jmp mainloop
    zendif

    \ Scroll up
    cmp #'U'
    zif eq
        ldy #SCREEN_SCROLLUP
        jsr SCREEN
        jmp mainloop
    zendif

    \ Scroll down
    cmp #'J'
    zif eq
        ldy #SCREEN_SCROLLDOWN
        jsr SCREEN
        jmp mainloop
    zendif

    \ Clear to end of line
    cmp #'L'
    zif eq
        ldy #SCREEN_CLEARTOEOL
        jsr SCREEN
        jmp mainloop
    zendif

    \ Toggle style
    cmp #'I'
    zif eq
        lda #0
        cmp style
        zif ne
            sta style
            ldy #SCREEN_SETSTYLE
            jsr SCREEN
            jmp mainloop
        zendif
        lda #1
        sta style
        ldy #SCREEN_SETSTYLE
        jsr SCREEN
        jmp mainloop
    .zendif
    
    \ Toggle keyboard read mode
    cmp #'B'
    .zif eq
        lda kbd_blocking
        .zif eq
            lda #1
            sta kbd_blocking
            jmp mainloop
        .zendif
        lda #0
        sta kbd_blocking
        jmp mainloop
        
    .zendif
  
    \ Draw line numbers
    cmp #'N'
    zif eq
        lda max_y
        sta ptr2
        zrepeat
            ldx ptr2
            lda max_x
            sec
            sbc #3
            ldy #SCREEN_SETCURSOR
            jsr SCREEN

            lda ptr2
            jsr print_h8

            dec ptr2
        zuntil mi
        jmp mainloop
    zendif

    \ Clear screen and print help 
    cmp #'H'
    beq help

    \ Clear screen and quit 
    cmp #'Q'
    zif eq
        ldy #SCREEN_CLEAR
        jsr SCREEN
        rts
    zendif
    
    jmp mainloop
zendproc

BIOS:
    jmp 0

SCREEN: 
    jmp 0    


zproc update_cursor
    lda cur_x
    ldx cur_y
    ldy #SCREEN_SETCURSOR
    jsr SCREEN

    rts
zendproc

\ Prints an inline string. The text string must immediately follow the
\ subroutine call.

zproc printi
    pla
    sta ptr1+0
    pla
    sta ptr1+1

    zloop
        ldy #1
        lda (ptr1), y
        zbreak eq
        zbreak mi
        jsr putchar

        inc ptr1+0
        zif eq
            inc ptr1+1
        zendif
    zendloop

    inc ptr1+0
    zif eq
        inc ptr1+1
    zendif
    inc ptr1+0
    zif eq
        inc ptr1+1
    zendif

    jmp (ptr1)
zendproc

\ Prints an 8-bit hex number in A with SCREEN_PUTCHAR.
zproc print_h8
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_hex4_number
    pla
print_hex4_number:
    and #$0f
    ora #'0'
    cmp #'9'+1
    zif cs
        adc #6
    zendif
    pha
    ldy #SCREEN_PUTCHAR
    jsr SCREEN
    pla
    rts
zendproc

\ Prints XA in decimal. Y is the padding char or 0 for no padding.

zproc print16
    ldy #0
zendproc
\ falls through
zproc print16padded
    sta ptr1+0
    stx ptr1+1
    sty ptr2+0

    .label dec_table
    .label skip
    .label justprint

    ldy #8
    zrepeat
        ldx #0xff
        sec
        zrepeat
            lda ptr1+0
            sbc dec_table+0, y
            sta ptr1+0

            lda ptr1+1
            sbc dec_table+1, y
            sta ptr1+1

            inx
        zuntil cc

        lda ptr1+0
        adc dec_table+0, y
        sta ptr1+0

        lda ptr1+1
        adc dec_table+1, y
        sta ptr1+1

        tya
        pha
        txa
        pha

        zif eq                     \ if digit is zero, check padding
            lda ptr2+0              \ get the padding character
            beq skip                \ if zero, no padding
            bne justprint           \ otherwise, use it
        zendif

        ldx #'0'                    \ printing a digit, so reset padding
        stx ptr2+0
        ora #'0'                    \ convert to ASCII
    justprint:
        jsr putchar
    skip:
        pla
        tax
        pla
        tay

        dey
        dey
    zuntil mi
    rts

dec_table:
   .word 1, 10, 100, 1000, 10000
zendproc

zproc putchar
    ldy #BDOS_CONIO
    jmp BDOS
zendproc

string_init:
    .byte "W,A,S,D or arrow keys - Move cursor\r\n"
    .byte "C - Put character\r\n"
    .byte "P - Put string\r\n"
    .byte "V - Toggle cursor visibility\r\n"
    .byte "U - Scroll up\r\n"
    .byte "J - Scroll down\r\n"
    .byte "L - Clear to End of Line\r\n"
    .byte "I - Toggle style\r\n"
    .byte "B - Toggle blocking/non-blocking read\r\n"
    .byte "H - Clear screen and print this help\r\n"
    .byte "N - Draw line numbers\r\n"
    .byte "Q - Quit\r\n"
    .byte 0

string_a:
    .byte "String"
    .byte 0

chars_spinner:
    .byte "-\\|/"
    .byte 0

