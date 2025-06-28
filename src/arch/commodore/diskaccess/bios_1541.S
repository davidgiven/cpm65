; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

; DPH and DPB for drive 0 (our only drive)

.global dph
.global dpb_1541

NUM_ZONES = 4

.zeropage ptr

.data
define_dpb dpb_1541, 136*10, 1024, 64, 0
define_dph dph, dpb_1541

; Converts an LBA sector number in XA to track/sector in Y, A.

zproc convert_to_ts, .text.tsconvert, weak
    ldy #0              ; zone number
    sta ptr+1           ; low byte of sector number
    sty ptr+0           ; track number
    zloop
        cpx #0
        zif eq
            lda ptr+1
            cmp zone_size_table, y
            zif lt      ; does this sector fit in this track?
                ldy ptr+0 ; yes
                iny     ; ...but tracks are one-based.
                rts
            zendif
        zendif

        ; Move to the next track, advancing the zone if necessary.

        inc ptr+0
        lda ptr+0
        cmp zone_boundary_table, y
        zif ge          ; need to move to the next zone?
            iny
            cpy #NUM_ZONES
            zif eq
                dey
            zendif
        zendif

        sec
        lda ptr+1
        sbc zone_size_table, y
        zif cc
            dex
        zendif
        sta ptr+1
    zendloop

zone_boundary_table:
    .byte 18, 25, 31, 36 ; highest track number +1
zone_size_table:
    .byte 21, 19, 18, 17 ; number of sectors in each zone
zendproc