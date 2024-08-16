;
;	Push a word from XA
;
;	On 6502 this is far uglier as you can't conveniently ripple
;	dec the way you can inc
;
	.export __push
	.export __push0a
	.export __push0
	.export __push1
	.export __pushffff

__pushffff:
	lda	#0xFF
	tax
	bne	__push
__push1:
	lda	#1
	bne	__push0a
__push0:
	lda	#0
__push0a:
	ldx	#0
__push:
	sta	@tmp1
	lda	@sp
	sec
	sbc	#2
	sta	@sp
	bcc	l1
	dec	@sp+1
l1:	ldy	#1
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

