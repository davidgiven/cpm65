	.code

	.export __andspy0
	.export __andspy0s
	.export __andspy
	.export __andspys
__andspy0:
__andspy0s:
	ldy #0
__andspy:
__andspys:
	and (@sp),y
	pha
	txa
	iny
	and (@sp),y
	tax
	pla
	rts
