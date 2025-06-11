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
