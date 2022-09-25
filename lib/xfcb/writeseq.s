	.include "xfcb.inc"
	.include "cpm65.inc"

	.import BDOS
	.import xfcb_prepare

.export xfcb_writesequential
.proc xfcb_writesequential
	jsr xfcb_prepare
	ldy #bdos::write_sequential
	jmp BDOS
.endproc

