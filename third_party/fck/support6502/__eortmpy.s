	.code

	.export __eortmpy0
	.export __eortmpy0s
	.export __eortmpy
	.export __eortmpys
__eortmpy0:
__eortmpy0s:
	ldy #0
__eortmpy:
__eortmpys:
	eor (@tmp),y
	pha
	txa
	iny
	eor (@tmp),y
	tax
	pla
	rts
