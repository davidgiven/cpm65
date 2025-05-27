#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "c64.inc"
#include "wait.inc"

ZEROPAGE

.global uloadtmp
uloadtmp:   .fill 1

zproc yload_init
    sei

    lda #0xff                        ; wait for line 255
    zrepeat
        cmp SCREEN_RASTER
    zuntil eq

    lda #8                           ; wait for a line with low byte 8
    zrepeat
        cmp SCREEN_RASTER
    zuntil eq

    bit SCREEN_CONTROL              ; if MSB of raster set, this is line 263, and PAL
    zif mi
        lda #0xf0                   ; BEQ, 2 cycles
        sta pal_delay_insn
    zendif

    cli
    rts
zendproc

; Sends A to the drive. Preserves X (but not Y).

zproc yload_send
    pha
    lsr
    lsr
    lsr
    lsr
    tay

    lda CIA2_PA
    and #7
    sta CIA2_PA
    sta uloadtmp
    eor #0x07
    ora #0x38
    sta CIA2_DA

    zrepeat
        bit CIA2_PA         ; wait for drive to signal ready to receive
    zuntil vc               ; with CLK low (asserted)

    set1 CIA2_PA, 0x20      ; assert DATA to acknowledge

    zrepeat
        bit CIA2_PA         ; wait for drive to release CLK
    zuntil vs

    ; Wait until a badline won't screw up the timing.

    sei
    zrepeat
        lda SCREEN_CONTROL       ; wait until a badline won't screw up
        clc                     ; the timing
        sbc SCREEN_RASTER
        and #7
    zuntil ne

    set0 CIA2_PA, 0x20            ; release DATA to signal that data is coming

    ; The CIA2_PA output layout is dcDCAxxx. dc is input, and writing here does
    ; nothing. DC is output. We map each nibble to a four-bit value which is
    ; written once to dcDC, then shifted right two bits and written again.
    ;
    ; The timing is critical for sending the bit pairs: 4, 14, 30, 40.

/* 0 */  lda sendtab, y          ; send the first two bits
/* 4 */  sta CIA2_PA

/* 8 */  lsr a
/* 10 */ lsr a
/* 12 */ and #%00110000          ; send the next two
/* 14 */  sta CIA2_PA

/* 18 */ pla                     ; get the next nybble
/* 22 */ and #0x0f
/* 24 */ tay
/* 26 */ lda sendtab, y
/* 30 */ sta CIA2_PA

/* 34 */ lsr a                   ; send the last two bits
/* 36 */ lsr a
/* 38 */ and #%00110000
/* 40 */ sta CIA2_PA

/* 44 */ WAIT4                   ; slight delay, and...
/* 48 */
         
    lda uloadtmp            ; restore CIA2_PA and CIA_DA
    sta CIA2_PA
    lda #0x3f
    sta CIA2_DA

    cli
    rts
zendproc

zlproc sendtab, .aligned.16
    ; Bit ordering is %CcDd; this makes it easier to assemble the values on the
    ; 1541.

    ;      dcDC
    .byte %00000000 ; 0
    .byte %10000000 ; 1
    .byte %00100000 ; 2
    .byte %10100000 ; 3
    .byte %01000000 ; 4
    .byte %11000000 ; 5
    .byte %01100000 ; 6
    .byte %11100000 ; 7
    .byte %00010000 ; 8
    .byte %10010000 ; 9
    .byte %00110000 ; a
    .byte %10110000 ; b
    .byte %01010000 ; c
    .byte %11010000 ; d
    .byte %01110000 ; e
    .byte %11110000 ; f
zendproc

; Receives A from the drive. Preserves X and Y.

zproc yload_recv
    zrepeat
        bit CIA2_PA           ; wait for drive to signal data ready with
    zuntil pl                 ; DATA asserted

    set1 CIA2_PA, 0x10        ; assert CLK to acknowledge

    zrepeat
        bit CIA2_PA           ; wait for drive to release DATA
    zuntil mi

    ; Wait until a badline won't screw up the timing.

    sei
    zrepeat
        lda SCREEN_CONTROL
        clc
        sbc SCREEN_RASTER
        and #7
    zuntil ne

    set0 CIA2_PA, 0x10          ; release CLK to signal that we are receiving

    ; The layout of the C64 CIA2_PA port is %DCxxxxxx.
    ; The critical points here are cycles 15, 23, 31 and 41.
pal_delay_insn:
/* 0 */  bne .+2                 ; 3 cycles, for NTSC; replaced with a 2-cycle beq for PAL
/* 3 */  WAIT2
     
/* 5 */  and #3
/* 7 */  sta 1f+1
/* 11 */ sta CIA2_PA             ; set CLK high to be able to read the
/* 15 */ lda CIA2_PA             ; bits the diskdrive sends
/* 19 */ lsr a
/* 21 */ lsr a
/* 23 */ eor CIA2_PA
/* 27 */ lsr a
/* 29 */ lsr a
/* 31 */ eor CIA2_PA
/* 35 */ lsr a
/* 37 */ lsr a
     1:
/* 39 */ eor #0x00
/* 41 */ eor CIA2_PA
/* 45 */

    cli
    rts
zendproc
