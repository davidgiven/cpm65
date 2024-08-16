;
;	Pop a 16hit value from stack into XA, preserve XA. Leaves Y as 0
;
;	Based on code by Ullrich von Bassetwitz for CC65
;
	.export __poptmp
	.export __incsp2
	.code

__poptmp:
	pha
	ldy	#1
	lda	(@sp),y
	sta	@tmp+1
	dey
	lda	(@sp),y
	sta	@tmp
	pla
__incsp2:
	; +2 can only overflow once
	inc	@sp
	beq	l1
	inc	@sp
	beq	l2
	rts
l1:	inc	@sp
l2:	inc	@sp+1
	rts
