; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"

zproc uppercase
    cmp #'a'
    zif_cs
        cmp #'z'+1
        zif_cc
            and #$5f
        zendif
    zendif
    rts
zendproc

