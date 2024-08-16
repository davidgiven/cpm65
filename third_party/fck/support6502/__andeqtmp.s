	.code

	.export __andtmp
	.export __andtmps
__andtmp:
__andtmps:
	ldy #0
	and (@tmp),y
	sta (@tmp),y
	pha
	txa
	iny
	and (@tmp),y
	sta (@tmp),y
	tax
	pla
	rts
