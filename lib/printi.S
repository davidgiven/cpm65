; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

.global printi
.global printip

pad = __rc2
num = __rc3
save = __rc5

.section .text.printi
; void printi(uint16_t value)
printi:
    ldy #0
    sty pad
; void printip(uint16_t value, char pad)
printip:
    sta num+0
    stx num+1
    ldy #8              ; offset into tens
L1:
    ldx #$ff            ; start with digit=-1
    sec
L2:
    lda num+0
    sbc tens+0, y
    sta num+0
    lda num+1
    sbc tens+1, y
    sta num+1
    inx
    bcs L2

    lda num+0           ; add current count back in
    adc tens+0, y
    sta num+0
    lda num+1
    adc tens+1, y
    sta num+1

    txa
    bne printdigit
    cpy #0
    beq printdigit
    lda pad
    bne print
    beq next

printdigit:
    ldx #'0'
    stx pad
    ora #'0'
print:
    sty save
    jsr cpm_conout
    ldy save
next:
    dey
    dey
    bpl L1
    rts

tens:
    .short 1
    .short 10
    .short 100
    .short 1000
    .short 10000

; vim: sw=4 ts=4 et ft=asm

