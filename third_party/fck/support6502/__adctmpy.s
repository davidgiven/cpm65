	.code

	.export __adctmpy0
	.export __adctmpy0s
	.export __adctmpy
	.export __adctmpys
__adctmpy0:
__adctmpy0s:
	ldy #0
__adctmpy:
__adctmpys:
	clc
	adc (@tmp),y
	pha
	txa
	iny
	adc (@tmp),y
	tax
	pla
	rts
