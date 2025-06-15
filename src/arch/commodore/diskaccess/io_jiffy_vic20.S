; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "vic20.inc"
#include "wait.inc"

ZEROPAGE

ieee_byte:          .fill 1
ieee_eoi:           .fill 1

; Kernel ROM disassembly here:
; http://www.fox-ts.co.uk/shared/vic20kernelrom.html
;
; Description of the terrible IEC protocol here:
; https://www.pagetable.com/?p=1135

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

; Switch from any mode to idle.

zproc ieee_computer_idle
    jsr iec_release_atn
    jsr iec_release_data
    jmp iec_release_clock
zendproc

; Returns a byte into A. If EOI was set, sets C.

zproc ieee_getb
    ; Wait for the talker to indicate it's ready to send.

    jsr wait_for_iec_clock_release

    ; Indicate that we're ready to receive.

    jsr iec_release_data

    ; Wait for the talker to assert clock, indicating that it's starting.
    ; There's a timeout here used for indicating EOI.

    lda #0
    sta ieee_eoi
    lda #1          ; 256us timeout
    sta VIA2_T2CH
    zrepeat
        lda VIA2_IFR
        and #VIA2_IFR_T2
        zif ne
            ; Timeout. Acknowledge EOI by toggling data.

            jsr iec_assert_data
            jsr wait_1ms
            jsr iec_release_data
            inc ieee_eoi
        zendif

        jsr get_iec_status
    zuntil pl ; until clock is asserted

    ; The talker will clock in bits on clock release edges.

    txa
    pha
    ldx #8
    zrepeat
        jsr wait_for_iec_clock_release
        ror ieee_byte
        jsr wait_for_iec_clock_assert

        dex
    zuntil eq
    pla
    tax

    ; Acknowledge receipt by asserting data.

    jsr iec_assert_data

    lda ieee_eoi        ; bottom bit set on EOI
    ror a               ; move into C
    lda ieee_byte
    rts
zendproc

; Sends A, with EOI set.

zproc ieee_puteoib
    pha
    lda #1
    sta ieee_eoi
    pla
zendproc
    ; fall through

; Sends A. Returns C on error.

zproc ieee_putb
    sta ieee_byte

    ; Ensure there is actually a device on the other end by releasing data and
    ; seeing if the device has it asserted. If it's not, there's nothing there.

    jsr iec_release_data
    jsr get_iec_status
    zif cs
        ; Device not present.

        sec
        rts
    zendif

    ; Tell the receiver we're ready to send by releasing clock.

    jsr iec_release_clock

    ; Now that we're ready, wait for the device to acknowledge by releasing
    ; data.

    jsr wait_for_iec_data_release

    ; Perform EOI sequence if necessary: we wait without sending the clock low.
    ; Eventually the receiver will aknowledge by briefly asserting data. (Not
    ; sure how this behaves with multiple receivers?)

    lda ieee_eoi
    zif ne
        jsr wait_for_iec_data_assert
        jsr wait_for_iec_data_release
    zendif

    ; Assert clock and go.

    jsr iec_assert_clock

    ; Now send a byte.

    txa
    pha
    ldx #8              ; bit count
    zrepeat
        zrepeat
            lda VIA1_DRA
            cmp VIA1_DRA
        zuntil eq
        ror a
        ror a           ; put data into carry
        zif cs
            ; timeout
        zendif

        ror ieee_byte
        jsr set_iec_data_from_carry

        ; Leave the clock released for 26 cycles.

        jsr iec_release_clock               ; uses 6 cycles after changing clock
        WAIT12                              ; 12
        lda VIA2_PCR                        ; 4
        and #~VIA2_PCR_CB2_DATA_OUT & 0xff  ; 2
        ora #VIA2_PCR_CA2_CLOCK_OUT         ; 2
        sta VIA2_PCR                        ; 4; total delay, 26 cycles

        dex
    zuntil eq
    pla
    tax

    ; We are now done. Wait for the receivers to acknowledge by asserting data.

    jsr wait_for_iec_data_assert
    lda #0
    sta ieee_eoi
    clc
    rts
zendproc

; Sets the data bit to C.

zproc set_iec_data_from_carry
    bcc iec_assert_data
zendproc
    ; fall through
zproc iec_release_data
    ; IEC data goes high

    set0 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT
    rts
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

zproc iec_assert_data
    ; IEC data goes low

    set1 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT
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

zproc iec_release_clock
    ; Set low; IEC clock goes high

    set0 VIA2_PCR, VIA2_PCR_CA2_CLOCK_OUT
    rts
zendproc

zproc iec_assert_clock
    ; Set high; IEC clock goes low

    set1 VIA2_PCR, VIA2_PCR_CA2_CLOCK_OUT
    rts
zendproc

zproc iec_release_atn
    ; Set low; IEC ATN goes high

    set0 VIA1_DRA, VIA1_PA_ATN_OUT
    rts
zendproc

zproc iec_assert_atn
    ; Set high; IEC ATN goes low

    set1 VIA1_DRA, VIA1_PA_ATN_OUT
    rts
zendproc

; Returns the clock bit in N and the data bit in C.

zproc get_iec_status
    ; VIA1 PA has format xxxxxxDC.

    zrepeat
        lda VIA1_DRA
        cmp VIA1_DRA
    zuntil eq
    ror a
    ror a
    rts
zendproc

; Waits for 60us.

zproc wait_60us
    lda #60
    sta VIA2_T2CL
    lda #0
    sta VIA2_T2CH
    beq timer_wait              ; always taken
zendproc

; Waits for 250us.

zproc wait_250us
    lda #250
    sta VIA2_T2CL
    lda #0
    sta VIA2_T2CH
    beq timer_wait              ; always taken
zendproc

; Waits for 1ms.

zproc wait_1ms
    lda #4
    sta VIA2_T2CH
timer_wait:
    zrepeat
        lda VIA2_IFR
        and #VIA2_IFR_T2
    zuntil ne
    rts
zendproc

