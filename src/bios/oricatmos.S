; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "mos.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"

.section "sector1", "ax"

; Jasmin will load this at 0x0400.

    jmp sector1

; Microdisk requires this literal data.

    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x20, 0x20 ; :.....   :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x03 ; :     ...:
    .byte 0x00, 0x00, 0x00, 0x01, 0x00, 0x53, 0x45, 0x44 ; :.....SED:
    .byte 0x4F, 0x52, 0x49, 0x43, 0x20, 0x20, 0x20, 0x20 ; :ORIC    :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20                   ; :    ....:

.section "sector2", "ax"

; This is the Microdisk boot sector. It can load at a variety of addresses, for
; maximum inconvenience. After loading, we relocate to 0x9800, which is known to be
; unused (it's in the highres screen area).

; These literal bytes go before the code itself:

    .byte 0x00, 0x00, 0xFF, 0x00, 0xD0, 0x9F, 0xD0, 0x9F
    .byte 0x02, 0xB9, 0x01, 0x00, 0xFF, 0x00, 0x00, 0xB9
    .byte 0xE4, 0xB9, 0x00, 0x00, 0xE6, 0x12, 0x00

    sei
    lda #0x60
    sta 0x00                    ; place an RTS in zero page
    jsr 0x0000                  ; call it
return:

    tsx
    dex
    clc
    lda 0x0100, x               ; get low byte
    sbc #(return - sector2 - 2) ; adjust to beginning of sector
    sta 0x00
    lda 0x0101, x               ; get high byte
    sbc #0
    sta 0x01                    ; (0x0000) is now a pointer

    ; Copy 256 bytes.

    ldy #0
    zloop
        lda (0x00), y
        sta sector2, y
        iny
    zuntil_eq
    jmp sector2_start

sector2_start:
    nop
    jmp sector2_start

.section "sector3", "ax"

; Sector 3 of a disk must contain this exact data, or the Microdisk ROM will
; refuse to boot it. (It's a minimal Microdisk filesystem.)

    .byte $00,$00,$02,$53,$59,$53,$54,$45,$4d,$44,$4f,$53,$01,$00,$02,$00  ; ...SYSTEMDOS....
    .byte $02,$00,$00,$42,$4f,$4f,$54,$55,$50,$43,$4f,$4d,$00,$00,$00,$00  ; ...BOOTUPCOM....
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
