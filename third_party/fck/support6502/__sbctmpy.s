	.code

	.export __sbctmpy0
	.export __sbctmpy0s
	.export __sbctmpy
	.export __sbctmpys
__sbctmpy0:
__sbctmpy0s:
	ldy #0
__sbctmpy:
__sbctmpys:
	sec
	sbc (@tmp),y
	pha
	txa
	iny
	sbc (@tmp),y
	tax
	pla
	rts
