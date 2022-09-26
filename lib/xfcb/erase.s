	.include "xfcb.inc"
	.include "cpm65.inc"

	.import BDOS
	.import xfcb_prepare

.export xfcb_erase
.proc xfcb_erase
	jsr xfcb_prepare
	ldy #bdos::delete_file
	jmp BDOS
.endproc


