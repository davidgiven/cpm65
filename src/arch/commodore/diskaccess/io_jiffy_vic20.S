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
iec_make_bus_idle = 0xef09
wait_1ms = 0xef96
timer_wait = 0xef9b

jiffy_has_pending_char = 0x94
jiffy_pending_char = 0x95
jiffy_eoi = 0xa3


ORIOST = 0xfe6a
SERGET = 0xe4b2
RSPAUSE         = $F160        ; SET TIMER
SRBAD           = $EEB4        ; device not present

; Kernel ROM disassembly here:
; http://www.fox-ts.co.uk/shared/vic20kernelrom.html
;
; Description of the terrible IEC protocol here:
; https://www.pagetable.com/?p=1135

zproc io_init
    rts
zendproc

zproc jiffy_talk
        ora     #$40
        skip2
zproc jiffy_listen
        ora     #$20
        jsr     RSPAUSE         ; SET TIMER
zproc jiffy_listen2
        pha                     ; save device address
        bit     jiffy_has_pending_char             ; test deferred character flag
        bpl     1f              ; branch if no defered character
        sec                     ; flag EOI
        ror     jiffy_eoi             ; rotate into EOI flag byte
        jsr     ieee_putb
        lsr     jiffy_has_pending_char             ; clear deferred character flag
        lsr     jiffy_eoi             ; clear EOI flag
1:       pla                     ; device address OR'ed with command
        sta     jiffy_pending_char             ; save as serial defered character
        sei
        lda     #$00
        sta     jiffy_eoi
        jsr     iec_release_data         ; set IEC data out high (0)
        jsr iec_assert_atn
zproc put_command_byte
        jsr     iec_assert_clock         ; set IEC clock out low
        jsr     iec_release_data         ; set IEC data out high (0)
        jsr     wait_1ms           ; 1ms delay
IEC_send_byte:
        sei
        jsr     iec_release_data         ; set serial data out high
        jsr     get_iec_status
        bcc     1f              ;
        jmp     SRBAD           ; Device_Not_Present
1:       jsr     iec_release_clock         ; set serial clock high
        bit     jiffy_eoi             ; test EOI flag
        zif mi ; if not EOI
                jsr wait_for_iec_data_release
                jsr wait_for_iec_data_assert
        zendif
        jsr wait_for_iec_data_release

; serial data is high now pull the clock low, preferably within 60us

        jsr     iec_assert_clock         ; set IEC clock out low

; now the Vic has to send the eight bits, LSB first. first it sets the
; serial data line to reflect the bit in the byte, then it sets the
; serial clock to high. The serial clock is left high for 26 cycles,
; 23us on a PAL Vic, before it is again pulled low and the serial data
; is allowed high again

; The jiffy routine detecs Jiffy devices within the routine
; jiffy_detect_device and X=2

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

        cpx #$02
        zif eq
            lda #$02            ; test bit 1 (DATA) of serial bus
            ldx #$20            ; 1e??? wait for jiffy protocol
        4:
            bit VIA1_PA        ; test DATA
            beq 2f          ; data high (0) -> Jiffy signal
            dex
            bne 4b
            beq 3f       ; no Jiffy device
    
        2:
            jsr wait_for_iec_data_release
        3:
            ldx #$02
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
    jsr iec_make_bus_idle
    sec
    rts
zendproc

zproc jiffy_untalk
    jsr iec_release_atn
    jsr iec_assert_clock
    lda #$5F
    skip2
zproc jiffy_unlisten
    lda #$3F
    jsr jiffy_listen2
    jmp iec_make_bus_idle
zendproc

zproc jiffy_talksa
    sta jiffy_pending_char
    jsr put_command_byte

    jsr iec_assert_data
    jsr iec_release_atn
    jsr iec_release_clock
    jmp wait_for_iec_clock_assert
zendproc

zproc jiffy_listensa
    sta jiffy_pending_char
    jsr put_command_byte
    jmp iec_release_atn
zendproc

; Returns a data byte into A using the jiffy protocol. If EOI was set, sets C.

zproc ieee_getb
; Read a byte in using the SJLoad routine.
; total time for 1 byte received:
; NTSC: (18+11+14+8+ 8+23+19) * (1/1.022727) = 98.755581890 microseconds
;  PAL: (18+14+14+9+10+25+19) * (1/1.108405) = 98.339505867 microseconds
; if the PAL version were to be used on NTSC, it would take 106.577806199 microseconds.

