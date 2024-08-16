	.code

	.export __eorspy0
	.export __eorspy0s
	.export __eorspy
	.export __eorspys
__eorspy0:
__eorspy0s:
	ldy #0
__eorspy:
__eorspys:
	eor (@sp),y
	pha
	txa
	iny
	eor (@sp),y
	tax
	pla
	rts
