#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "vic20.inc"
#include "wait.inc"

ZEROPAGE

.global uloadtmp
uloadtmp:   .fill 1

zproc io_init
    lda VICPALNTSC
    cmp #0x0c
    zif eq
        ; The NTSC VIC20 runs at 1.022727 MHz, the same as the NTSC C64; but the
        ; PAL VIC20 runs at 1.1108404 MHz, significantly faster than the
        ; 0.985248 MHz PAL C64.
        ; 
        ; That is 1.0861 times the speed of the NTSC VIC20, so that every 10
        ; NTSC cycles we get 11 PAL cycles.

        ; PAL
    zendif
    rts
zendproc

; Sends A to the drive. Preserves X (but not Y).

zproc yload_send
    tay
    txa
    pha

    lda #VIA1_PA_CLOCK_IN
    zrepeat
        bit VIA1_DRA        ; wait for drive to signal ready to receive
    zuntil eq               ; with CLK asserted

    set1 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT ; assert DATA to acknowledge

    lda #VIA1_PA_CLOCK_IN
    zrepeat
        bit VIA1_DRA        ; wait for drive to release CLK
    zuntil ne

    ; The VIC20's data output bits are nothing like as conveniently laid out as
    ; the C64. For each bit pair, the PCR looks like:
    ;     %11D111C0
    ;
    ; The timing is critical for sending the bit pairs: 4, 14, 30, 40.
    ; This is too much to calculate on the fly, so we have to precalculate everything.

    tya
    asl a
    and #%00011110
    tax
    lda sendtab+0, x
    pha
    lda sendtab+1, x
    pha
    
    tya
    lsr a
    lsr a
    lsr a
    and #%00011110
    tax
    lda sendtab+0, x
    pha
    lda sendtab+1, x
    pha

    ; Begin time-critical part.
    ;

    lda VICPALNTSC
    cmp #0x0c
    zif eq
        ; PAL

        set0 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT
        /* 0 */  pla
        /* 4 */  sta VIA2_PCR
        /* 8 */  WAIT4
        /* 11 */ pla
        /* 15 */ sta VIA2_PCR
        /* 19 */ WAIT10
        /* 29 */ pla
        /* 33 */ sta VIA2_PCR
        /* 37 */ WAIT3
        /* 40 */ pla
        /* 44 */ sta VIA2_PCR
        /* 48 */ WAIT4
        /* 52 */
    zelse
        set0 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT
        /* 0 */  pla
        /* 4 */  sta VIA2_PCR
        /* 8 */  WAIT2
        /* 10 */ pla
        /* 14 */ sta VIA2_PCR
        /* 18 */ WAIT8
        /* 26 */ pla
        /* 30 */ sta VIA2_PCR
        /* 34 */ WAIT2
        /* 36 */ pla
        /* 40 */ sta VIA2_PCR
        /* 44 */ WAIT4
        /* 48 */
    zendif

    ; Release DATA and CLOCK because we're done

    set0 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT|VIA2_PCR_CA2_CLOCK_OUT

    pla
    tax
    rts
zendproc

zlproc sendtab, .aligned.32
    ;      %..D...C.
    D0C0 = %11011100 ; 0xdc
    D0C1 = %11011110 ; 0xde
    D1C0 = %11111100 ; 0xfc
    D1C1 = %11111110 ; 0xfe

    ; In order to more closely map the C64 tables, the first nibble to be sent
    ; is the _second_ item in the table.  Bit ordering is %CcDd; this makes it
    ; easier to assemble the values on the 1541.

    ;      4 6   5 7 (high nibble)
    ;      0 2   1 3 (low nibble)
    ;      d c   D C
    .byte D0C0, D0C0 ; 0
    .byte D1C0, D0C0 ; 1
    .byte D0C0, D1C0 ; 2
    .byte D1C0, D1C0 ; 3
    .byte D0C1, D0C0 ; 4
    .byte D1C1, D0C0 ; 5
    .byte D0C1, D1C0 ; 6
    .byte D1C1, D1C0 ; 7
    .byte D0C0, D0C1 ; 8
    .byte D1C0, D0C1 ; 9
    .byte D0C0, D1C1 ; a
    .byte D1C0, D1C1 ; b
    .byte D0C1, D0C1 ; c
    .byte D1C1, D0C1 ; d
    .byte D0C1, D1C1 ; e
    .byte D1C1, D1C1 ; f
zendproc

; Receives A from the drive. Preserves X and Y.

zproc yload_recv
    txa
    pha
    tya
    pha

    lda #VIA1_PA_DATA_IN
    zrepeat
        bit VIA1_DRA        ; wait for drive to signal ready to receive
    zuntil eq               ; with DATA asserted

    set1 VIA2_PCR, VIA2_PCR_CA2_CLOCK_OUT

    lda #VIA1_PA_DATA_IN
    zrepeat
        bit VIA1_DRA        ; wait for drive to signal data ready with
    zuntil ne               ; DATA released

    ; Begin time-critical part

    ; The layout of the VIC20 input bits is %xxxxxxDC, which isn't that
    ; different from the C64's of %DCxxxxxx.

    lda VICPALNTSC
    cmp #0x0c
    zif eq
        ; PAL
        
        set0 VIA2_PCR, VIA2_PCR_CA2_CLOCK_OUT
        /* 0 */  WAIT12
        /* 9 */  WAIT3
        /* 19 */ ldx VIA1_PA        ; %xxxxxx10
        /* 14 */ WAIT5
        /* 28 */ ldy VIA1_PA        ; %xxxxxx32
        /* 23 */ WAIT5
        /* 37 */ lda VIA1_PA
        /* 41 */ pha                ; %xxxxxx54
        /* 45 */ WAIT4
        /* 41 */ lda VIA1_PA        ; %xxxxxx76
    zelse
        ; NTSC
        ; The critical points here are cycles 15, 23, 31 and 41.

        set0 VIA2_PCR, VIA2_PCR_CA2_CLOCK_OUT
        /* 0 */  WAIT12
        /* 12 */ WAIT3
        /* 15 */ ldx VIA1_PA        ; %xxxxxx10
        /* 19 */ WAIT4
        /* 23 */ ldy VIA1_PA        ; %xxxxxx32
        /* 27 */ WAIT4
        /* 31 */ lda VIA1_PA
        /* 35 */ pha                ; %xxxxxx54
        /* 38 */ WAIT3
        /* 41 */ lda VIA1_PA        ; %xxxxxx76
    zendif

    ; Now reassemble the data again.

    asl a
    asl a
    sta uloadtmp
    pla
    and #%00000011
    ora uloadtmp
    
    asl a
    asl a
    sta uloadtmp
    tya
    and #%00000011
    ora uloadtmp

    asl a
    asl a
    sta uloadtmp
    txa
    and #%00000011
    ora uloadtmp

    sta uloadtmp
    pla
    tay
    pla
    tax
    lda uloadtmp
    
    rts
zendproc
