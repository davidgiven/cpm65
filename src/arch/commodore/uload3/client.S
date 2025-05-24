#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "c64.inc"

ZEROPAGE

uloadtmp:   .fill 1

zproc uload3_init
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

zproc uload3_send
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
    zuntil vc               ; with CLK low

    lda CIA2_PA             ; pull DATA low to acknowledge
    ora #0x20
    sta CIA2_PA

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

    lda CIA2_PA               ; release DATA to signal that data is coming
    ;ora #0x20
    and #0xdf
    sta CIA2_PA

    lda sendtab, y          ; send the first two bits
    sta CIA2_PA

    lsr
    lsr
    and #%00110000          ; send the next two
    sta CIA2_PA

    pla                     ; get the next nybble
    and #0x0f
    tay
    lda sendtab, y
    sta CIA2_PA

    lsr                     ; send the last two bits
    lsr
    and #%00110000
    sta CIA2_PA

    nop                     ; slight delay, and...
    nop
    lda uloadtmp            ; restore CIA2_PA and CIA_DA
    sta CIA2_PA
    lda #0x3f
    sta CIA2_DA

    cli
    rts
zendproc

zlproc sendtab, .aligned.16
    .byte 0x00, 0x80, 0x20, 0xa0
    .byte 0x40, 0xc0, 0x60, 0xe0
    .byte 0x10, 0x90, 0x30, 0xb0
    .byte 0x50, 0xd0, 0x70, 0xf0
zendproc

; Receives A from the drive. Preserves X and Y.

zproc uload3_recv
    zrepeat
        bit CIA2_PA           ; wait for drive to signal data ready with
    zuntil pl                 ; DATA low

    lda CIA2_PA               ; drop CLK to acknowledge
    ora #0x10
    sta CIA2_PA

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

    lda CIA2_PA
    and #0xef
    sta CIA2_PA             ; set CLK low to signal that we are receiving
pal_delay_insn:
    bne 1f                  ; 3 cycles, for NTSC; replaced with a 2-cycle beq for PAL
1:
    nop

    and #3
    sta 1f+1
    sta CIA2_PA             ; set CLK high to be able to read the
    lda CIA2_PA             ; bits the diskdrive sends
    lsr
    lsr
    eor CIA2_PA
    lsr
    lsr
    eor CIA2_PA
    lsr
    lsr
1:
    eor #0x00
    eor CIA2_PA

    cli
    rts
zendproc

; Loads the response from an F command into ptr.

zproc uload3_recv_file
    zrepeat
        jsr uload3_recv
        zbreakif eq
        cmp #0xff
        zif eq
            ; Error!
            sec
            rts
        zendif

        sta uloadtmp
        ldy #0
        zrepeat
            jsr uload3_recv
            sta (ptr), y
            iny
            cpy uloadtmp
        zuntil eq

        clc
        lda ptr+0
        adc uloadtmp
        sta ptr+0
        zif cs
            inc ptr+1
        zendif

        lda uloadtmp
        cmp #0xfe
    zuntil ne
    rts
zendproc
