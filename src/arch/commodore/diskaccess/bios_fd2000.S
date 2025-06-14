; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

; DPH and DPB for drive 0 (our only drive)

.global dph

.data
define_dpb dpb_fd2000, 157*80, 4096, 128, 3*80
define_dph dph, dpb_fd2000

; Converts an LBA sector number in XA to track/sector in Y, A.
; The FD2000 pretends there are 26 tracks, each of which has 256 sectors (except
; the last). This is almost, but not quite, LBA already.

zproc convert_to_ts, .text.tsconvert, weak
    pha
    txa
    tay
    iny             ; track numbers start at 1
    pla
    rts
zendproc
