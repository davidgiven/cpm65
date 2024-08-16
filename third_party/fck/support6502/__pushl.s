;
;	Push a word from XA
;
;	On 6502 this is far uglier as you can't conveniently ripple
;	dec the way you can inc
;
	.export __pushl
	.export __pushl0
	.export __pushl0a
	.export __pushlw

	.code

__pushl:
	sta	@tmp1
	lda	@sp
	sec
	sbc	#4
	sta	@sp
	bcc	l1
	dec	@sp+1
l1:	ldy	#3
	lda	@__hireg+1
	sta	(@sp),y
	dey
	lda	@__hireg
	sta	(@sp),y
	dey
	txa
	sta	(@sp),y
	lda	@tmp1
	dey
	sta	(@sp),y
	rts

; The compiler knows that this routine does not damage XA and returns
; Y = 0
;
; This routine is fairly slow so the compiler tries quite hard to avoid
; having to use it. For things like function arguments though it's
; unavoidable
;
; Need to look at more uses of folding cast of long and push into pushlw
;
__pushl0:
	lda	#0
__pushl0a:
	ldx	#0
__pushlw:
	sta	@tmp1
	lda	@sp
	sec
	sbc	#4
	sta	@sp
	bcc	l2
	dec	@sp+1
l2:	ldy	#3
	lda	#0
	sta	(@sp),y
	dey
	sta	(@sp),y
	dey
	txa
	sta	(@sp),y
	lda	@tmp1
	sta	(@sp),y
	rts			; XA is value Y is 0
