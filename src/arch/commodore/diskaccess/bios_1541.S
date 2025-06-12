; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

; DPH and DPB for drive 0 (our only drive)

.global dph
.global dpb_1541

.data
define_dpb dpb_1541, 136*10, 1024, 64, 0
define_dph dph, dpb_1541

; Converts an LBA sector number in XA to track/sector in Y, A.

zproc convert_to_ts, .text.tsconvert, weak
    ldy #0
    zloop
        cpx #0
        zif eq
            cmp track_size_table, y
            zif cc
                iny     ; tracks are one-based.
                rts
            zendif
        zendif

        sec
        sbc track_size_table, y
        zif cc
            dex
        zendif
        iny
    zendloop

track_size_table:
    .fill 17, 1, 21
    .fill 7, 1, 19
    .fill 6, 1, 18
    .fill 10, 1, 17
zendproc
