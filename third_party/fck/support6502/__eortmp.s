	.code

	.export __eor
	.export __eors
	.export __eortmp
	.export __eortmps
__eor:
__eors:
	jsr __poptmp
__eortmp:
__eortmps:
	eor @tmp
	pha
	txa
	eor @tmp+1
	tax
	pla
	rts
