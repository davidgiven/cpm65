	.include "xfcb.inc"
	.include "cpm65.inc"

	.import BDOS
	.import xfcb_prepare

.export xfcb_writerandom
.proc xfcb_writerandom
	jsr xfcb_prepare
	ldy #bdos::write_random
	jmp BDOS
.endproc

