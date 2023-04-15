; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

.macro WAIT2
    nop        ; 2
.endm

.macro WAIT3
    cmp 0      ; 3
.endm

.macro WAIT4
    nop        ; 2
    nop        ; 2
.endm

.macro WAIT5
    cmp 0      ; 3
    nop
.endm

.macro WAIT6
    cmp (0, x) ; 6
.endm

.macro WAIT7
    pha        ; 3
    pla        ; 4
.endm

.macro WAIT8
    cmp (0, x) ; 6
    nop        ; 2
.endm

.macro WAIT9
    pha        ; 3
    pla        ; 4
    nop        ; 2
.endm

.macro WAIT10
    pha        ; 3
    pla        ; 4
    cmp 0      ; 3
.endm
    
.macro WAIT11
    pha        ; 3
    pla        ; 4
    nop        ; 2
    nop        ; 2
.endm
    
.macro WAIT12
    cmp (0, x) ; 6
    cmp (0, x) ; 6
.endm

; vim: filetype=asm sw=4 ts=4 et


