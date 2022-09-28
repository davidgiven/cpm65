	.include "xfcb.inc"
	.include "cpm65.inc"
	.include "zif.inc"

	.importzp __fcb

.export xfcb_clear
; Preserves XA.
xfcb_clear:
	pha
	lda #0
	;ldy #xfcb::s2   ; this one is actually cleared by the BDOS
	;sta (__fcb), y

	ldy #xfcb::ex
	lda #0
	zrepeat
		sta (__fcb), y
		iny
		cpy #xfcb::r2+1
	zuntil_eq

	pla
	rts


