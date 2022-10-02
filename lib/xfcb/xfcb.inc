; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

.struct xfcb
    dr .byte
    f1 .byte
    f2 .byte
    f3 .byte
    f4 .byte
    f5 .byte
    f6 .byte
    f7 .byte
    f8 .byte
    t1 .byte
    t2 .byte
    t3 .byte
    ex .byte
    s1 .byte
    s2 .byte
    rc .byte
    al .res 16
    cr .byte
    r0 .byte
    r1 .byte
    r2 .byte
	us .byte
.endstruct


