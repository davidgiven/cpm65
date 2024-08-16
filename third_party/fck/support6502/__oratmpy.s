	.code

	.export __oratmpy0
	.export __oratmpy0s
	.export __oratmpy
	.export __oratmpys
__oratmpy0:
__oratmpy0s:
	ldy #0
__oratmpy:
__oratmpys:
	ora (@tmp),y
	pha
	txa
	iny
	ora (@tmp),y
	tax
	pla
	rts
