	.code

	.export __andtmpy0
	.export __andtmpy0s
	.export __andtmpy
	.export __andtmpys
__andtmpy0:
__andtmpy0s:
	ldy #0
__andtmpy:
__andtmpys:
	and (@tmp),y
	pha
	txa
	iny
	and (@tmp),y
	tax
	pla
	rts
