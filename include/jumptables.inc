; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

.macro jmpdispatch lotab, hitab
    sta ptr
    lda \hitab, y
    pha
    lda \lotab, y
    pha
    lda ptr
    rts
.endm

.macro jmptablo value
    .byte (\value - 1)@mos16lo
.endm

.macro jmptabhi value
    .byte (\value - 1)@mos16hi
.endm

.macro jmptabloconst value
    .byte (\value - 1) & 0xff
.endm

.macro jmptabhiconst value
    .byte (\value - 1) >> 8
.endm

; vim: filetype=asm sw=4 ts=4 et

