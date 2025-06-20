; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "vic20.inc"
#include "wait.inc"

ZEROPAGE

t9c:        .fill 1
tb3:        .fill 1
ta4:        .fill 1
tc0:        .fill 1
jiffy_has_pending_char: .fill 1
jiffy_pending_char:     .fill 1
jiffy_eoi:              .fill 1

; Values for VIA2_PCR. Bit values are inverted --- 1 == asserted, 0 == released.
;      %..D...C.
D0C0 = %11011100 ; 0xdc
D0C1 = %11011110 ; 0xde
D1C0 = %11111100 ; 0xfc
D1C1 = %11111110 ; 0xfe

iec_release_data = 0xe4a0
iec_assert_data = 0xe4a9
iec_release_clock = 0xef84
iec_assert_clock = 0xef8d
iec_release_atn = 0xeec5
ieee_computer_idle = 0xef09
wait_1ms = 0xef96
timer_wait = 0xef9b

SERGET = 0xe4b2

; Kernel ROM disassembly here:
; http://www.fox-ts.co.uk/shared/vic20kernelrom.html
;
; Description of the terrible IEC protocol here:
; https://www.pagetable.com/?p=1135

zproc io_init
    lda #0
    sta jiffy_has_pending_char
    sta jiffy_pending_char
    sta jiffy_eoi
    rts
zendproc

; The computer is asserting ATN and about to send a command.

zproc ieee_computer_atn
    jsr iec_assert_atn
    jsr iec_assert_clock
    jsr iec_release_data
    jmp wait_for_iec_data_assert
zendproc

; Switch from ATN to the computer talking.

zproc ieee_computer_talking
    jmp iec_release_atn
zendproc

; Switch from ATN to the computer listening.

zproc ieee_computer_listening
    jsr iec_release_atn
    jsr iec_assert_data
    jsr iec_release_clock
    jmp wait_for_iec_clock_assert
zendproc

; Sends the byte in A via the old-fashioned IEC protocol, with JiffyDOS
; triggering. EOI is not honoured.

zproc put_command_byte
    sta jiffy_pending_char
    jsr iec_assert_clock         ; set IEC clock out low
    jsr iec_release_data         ; set IEC data out high (0)
    jsr wait_1ms           ; 1ms delay
    jsr iec_release_data         ; set serial data out high
    jsr get_iec_status
    bcs device_timeout
    jsr iec_release_clock         ; set serial clock high
    jsr wait_for_iec_data_release

    jsr iec_assert_clock         ; set IEC clock out low

    ; Send the actual data.

    ldx #8                          ; eight bits to do
    zrepeat
        jsr get_iec_status
        bmi device_timeout          ; if clock assert, it's a timeout
        jsr iec_release_data        ; set IEC data high (0)
        ror jiffy_pending_char      ; rotate bit to send into carry
        zif cc
            jsr iec_assert_data
        zendif
        jsr iec_release_clock
        WAIT6
        jsr iec_release_data
        jsr iec_assert_clock

        ; If we're on the second last bit, perform the JiffyDOS detection. This
        ; is necessary to make the drive speak/listen to JiffyDOS commands.
        ; However, it's more annoying than it should be because detection only
        ; works on some bytes of the command, and at other times it times out.

        cpx #2
        zif eq
            lda #2              ; test bit 1 (DATA) of serial bus
            ldx #0x20           ; 1e??? wait for jiffy protocol
        4:
            bit VIA1_PA        ; test DATA
            beq 2f          ; data high (0) -> Jiffy signal
            dex
            bne 4b
            beq 3f       ; no Jiffy device
    
        2:
            jsr wait_for_iec_data_release
        3:
            ldx #2  
        zendif

        dex
    zuntil eq

    ; Wait up to 1ms for the device to respond.

    lda #4
    sta VIA2_T2CH
    zrepeat
        lda VIA2_IFR
        and #VIA2_IFR_T2
        bne device_timeout

        jsr get_iec_status
    zuntil cc               ; wait for data low
    rts
