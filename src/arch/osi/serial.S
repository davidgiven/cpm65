; Ohio Scientific Instruments serial tty routines.
; Copyright © 2024 by Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

SERIAL_ACIA_CONTROL = $fc00
SERIAL_ACIA_STATUS  = $fc00
SERIAL_ACIA_RDR     = $fc01
SERIAL_ACIA_TDR     = $fc01

; ----------------------------------------------------------------------------

zproc init_serial
    jmp serial_open
zendproc

zproc tty_conin
    jmp serial_in
zendproc

zproc tty_const
    lda SERIAL_ACIA_STATUS
    lsr
    zif_cc
        lda #0                      ; no key
    zelse
        lda #$ff                    ; key is pending
    zendif
    rts
zendproc

zproc tty_conout
    cmp #127                        ; workaround for now, see issue #148
    zif_eq                          ; and PR #138
        lda #8
        jsr serial_out
        lda #' '
        jsr serial_out
        lda #8
    zendif
    jmp serial_out
zendproc

; ----------------------------------------------------------------------------

; RAW SERIAL DRIVER

defdriver SERIAL, DRVID_SERIAL, drvstrat_SERIAL, 0

zproc drvstrat_SERIAL
    jmpdispatch drv_serial_jump_lo, drv_serial_jump_hi

drv_serial_jump_lo:
    jmptablo serial_inp
    jmptablo serial_out
    jmptablo serial_open
    jmptablo serial_close
    jmptablo serial_outp
    jmptablo serial_in

drv_serial_jump_hi:
    jmptabhi serial_inp
    jmptabhi serial_out
    jmptabhi serial_open
    jmptabhi serial_close
    jmptabhi serial_outp
    jmptabhi serial_in
zendproc

; Non-Blocking I/O
; ----------------

; exit: C if no char pending, !C return char in A
zproc serial_inp
    lda SERIAL_ACIA_STATUS
    lsr
    zif_cc                          ; no char is pending
        sec
        rts
    zendif

    lda SERIAL_ACIA_RDR
    clc
    rts
zendproc

; exit: C if unable to send, !C A is sent
zproc serial_outp
    pha
    lda SERIAL_ACIA_STATUS
    lsr
    lsr
    zif_cc                          ; TDR is not empty
        pla
        sec
        rts
    zendif

    pla
    sta SERIAL_ACIA_TDR
    clc
    rts
zendproc

; Blocking I/O
; ------------

zproc serial_in
    zrepeat
        lda SERIAL_ACIA_STATUS       ; wait for bit 0 set, RDR full
        lsr
    zuntil_cs

    lda SERIAL_ACIA_RDR
    rts
zendproc

zproc serial_out
    pha
    zrepeat
        lda SERIAL_ACIA_STATUS       ; wait for bit 1 set, TDR empty
        lsr
        lsr
    zuntil_cs
    pla
    sta SERIAL_ACIA_TDR
    rts
zendproc

; Open/Close

zproc serial_open
    lda #CONTROL_RESET
    sta SERIAL_ACIA_CONTROL
    ; div1 --> 4800 baud default, up to 19200 with faster base clock
    lda #(TCB_nRTS_HIGH_IRQ_DIS << TCB_SHIFT) | (WS_8N2 << WS_SHIFT)
    sta SERIAL_ACIA_CONTROL
    rts
zendproc

zproc serial_close
    rts
zendproc

; -------------------------------------------------------------------------

; vim: filetype=asm sw=4 ts=4 et
