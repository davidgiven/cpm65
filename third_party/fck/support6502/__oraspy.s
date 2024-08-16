	.code

	.export __oraspy0
	.export __oraspy0s
	.export __oraspy
	.export __oraspys
__oraspy0:
__oraspy0s:
	ldy #0
__oraspy:
__oraspys:
	ora (@sp),y
	pha
	txa
	iny
	ora (@sp),y
	tax
	pla
	rts