; timing:
; NTSC: 18*(1/1.022727) microseconds = 17.6000004693 microseconds
;  PAL: 18*(1/1.108405) microseconds = 16.2395514280 microseconds

1:       lda     VIA1_PA        ;4 serial bus
        and     #$03            ;2 mask clock-in and data-in bits
        beq     1b              ;2 wait for one of them to be high

        lda     #$80            ;2 initialize the byte-received flag
        sta     t9c             ;3 to $80
        txa                     ;2 save .X
        pha                     ;3 i'm serious

; timing:
; NTSC: 11*(1/1.022727) microseconds = 10.755558424 microseconds
;  PAL: 14*(1/1.108405) microseconds = 12.630762221 microseconds

        pha                     ;3
        pla                     ;4

.ifdef SJ20_NTSC
        nop                     ;2
        nop                     ;2
.endif

.ifndef SJ20_NTSC
        pha                     ;3
        pla                     ;4
.endif

; timing:
; NTSC: 14*(1/1.022727) microseconds = 13.688892539 microseconds
;  PAL: 14*(1/1.108405) microseconds = 12.630762221 microseconds

        lda     VIA2_PCR        ;4 handshaking (bring serial bus data line high)
        and     #$DD            ;2 handshaking cont'd
        sta     VIA2_PCR        ;4 handshaking cont'd
        ora     #$20            ;2 set bit 5=1
        tax                     ;2 store

; timing:
; NTSC: 8*(1/1.022727) microseconds = 7.822224308 microseconds
;  PAL: 9*(1/1.108405) microseconds = 8.302200083 microseconds

        bit     t9c             ;timing
.ifndef SJ20_NTSC
        bit     t9c             ;timing
.endif
        bit     t9c             ;timing
.ifdef SJ20_NTSC
        nop
.endif

; timing:
; NTSC:  8*(1/1.022727) microseconds = 7.822224308 microseconds
;  PAL: 10*(1/1.108405) microseconds = 9.021973050 microseconds

        lda     VIA1_PA        ; get bit 0 & 1
        ror                     ; bit 0 (clock) -> bit 7
        ror                     ; bit 1 (data ) -> carry
        and     #$80            ; mask received bit 0

.ifndef SJ20_NTSC
        nop                     ;2
.endif

        ora     VIA1_PA        ; get bit 2 & 3
        rol                     ; A = .....XXX
        rol                     ; A = ....XXXX
        sta     tb3             ; store lower nibble

        lda     VIA1_PA        ; get bit 4 & 5
        ror                     ; bit 4 (clock) -> bit 7
        ror                     ; bit 5 (data ) -> carry
        and     #$80            ; mask received bit 4

.ifndef SJ20_NTSC
        nop                     ;2
.endif

; timing:
; NTSC: 19*(1/1.022727) microseconds = 18.577782732 microseconds
;  PAL: 19*(1/1.108405) microseconds = 17.141748729 microseconds

        ora     VIA1_PA        ; get bit 6 & 7
        rol                     ; A = .....XXX
        rol                     ; A = ....XXXX
        sta     tc0             ; store upper nibble
        lda     VIA1_PA        ; get status bits
        stx     VIA2_PCR        ; data out (5) = 1
; end of timing sensitive portion
        sta     t9c             ; save status bits

        ; Combine nibbles.

        lda     tb3
        and     #$0F
        sta     tb3
        lda     tc0
        asl
        asl
        asl
        asl
        ora     tb3

        sta     ta4             ; received byte
        pla
        tax
        lda     t9c             ; restore status bits
        ror                     ; (clock) -> bit 7
        ror                     ; (data ) -> carry
        bpl     l7C54           ; Jiffy_Set_OK   ; clock = 0 -> OK
        bcc     lfC4f           ; Jiffy_Set_EOI  ; data  = 0 -> EOI
        lda     #$42            ; EOI (6) and time out (1) ($42)
        jmp     $EEB9           ; Set_IEC_Status

    lda jiffy_eoi        ; bottom bit set on EOI
    ror a               ; move into C
    lda jiffy_pending_char
    rts

lfC4f:  lda     #$40            ; bit 6 = EOI
        jsr     ORIOST
l7C54:  lda     ta4
        sec
        rts

zendproc

