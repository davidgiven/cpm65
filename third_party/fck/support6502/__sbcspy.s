	.code

	.export __sbcspy0
	.export __sbcspy0s
	.export __sbcspy
	.export __sbcspys
__sbcspy0:
__sbcspy0s:
	ldy #0
__sbcspy:
__sbcspys:
	sec
	sbc (@sp),y
	pha
	txa
	iny
	sbc (@sp),y
	tax
	pla
	rts
