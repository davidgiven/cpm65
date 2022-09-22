	.include "xfcb.inc"
	.include "cpm65.inc"

	.importzp __fcb

.export xfcb_set
xfcb_set:
	sta __fcb+0
	stx __fcb+1
	rts

