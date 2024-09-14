; ---------------------------------------------------------------------------
;
; nano6502 baudrate utility
;
; Copyright (C) 2024 Henrik Löfgren
; This file is licensed under the terms of the 2-cluse BSD license. Please
; see the COPYING file in the root project directory for the full test.
;
; ---------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"

; UART IO bank addresses
IO_page_reg = $00
IO_page_UART = $01
uart_b_baudrate = $fe08

zproc main
    lda #<banner
    ldx #>banner
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    jsr print_baudrate

    lda #<query
    ldx #>query
    ldy #BDOS_WRITE_STRING
    jsr BDOS

get_selection:
    ldy #BDOS_CONSOLE_INPUT
    jsr BDOS
    
    cmp #$2F
    zif_cs
        cmp #$36
        bcc ok_selection
        
        lda #<br_invalid
        ldx #>br_invalid
        ldy #BDOS_WRITE_STRING
        jsr BDOS

        lda #<crlf
        ldx #>crlf
        ldy #BDOS_WRITE_STRING
        jsr BDOS
    zendif
    jmp get_selection
ok_selection:
    sec
    sbc #$30
    
    ldx #IO_page_UART
    stx IO_page_reg
    
    sta uart_b_baudrate

    lda #<updated
    ldx #>updated
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    jsr print_baudrate

	rts
zendproc

zproc print_baudrate
    lda #<current
    ldx #>current
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    lda #IO_page_UART
    sta IO_page_reg
    
    lda uart_b_baudrate
    cmp #0
    zif_eq
        lda #<br_4800
        ldx #>br_4800
        jmp print_br
    zendif
    
    cmp #1
    zif_eq
        lda #<br_9600
        ldx #>br_9600
        jmp print_br
    zendif

    cmp #2
    zif_eq
        lda #<br_19200
        ldx #>br_19200
        jmp print_br
    zendif

    cmp #3
    zif_eq
        lda #<br_38400
        ldx #>br_38400
        jmp print_br
    zendif

    cmp #4
    zif_eq
        lda #<br_57600
        ldx #>br_57600
        jmp print_br
    zendif

    cmp #5
    zif_eq
        lda #<br_115200
        ldx #>br_115200
        jmp print_br
    zendif
    
    lda #<br_invalid
    ldx #>br_invalid
    
print_br:
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    lda #<crlf
    ldx #>crlf
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    rts
zendproc

    .data
banner:
    .ascii "nano6502 baudrate utility"
    .byte 13,10
    .ascii "-------------------------"
    .byte 13,10,0

current:
    .ascii "Current UART B baudrate: "
    .byte 0

br_4800:
    .ascii "4800"
    .byte 0

br_9600:
    .ascii "9600"
    .byte 0

br_19200:
    .ascii "19200"
    .byte 0

br_38400:
    .ascii "38400"
    .byte 0

br_57600:
    .ascii "57600"
    .byte 0

br_115200:
    .ascii "115200"
    .byte 0

br_invalid:
    .ascii "Invalid setting"
    .byte 0

crlf:
    .byte 13, 10, 0

query:
    .byte 13, 10
    .ascii "Select new baudrate: "
    .byte 13, 10
    .ascii "[0] 4800, [1] 9600, [2] 19200, [3] 38400, [4] 57600, [5] 115200"
    .byte 13, 10, 0

updated:
    .byte 13, 10
    .ascii "Baudrate setting updated."
    .byte 13,10,0
