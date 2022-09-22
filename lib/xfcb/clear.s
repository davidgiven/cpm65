	.include "xfcb.inc"
	.include "cpm65.inc"

	.importzp __fcb

.export xfcb_clear
; Preserves XA.
xfcb_clear:
	pha
	lda #0
	;ldy #xfcb::s2   ; this one is actually cleared by the BDOS
	;sta (__fcb), y
	ldy #xfcb::ex
	sta (__fcb), y
	ldy #xfcb::cr
	sta (__fcb), y
	pla
	rts