zendproc

zlproc device_timeout
    jsr ieee_computer_idle
    sec
    rts
zendproc

; Returns a data byte into A using the jiffy protocol. If EOI was set, sets C.

zproc ieee_getb
; Read a byte in using the SJLoad routine.
; total time for 1 byte received:
; NTSC: (18+11+14+8+ 8+23+19) * (1/1.022727) = 98.755581890 microseconds
;  PAL: (18+14+14+9+10+25+19) * (1/1.108405) = 98.339505867 microseconds
; if the PAL version were to be used on NTSC, it would take 106.577806199 microseconds.

    ; Sets the V flag if we're PAL.

    lda VICPALNTSC
1:
    cmp #PAL
    clv
    zif eq
        bit 1b                  ; 'cmp imm' has opcode 0xc9, so bitting it will set V
    zendif

    ; NTSC: 18*(1/1.022727) microseconds = 17.6000004693 microseconds
    ;  PAL: 18*(1/1.108405) microseconds = 16.2395514280 microseconds

    /* 0+0 */  zrepeat
    /* 0+4 */      lda VIA1_PA
    /* 4+2 */      and #0x03          ; wait for one of CLOCK or DATA...
    /* 6+2 */  zuntil ne              ; ...to be released

    /* 8+10 */ WAIT10
    /* 18 */

    ; NTSC: 11*(1/1.022727) microseconds = 10.755558424 microseconds
    ;  PAL: 14*(1/1.108405) microseconds = 12.630762221 microseconds

    /* PAL NTSC */ 
    /* 0+2  0+3 */  zif vs
    /* 2+4      */      WAIT4
    /* 6+0  3+0 */  zendif
    /* 6+8  3+8 */  WAIT8
    /* 14   11  */

    ; NTSC: 14*(1/1.022727) microseconds = 13.688892539 microseconds
    ;  PAL: 14*(1/1.108405) microseconds = 12.630762221 microseconds

    /* 0 */  lda VIA2_PCR
    /* 4 */  and #0xdd
    /* 6 */  sta VIA2_PCR           ; release CLOCK, DATA
    /* 10 */ ora #VIA2_PCR_CB2_DATA_OUT
    /* 12 */ tax
    /* 14 */


    ;  PAL: 9*(1/1.108405) microseconds = 8.302200083 microseconds
    ; NTSC: 8*(1/1.022727) microseconds = 7.822224308 microseconds

    /* PAL  NTSC */
    /* 0+3  0+2 */  bvs .+2
    /* 3+6  2+6 */  WAIT6

    ;  PAL: 12*(1/1.108405) microseconds = 10.826367618334 microseconds
    ; NTSC: 10*(1/1.022727) microseconds = 9.7777803851859 microseconds

    /* PAL  NTSC */
    /* 0+4  0+4 */  lda VIA1_PA     ; bits 0, 1
    /* 4+3  4+3 */  pha
    /* 7+2  7+3 */  zif vs
    /* 9+3      */      WAIT3
    /* 12   10  */  zendif

    ;  PAL: 11*(1/1.108405) microseconds = 10.142876243079 microseconds
    ; NTSC: 11*(1/1.022727) microseconds = 10.755558423704 microseconds

    /* 0+4 */  lda VIA1_PA          ; bits 2, 3
    /* 4+3 */  pha
    /* 7+4 */  WAIT4
    /* 11 */

    ;  PAL: 12*(1/1.108405) microseconds = 10.826367618334 microseconds
    ; NTSC: 10*(1/1.022727) microseconds = 9.7777803851859 microseconds

    /* PAL  NTSC */
    /* 0+4  0+4 */  lda VIA1_PA     ; bits 4, 5
    /* 4+3  4+3 */  pha
    /* 7+2  7+3 */  zif vs
    /* 9+3      */      WAIT3
    /* 12   10  */  zendif

    ;  PAL: 19*(1/1.108405) microseconds = 17.141748729 microseconds
    ; NTSC: 19*(1/1.022727) microseconds = 18.577782732 microseconds

    /* 0+4 */  lda VIA1_PA          ; bits 6, 7
    /* 4+3 */  pha
    /* 7+4 */  WAIT4
    /* 11+4 */ lda VIA1_PA          ; status
    /* 15+4 */ stx VIA2_PCR
    /* 19 */

    sta t9c             ; save status bits

    ; Now reconstruct the nibble.

    pla                 ; ......76
    and #%00000011
    asl a               ; .....76.
    asl a               ; ....76..
    sta tc0

    pla                 ; ......54
    and #%00000011
    ora tc0             ; ....7654
    asl a               ; ...7654.
    asl a               ; ..7654..
    sta tc0

    pla
    and #%00000011
    ora tc0             ; ..765432
    asl a               ; .765432.
    asl a               ; 765432..
    sta tc0

    pla
    and #%00000011
    ora tc0             ; 76543210

    tax
    lda t9c             ; ......DC
    and #%00000001
    sec
    zif eq
        ; Clock asserted, success.
        clc
    zendif
    
    txa
    rts
