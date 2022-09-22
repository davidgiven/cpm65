	.include "xfcb.inc"
	.include "cpm65.inc"

	.importzp __fcb
	.import BDOS
	.import xfcb_get
	.import xfcb_set
	.import xfcb_prepare
	.import xfcb_clear

.export xfcb_readsequential
.proc xfcb_readsequential
	jsr xfcb_prepare
	ldy #bdos::read_sequential
	jmp BDOS
.endproc

