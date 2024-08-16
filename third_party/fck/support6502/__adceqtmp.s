	.code

	.export __adctmp
	.export __adctmps
__adctmp:
__adctmps:
	ldy #0
	clc
	adc (@tmp),y
	sta (@tmp),y
	pha
	txa
	iny
	adc (@tmp),y
	sta (@tmp),y
	tax
	pla
	rts
