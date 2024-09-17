; ---------------------------------------------------------------------------
;
; nano6502 text color setting utility
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
IO_page_video = $04

video_fg_r = $fe10
video_fg_g = $fe11
video_fg_b = $fe12
video_bg_r = $fe13
video_bg_g = $fe14
video_bg_b = $fe15

ZEROPAGE

bg_color: .fill 3

zproc main
    ; Read hex color values from command line

    ldx #1
    ldy #0

read_bg:
    ; Read first digit
	lda cpm_fcb,x

    ; Convert
	jsr hexconv
    ; Exit if not valid hex
    zif_cs
	    rts
    zendif

    ; Store and shift to high nibble
	asl
    asl
    asl
    asl
    sta bg_color,y
    
    inx
    ; Read second digit
    lda cpm_fcb,x

    ; Convert
    jsr hexconv
    ; Exit if not valid hex
    zif_cs
	    rts
    zendif
    ; Combine with low nibble
    ora bg_color,y
    sta bg_color,y

    iny
    inx
    cpx #7
    bne read_bg

    ; Set color
    lda #IO_page_video
    sta IO_page_reg
    lda bg_color
    sta video_bg_r
    lda bg_color+1
    sta video_bg_g
    lda bg_color+2
    sta video_bg_b

	rts
zendproc

; Convert ASCII hex digit to number, print usage if not valid data
zproc hexconv
    cmp #'0'
    bcs hexconv_a
    jmp print_usage
hexconv_a:
    cmp #'9'+1
    bcs hexconv_b
    sec
    sbc #0x30
    clc
    rts 
hexconv_b:
    cmp #'F'+1
    bcc hexconv_c
    jmp print_usage
hexconv_c:
    sec
    sbc #0x37
    clc
    rts
print_usage:
    lda #<usage_string
    ldx #>usage_string
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    sec
    rts
zendproc

usage_string:
    .ascii "colorbg - set background color on the nano6502 computer"
    .byte 13, 10
    .ascii "Usage: colorbg RRGGBB. Eg. color FFFFFF for white background."
    .byte 13, 10, 0
