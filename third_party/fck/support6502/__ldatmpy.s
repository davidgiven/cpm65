	.code

	.export __ldatmpy0
	.export __ldatmpy0s
	.export __ldatmpy
	.export __ldatmpys
__ldatmpy0:
__ldatmpy0s:
	ldy #0
__ldatmpy:
__ldatmpys:
	lda (@tmp),y
	pha
	txa
	iny
	lda (@tmp),y
	tax
	pla
	rts
