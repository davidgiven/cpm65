;
;	XA is the pointer, add the amount given. These are used a lot
;

	.export	__plusplus1
	.code

__plusplus1:
	sta	@tmp
	stx	@tmp+1
	ldy	#1
	lda	(@tmp),y
	tax
	dey
	lda	(@tmp),y
	pha
	clc
	adc	#1
	sta	(@tmp),y
	dey
	txa
	adc	#0
	iny
	sta	(@tmp),y
l1:	rts		; alwayus exits with Y = 1, XA old value

