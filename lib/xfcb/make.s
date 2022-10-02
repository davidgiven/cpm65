; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

	.include "xfcb.inc"
	.include "cpm65.inc"

	.importzp __fcb
	.import BDOS
	.import xfcb_get
	.import xfcb_set
	.import xfcb_prepare
	.import xfcb_clear

.export xfcb_make
.proc xfcb_make
	jsr xfcb_prepare
	jsr xfcb_clear
	ldy #bdos::create_file
	jmp BDOS
.endproc