zproc send_byte
        bit     jiffy_has_pending_char             ; test deferred character flag
        bmi     1f              ; branch if defered character
        sec                     ; set deferred character flag
        ror     jiffy_has_pending_char
        bne     2f
1:  pha
        jsr     ieee_putb
        pla
2:   sta     jiffy_pending_char             ; save as serial defered character
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

        txa             ; store .X on stack
        pha
        lda     jiffy_pending_char     ; BSOUR, the byte to send
        lsr             ; put MSB in LSB
        lsr
        lsr
        lsr
        tax             ; give to .X
        lda     stab1,x ; get the corresponding data from the send table
        pha             ; save it
        txa             ; restore .A to .X
        lsr             ; next 2 bits
        lsr
        tax             ; give to .X
        lda     stab1,x ; get the corresponding send table data again
        sta     tb3
        lda     jiffy_pending_char     ; restore BSOUR
        and     #$0F    ; get LSB of BSOUR
        tax             ; give to .X

        lda     #$02

; start of timing sensitive portion
; total time:
; NTSC: (15+14+20+17+18/19+13) * (1/1.022727) = 94.844469736 microseconds
;  PAL: (15+16+22+19+20/21+13) * (1/1.108405) = 94.730716660 microseconds

; timing:
; NTSC: 15
;  PAL: 15

1:       bit     VIA1_PA        ;4 wait for bit 1 (data) of $911F to be set
        beq     1b              ;2 loop until data is 1

        lda     VIA2_PCR        ;4 handshaking - (bring serial bus data line high)
        and     #$DD            ;2 yep
        sta     t9c             ;3 save what we want to handshake.

; timing
; NTSC: 14
;  PAL: 20

        pha                     ;3
        pla                     ;4
        pha                     ;3
        pla                     ;4
.ifndef SJ20_NTSC
        nop                     ;2
        nop                     ;2
        nop                     ;2
.endif

; timing
; NTSC: 14
;  PAL: 16

        sta     VIA2_PCR        ;4 handshaking - bring the data line high
        pla                     ;3 restore .A (gotten from send table earlier)
        ora     t9c             ;3 OR with handshake value to get value to send

.ifndef SJ20_NTSC
        nop                     ;2
.endif

        sta     VIA2_PCR        ;4 send to drive over serial bus

; timing
; NTSC: 20
;  PAL: 22

        lda     tb3             ;3 get 2nd value to send
        ora     t9c             ;3 OR with old $912C
        ora     t9c             ;3 timing
        sta     VIA2_PCR        ;4 send to drive over serial bus
        lda     stab2,x         ;4 Get third value to send from table
        ora     t9c             ;3 OR with old $912C

.ifndef SJ20_NTSC
        nop                     ;2
.endif

; timing
; NTSC: 17
;  PAL: 19

        sta     VIA2_PCR        ;4 send to drive over serial bus
        lda     stab3,x         ;4 Get fourth value to send from table
        ora     t9c             ;3 OR with old $912C
        nop                     ;2 timing
        sta     VIA2_PCR        ;4 send to drive over serial bus

.ifndef SJ20_NTSC
        nop                     ;2
.endif

; timing
; NTSC: 18/19
;  PAL: 20/21

        and     #$DD            ;2
        bit     jiffy_eoi        ;3 is bit 7 of LDFLAG set?
        bmi     1f              ;2/3 yes, don't bring data line low yet
        ora     #$02            ;2 no, OR to bring serial bus data line low
1:       sta     VIA2_PCR        ;4 handshaking - bring data line low

        pla                     ;4 restore .X
        tax                     ;2

.ifndef SJ20_NTSC
        nop                     ;2
.endif

; timing
; NTSC: 13
;  PAL: 13

        lda     t9c             ;3 get old $912C
        ora     #$02            ;2 OR to bring data line low
        sta     VIA2_PCR        ;4 handshaking - bring data line low
        lda     VIA1_PA        ;4 read serial bus
        and     #$02            ;2 is data line low?
; end of timing sensitive portion
        beq     l7C56           ; yes, we're done
        jmp     $EEB7           ; no, err TIME OUT
    l7C56:
        clc
        rts
zendproc

zlproc stab1, .align.16
    .byte   $00,$02,$20,$22,$00,$02,$20,$22,$00,$02,$20,$22,$00,$02,$20,$22
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


