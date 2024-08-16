;
;	XA is the pointer, add the amount given. The other 8bit cases are
;	not such a hot path
;
	.export	__plusplus4
	.export	__plusplusy
	.code

__plusplus4:
	ldy	#4
__plusplusy:
	sty	@tmp1
	sta	@tmp
	stx	@tmp+1
	ldy	#1
	lda	(@tmp),y
	tax
	dey
	lda	(@tmp),y
	pha
	clc
	adc	@tmp1
	sta	(@tmp),y
	dey
	txa
	adc	#0
	sta	(@tmp),y
	pla
	rts
