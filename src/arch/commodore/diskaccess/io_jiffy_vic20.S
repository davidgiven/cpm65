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

.global ieee_computer_talking
ieee_computer_talking = iec_release_atn

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
    jsr wait_1ms                 ; 1ms delay
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

; Sets the V flag if we're PAL.

zlproc set_v_if_pal
    lda VICPALNTSC
1:
    cmp #PAL
    clv
    zif eq
        bit 1b                  ; 'cmp imm' has opcode 0xc9, so bitting it will set V
    zendif
    rts
zendproc

; Returns a data byte into A using the jiffy protocol. If EOI was set, sets C.

zproc ieee_getb
    jsr set_v_if_pal

    ; NTSC: 18*(1/1.022727) us = 17.6000004693 us
    ;  PAL: 18*(1/1.108405) us = 16.2395514280 us

    /* 0+0 */  zrepeat
    /* 0+4 */      lda VIA1_PA
    /* 4+2 */      and #0x03          ; wait for one of CLOCK or DATA...
    /* 6+2 */  zuntil ne              ; ...to be released

    /* 8+10 */ WAIT10
    /* 18 */

    ; NTSC: 11*(1/1.022727) us = 10.755558424 us
    ;  PAL: 14*(1/1.108405) us = 12.630762221 us

    /* PAL NTSC */ 
    /* 0+2  0+3 */  zif vs
    /* 2+4      */      WAIT4
    /* 6+0  3+0 */  zendif
    /* 6+8  3+8 */  WAIT8
    /* 14   11  */

    ; NTSC: 14*(1/1.022727) us = 13.688892539 us
    ;  PAL: 14*(1/1.108405) us = 12.630762221 us

    /* 0 */  lda VIA2_PCR
    /* 4 */  and #0xdd
    /* 6 */  sta VIA2_PCR           ; release CLOCK, DATA
    /* 10 */ ora #VIA2_PCR_CB2_DATA_OUT
    /* 12 */ tax
    /* 14 */


    ;  PAL: 9*(1/1.108405) us = 8.302200083 us
    ; NTSC: 8*(1/1.022727) us = 7.822224308 us

    /* PAL  NTSC */
    /* 0+3  0+2 */  bvs .+2
    /* 3+6  2+6 */  WAIT6
    /* 9    8   */

    ;  PAL: 12*(1/1.108405) us = 10.826367618334 us
    ; NTSC: 10*(1/1.022727) us = 9.7777803851859 us

    /* PAL  NTSC */
    /* 0+4  0+4 */  lda VIA1_PA     ; bits 0, 1
    /* 4+3  4+3 */  pha
    /* 7+2  7+3 */  zif vs
    /* 9+3      */      WAIT3
    /* 12   10  */  zendif

    ;  PAL: 11*(1/1.108405) us = 10.142876243079 us
    ; NTSC: 11*(1/1.022727) us = 10.755558423704 us

    /* 0+4 */  lda VIA1_PA          ; bits 2, 3
    /* 4+3 */  pha
    /* 7+4 */  WAIT4
    /* 11 */

    ;  PAL: 12*(1/1.108405) us = 10.826367618334 us
    ; NTSC: 10*(1/1.022727) us = 9.7777803851859 us

    /* PAL  NTSC */
    /* 0+4  0+4 */  lda VIA1_PA     ; bits 4, 5
    /* 4+3  4+3 */  pha
    /* 7+2  7+3 */  zif vs
    /* 9+3      */      WAIT3
    /* 12   10  */  zendif

    ;  PAL: 19*(1/1.108405) us = 17.141748729 us
    ; NTSC: 19*(1/1.022727) us = 18.577782732 us

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

    ; Done. Check the status byte to see if the read worked.

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
        jsr ieee_putb_raw
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
    sta jiffy_pending_char
