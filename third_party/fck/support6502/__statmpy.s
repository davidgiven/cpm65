	.code

	.export __statmpy0
	.export __statmpy0s
	.export __statmpy
	.export __statmpys
__statmpy0:
__statmpy0s:
	ldy #0
__statmpy:
__statmpys:
	sta (@tmp),y
	pha
	txa
	iny
	sta (@tmp),y
	tax
	pla
	rts
