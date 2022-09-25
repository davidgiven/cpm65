	.include "xfcb.inc"
	.include "cpm65.inc"

	.import BDOS
	.import xfcb_prepare

.export xfcb_close
.proc xfcb_close
	jsr xfcb_prepare
	ldy #bdos::close_file
	jmp BDOS
.endproc

