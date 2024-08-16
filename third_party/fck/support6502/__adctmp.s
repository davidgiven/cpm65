	.code

	.export __adc
	.export __adcs
	.export __adctmp
	.export __adctmps
__adc:
__adcs:
	jsr __poptmp
__adctmp:
__adctmps:
	clc
	adc @tmp
	pha
	txa
	adc @tmp+1
	tax
	pla
	rts