zlproc ieee_putb_raw

    ; The VIC20's data output bits are nothing like as conveniently laid out as
    ; the C64. For each bit pair, the PCR looks like:
    ;     %11D111C0
    ;
    ; JiffyDOS wants the bits sent in the order 22114334.

    ; Compute values, in reverse order.

    lda VIA2_PCR        ; store value of PCR...
    and #0xdd           ; ...without DATA and CLOCK...
    tax                 ; ...for use throughout.

    ; Final value: mark transaction complete.

    ora #VIA2_PCR_CA2_CLOCK_OUT ; assert DATA
    pha

    ; EOI marker.

    txa
    bit jiffy_eoi
    zif pl
        ora #0x02               ; if not EOI, assert CLOCK
    zendif
    pha

    ; Least significant bits go first.

    lda jiffy_pending_char
    and #0x0f
    tay
    txa
    ora stab3, y
    pha                 ; fourth bit pair

    txa
    ora stab2, y
    pha                 ; third bit pair

    ; Compute the MSB.

    lda jiffy_pending_char
    rol a               ; top two bits into bottom two bits
    rol a
    rol a
    and #3
    tay
    txa
    ora stab1, y
    pha                 ; second bit pair

    lda jiffy_pending_char
    lsr a
    lsr a
    lsr a
    lsr a
    and #3
    tay
    txa
    ora stab1, y        ; first bit pair
    pha

    lda #0x02
    zrepeat
        bit VIA1_PA
    zuntil ne           ; wait for device to release data

    ldy #5              ; delay for 2 + (2+3)*5 - 1 = 26 cycles
    zrepeat
        dey
    zuntil eq

    jsr set_v_if_pal
    stx VIA2_PCR         ; release CLOCK to indicate we're about to send; real timing starts here

    ;  PAL: 12 * (1/1.108406) = 10.8 us
    ; NTSC: 11 * (1/1.022727) = 10.8 us

    /* PAL  NTSC */
    /* 0+4  0+4  */  pla              ; first nibble
    /* 4+2  4+3  */  zif vs
    /* 6+2       */      WAIT2
    /* 8+0  7+0  */  zendif
    /* 8+4  7+4  */  sta VIA2_PCR
    /* 12   11   */                    ; total time: PAL=10.8us NTSC=10.8 (want 11us)

    ;  PAL: 14 * (1/1.108406) = 12.6 us
    ; NTSC: 13 * (1/1.022727) = 12.7 us

    /* PAL  NTSC */
    /* 0+4  0+4  */  pla              ; second nibble
    /* 4+2  4+3  */  zif vs
    /* 6+2       */      WAIT2
    /* 8+0  7+0  */  zendif
    /* 8+2  7+2  */  WAIT2
    /* 10+4 9+4  */  sta VIA2_PCR
    /* 14   13   */                   ; total time: PAL=23.4us NTSC=23.5us (should be 24)

    ;  PAL: 12 * (1/1.108406) = 10.8 us
    ; NTSC: 11 * (1/1.022727) = 10.8 us

    /* PAL  NTSC */
    /* 0+4  0+4  */  pla              ; third nibble
    /* 4+2  4+3  */  zif vs
    /* 6+2       */      WAIT2
    /* 8+0  7+0  */  zendif
    /* 8+4  7+4  */  sta VIA2_PCR
    /* 12   11   */                   ; total time: PAL=34.2us NTSC=34.3us (should be 35)

    ;  PAL: 15 * (1/1.108406) = 13.5 us
    ; NTSC: 14 * (1/1.022727) = 13.7 us

    /* PAL  NTSC */
    /* 0+4  0+4  */  pla              ; fourth nibble
    /* 4+2  4+3  */  zif vs
    /* 6+2       */      WAIT2
    /* 8+0  7+0  */  zendif
    /* 8+3  7+3  */  WAIT3
    /* 11+4 10+4 */ sta VIA2_PCR
    /* 15   14   */                   ; total time: PAL=47.7us NTSC=48.0us (should be 48)

    ;  PAL: 15 * (1/1.108406) = 13.5 us
    ; NTSC: 13 * (1/1.022727) = 12.7 us

    /* PAL  NTSC */
    /* 0+4  0+4  */  pla              ; EOI marker
    /* 4+2  4+3  */  zif vs
    /* 6+3       */      WAIT3
    /* 9+0  7+0  */  zendif
    /* 9+2  7+2  */  WAIT2
    /* 11+4 9+4  */ sta VIA2_PCR
    /* 15   13   */                   ; total time: PAL=61.2us NTSC=60.7us (should be 61)

    ;  PAL: 16 * (1/1.108406) = 14.4us
    ; NTSC: 15 * (1/1.022727) = 14.7us

    /* PAL  NTSC */
    /* 0+4  0+4  */  pla              ; terminator
    /* 4+2  4+3  */  zif vs
    /* 6+2       */      WAIT2
    /* 8+0  7+0  */  zendif
    /* 8+4  7+4  */  WAIT4
    /* 12+4 11+4 */  sta VIA2_PCR
    /* 16   15   */                   ; total time: PAL=75.6us NTSC=75.4us (should be 76)
    lda VIA1_PA

    ; Timing-sensitive portion ends here.

    and #0x02                   ; check DATA is asserted
    sec
    zif eq
        ; Yes, success.
        clc
    zendif
    rts
zendproc

zlproc stab1
    .byte 0x00, 0x02, 0x20, 0x22
zendproc

zlproc stab2,  .align.16
    .byte 0x00, 0x00, 0x20, 0x20, 0x00, 0x00, 0x20, 0x20
    .byte 0x02, 0x02, 0x22, 0x22, 0x02, 0x02, 0x22, 0x22
zendproc

zlproc stab3,  .align.16
    .byte 0x00, 0x20, 0x00, 0x20, 0x02, 0x22, 0x02, 0x22
    .byte 0x00, 0x20, 0x00, 0x20, 0x02, 0x22, 0x02, 0x22
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
    ; (There isn't a routine to do this in the VIC20 ROM, for some reason.)

    set1 VIA1_DRA, VIA1_PA_ATN_OUT
    rts
zendproc

; A is the secondary address (0xfX for OPEN).

zproc ieee_talk
    pha
    jsr ieee_computer_atn
    lda #0x48               ; TALK device 8
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
        jsr ieee_putb_raw
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
