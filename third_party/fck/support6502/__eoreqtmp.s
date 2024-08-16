	.code

	.export __eortmp
	.export __eortmps
__eortmp:
__eortmps:
	ldy #0
	eor (@tmp),y
	sta (@tmp),y
	pha
	txa
	iny
	eor (@tmp),y
	sta (@tmp),y
	tax
	pla
	rts
