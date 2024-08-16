;
;	We do -= differently to the others as it is not commutive. Instead
;	we negate the value and add
;
;	Based on code from Ullrich von Bassewitz for CC65
;
	.export	__minuseq
	.export __minusequ

__minuseq:
__minusequ:
	ldy	#0
	eor	#0xFF
	sec
	adc	(@tmp),y
	sta	(@tmp),y
	pha
	iny
	txa
	eor	#0xFF
	adc	(@tmp),y
	sta	(@tmp),y
	tax
	pla
	rts
