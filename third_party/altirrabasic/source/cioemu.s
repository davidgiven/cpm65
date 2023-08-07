; Altirra BASIC - READ/INPUT data module
; Copyright (C) 2023 David Given, All Rights Reserved.
;
; Copying and distribution of this file, with or without modification,
; are permitted in any medium without royalty provided the copyright
; notice and this notice are preserved.  This file is offered as-is,
; without any warranty.

.proc initcio
    lda #0
    sta brkkey
    rts
.endp

.proc ciov
    rts
.endp
