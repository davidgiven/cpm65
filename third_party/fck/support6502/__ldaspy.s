	.code

	.export __ldaspy0
	.export __ldaspy0s
	.export __ldaspy
	.export __ldaspys
__ldaspy0:
__ldaspy0s:
	ldy #0
__ldaspy:
__ldaspys:
	lda (@sp),y
	pha
	txa
	iny
	lda (@sp),y
	tax
	pla
	rts
