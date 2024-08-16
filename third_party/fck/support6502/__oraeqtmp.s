	.code

	.export __oratmp
	.export __oratmps
__oratmp:
__oratmps:
	ldy #0
	ora (@tmp),y
	sta (@tmp),y
	pha
	txa
	iny
	ora (@tmp),y
	sta (@tmp),y
	tax
	pla
	rts
