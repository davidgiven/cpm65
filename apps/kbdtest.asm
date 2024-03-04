\ Keyboard driver tester for CP/M-65
\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"
.include "drivers.inc"

.zp esccount, 1
.zp ptr1, 2

.label BIOS
.label SCREEN
.label printi
.label putchar
.label print_hex_number

.zproc start

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
    .zif cs
        rts
    .zendif
    sta SCREEN+1
    stx SCREEN+2

    \ Go!
    jsr printi
    .byte "Type now. Press escape three times to quit.", 13, 10, 0
    lda #0
    sta esccount

    .zloop
        .zrepeat
            ldy #SCREEN_GETCHAR
            jsr SCREEN
        .zuntil cc
        
        cmp #27
        .zif eq
            inc esccount
            ldx esccount
            cpx #3
            .zbreak eq
        .zendif
        cmp #27
        .zif ne
            ldx #0
            stx esccount
        .zendif
        
        pha
        lda #'['
        jsr putchar
        pla
        jsr print_hex_number
        lda #']'
        jsr putchar
    .zendloop

    lda #13
    jsr putchar
    lda #10
    jmp putchar
.zendproc

\ Prints an 8-bit hex number in A.
.zproc print_hex_number
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
    .zif cs
        adc #6
    .zendif
    pha
    jsr putchar
    pla
    rts
.zendproc

\ Prints an inline string. The text string must immediately follow the
\ subroutine call.

.zproc printi
    pla
    sta ptr1+0
    pla
    sta ptr1+1

    .zloop
        ldy #1
        lda (ptr1), y
        .zbreak eq
        .zbreak mi
        jsr putchar

        inc ptr1+0
        .zif eq
            inc ptr1+1
        .zendif
    .zendloop

    inc ptr1+0
    .zif eq
        inc ptr1+1
    .zendif
    inc ptr1+0
    .zif eq
        inc ptr1+1
    .zendif

    jmp (ptr1)
.zendproc

.zproc putchar
    ldy #BDOS_CONIO
    jmp BDOS
.zendproc

BIOS:
    jmp 0

SCREEN: 
    jmp 0    
