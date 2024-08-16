	.code

	.export __sbc
	.export __sbcs
	.export __sbctmp
	.export __sbctmps
__sbc:
__sbcs:
	jsr __poptmp
__sbctmp:
__sbctmps:
	sec
	sbc @tmp
	pha
	txa
	sbc @tmp+1
	tax
	pla
	rts