zendproc

zproc ieee_write
    bit jiffy_has_pending_char
    zif mi
        pha
        tya
        pha
        txa
        pha
        lda jiffy_pending_char
        jsr ieee_putb
        pla
        tax
        pla
        tay
        pla
    zendif

    sta jiffy_pending_char
    lda #0x80
    sta jiffy_has_pending_char
    clc
    rts
zendproc

; Puts a data byte in A using the jiffy protocol.

zproc ieee_putb
    ; The VIC20's data output bits are nothing like as conveniently laid out as
    ; the C64. For each bit pair, the PCR looks like:
    ;     %11D111C0
    ;
    ; JiffyDOS wants the bits sent in the order 22114334.

    lda jiffy_pending_char
    lsr a
    lsr a
    lsr a
    lsr a
    tay                 ; Y = MSB
    and #3
    tax
    lda stab1, x
    pha                 ; second value goes on stack

    tya
    lsr a
    lsr a
    and #3
    tax
    ldy stab1, x        ; first value goes in Y

    lda jiffy_pending_char
    and #$0F
    tax                 ; low nibble goes in X


; start of timing sensitive portion

    ; Timing-sensitive portion starts here (at the bit instruction).
    ; Total time:
    ; NTSC: (15+14+20+16+18/19+13) * (1/1.022727) = 93.844469736 microseconds
    ;  PAL: (15+16+22+18+20/21+13) * (1/1.108405) = 93.828519358 microseconds

    ; NTSC: 15
    ;  PAL: 15

           lda #0x02
/* 0 */    zrepeat
/* 0+4 */      bit VIA1_PA
/* 4+2 */  zuntil ne           ; wait for DATA release

/* 6+4 */  lda VIA2_PCR         ; store value of PCR...
/* 10+2 */ and #$DD             ; ...without DATA and CLOCK...
/* 12+3 */ sta t9c              ; ...for use later.
/* 15 */

    ; NTSC: 14
    ;  PAL: 20

    WAIT14
.ifndef SJ20_NTSC
    WAIT6
.endif

    ; NTSC: 14
    ;  PAL: 16

/* 0+4 */  sta VIA2_PCR         ; release DATA to indicate we're about to send
/* 4+3 */  pla                  ; first value to send
/* 7+3 */  ora t9c              ; old VIA2_PDR

.ifndef SJ20_NTSC
/* 10+2 */ WAIT2
.endif
/* 12+4 */ sta VIA2_PCR
/* 16 */

    ; NTSC: 20
    ;  PAL: 22

/* 0+2 */  tya                 ; second value to send
/* 2+3 */  ora t9c             ; or with old VIA2_PCR
/* 5+4 */  WAIT4
/* 9+4 */  sta VIA2_PCR
/* 13+4 */ lda stab2,x         ; third value to send
/* 17+3 */ ora t9c             ; or with old VIA2_PCR
/* 20 */

