; ---------------------------------------------------------------------------
;
; nano6502 LED tester, blinks onboard LEDs for 2 seconds
;
; Copyright (C) 2024 Henrik Löfgren
; This file is licensed under the terms of the 2-cluse BSD license. Please
; see the COPYING file in the root project directory for the full test.
;
; ---------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"

; Color RAM bank addresses
IO_page_reg = $00
IO_page_LED = $02
IO_page_timer = $05

timer_set_lsb = $fe02
timer_set_msb = $fe03
timer_start_strobe = $fe01
timer_idle = $fe00
timer_reset_strobe = $fe04

led_row = $fe00
led_b = $fe03

ZEROPAGE

leds: .fill 1

zproc main
    ldx #$0a 
    lda #$11
    sta leds
loop:
    lda #IO_page_LED
    sta IO_page_reg

    lda #30
    sta led_b

    lda leds
    sta led_row
    ror
    sta leds
    jsr delay
    lda #IO_page_LED
    sta IO_page_reg

    lda #00
    sta led_b

    lda leds
    sta led_row
    ror
    sta leds

    jsr delay

    dex
    bne loop

    lda #IO_page_LED
    sta IO_page_reg    

    lda #00
    sta led_row
     
	rts
zendproc

zproc delay
    lda #IO_page_timer
    sta IO_page_reg
    lda #$0A ; 0.1 sec
    sta timer_set_lsb
    lda #$00
    sta timer_set_msb
    sta timer_reset_strobe
    sta timer_start_strobe
delaywait:
    lda timer_idle
    beq delaywait
    rts 
zendproc
