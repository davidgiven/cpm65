	.include "xfcb.inc"
	.include "cpm65.inc"

	.import BDOS
	.import xfcb_prepare

.export xfcb_readrandom
.proc xfcb_readrandom
	jsr xfcb_prepare
	ldy #bdos::read_random
	jmp BDOS
.endproc