.ifndef SJ20_NTSC
    WAIT2
.endif

    ; NTSC: 16
    ;  PAL: 18

/* 0+4 */  sta VIA2_PCR
/* 4+4 */  lda stab3,x          ; Get fourth value to send from table
/* 8+2 */  ora t9c              ; old VIA2_PCR
/* 10+2 */ WAIT2
/* 12+4 */ sta VIA2_PCR
.ifndef SJ20_NTSC
/* 16+2 */ WAIT2
.endif
/* 18 */

    ; NTSC: 18/19
    ;  PAL: 20/21

/* 0+2 */  and #$DD
/* 2+3 */  bit jiffy_eoi
/* 5+2 */  zif pl
/* 7+2 */      ora #$02           ; If EOI, don't assert DATA
/* 9+0 */  zendif
/* 9+4 */  sta VIA2_PCR

/* 13+6 */ WAIT6

.ifndef SJ20_NTSC
/* 19+2 */ WAIT2
.endif
/* 21 */

    ; NTSC: 15
    ;  PAL: 15

/* 0+3 */  lda t9c                ; old VIA2_PDR
/* 3+2 */  ora #$02               ; assert DATA
/* 5+4 */  sta VIA2_PCR
/* 9+4 */  lda VIA1_PA
/* 13+2 */ and #$02               ; check DATA is asserted
/* 15 */

    ; Timing-sensitive portion ends here.

    sec
    zif eq
        ; Yes, success.
        clc
    zendif
    rts
zendproc

zlproc stab1
    .byte   $00,$02,$20,$22
zendproc

zlproc stab2, .align.16
    .byte   $00,$00,$20,$20,$00,$00,$20,$20,$02,$02,$22,$22,$02,$02,$22,$22
zendproc

zlproc stab3, .align.16
    .byte   $00,$20,$00,$20,$02,$22,$02,$22,$00,$20,$00,$20,$02,$22,$02,$22
zendproc

zproc wait_for_iec_data_release
    zrepeat
        jsr get_iec_status
    zuntil cs
    rts
zendproc

zproc wait_for_iec_data_assert
    zrepeat
        jsr get_iec_status
    zuntil cc
    rts
zendproc

zproc wait_for_iec_clock_release
    zrepeat
        jsr get_iec_status
    zuntil mi
    rts
zendproc

zproc wait_for_iec_clock_assert
    zrepeat
        jsr get_iec_status
    zuntil pl
    rts
zendproc

; Returns the clock bit in N and the data bit in C.

zproc get_iec_status
    ; ROM routine which returns the data bit in B0 and the clock bit in C.

    jsr SERGET
    ror a
    rts
zendproc

zproc iec_assert_atn
    ; Set high; IEC ATN goes low

    set1 VIA1_DRA, VIA1_PA_ATN_OUT
    rts
zendproc

; A is the secondary address (0xfX for OPEN).

zproc ieee_talk
    pha
    jsr ieee_computer_atn
    lda #0x48               ; TALK device 8
1:
    jsr put_command_byte
    pla
    ora #0x60               ; SECOND
    jsr put_command_byte
    jmp ieee_computer_listening
zendproc

; A is the secondary address.

zproc ieee_listen
    pha
    jsr ieee_computer_atn
    lda #0x28               ; LISTEN device 8
    jsr put_command_byte
    pla
    ora #0x60               ; SECOND
    jsr put_command_byte
    jmp ieee_computer_talking
zendproc

zproc ieee_unlisten
    bit jiffy_has_pending_char
    zif mi
        lda #0x80
        sta jiffy_eoi
        lda jiffy_pending_char
        jsr ieee_putb
        asl jiffy_has_pending_char      ; reset flag
    zendif

    lda #0x3f               ; UNLISTEN
    SKIP2
zproc ieee_untalk
    lda #0x5f               ; UNTALK
zproc atn_put_and_idle
    pha
    jsr ieee_computer_atn
    pla
    jsr put_command_byte
    jmp ieee_computer_idle
zendproc
