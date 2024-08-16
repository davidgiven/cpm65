;
;	Push a byte from A
;
;	On 6502 this is far uglier as you can't conveniently ripple
;	dec the way you can inc
;
;	From code by Ullrich von Bassewitz for CC65
;
	.export __pushc1
	.export __pushc0
	.export __pushc

	.code

; It's surprisingly common to push 0 or 1
__pushc1:
	lda	#1
	bne	__pushc
__pushc0:
	lda	#0
__pushc:
	ldy	@sp
	beq	l1
	dec	@sp
	ldy	#0
	sta	(@sp),y
	rts
l1:
	dec	@sp+1
	dec	@sp
	sta	(@sp),y
	rts

; The compiler knows that this routine does not damage XA and returns
; Y = 0
