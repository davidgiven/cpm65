	.include "xfcb.inc"
	.include "cpm65.inc"

	.importzp __fcb

.export xfcb_get
xfcb_get:
	lda __fcb+0
	ldx __fcb+1
	rts

