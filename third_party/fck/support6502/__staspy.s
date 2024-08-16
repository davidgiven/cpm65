	.code

	.export __staspy0
	.export __staspy0s
	.export __staspy
	.export __staspys
__staspy0:
__staspy0s:
	ldy #0
__staspy:
__staspys:
	sta (@sp),y
	pha
	txa
	iny
	sta (@sp),y
	tax
	pla
	rts
