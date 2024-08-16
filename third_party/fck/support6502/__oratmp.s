	.code

	.export __ora
	.export __oras
	.export __oratmp
	.export __oratmps
__ora:
__oras:
	jsr __poptmp
__oratmp:
__oratmps:
	ora @tmp
	pha
	txa
	ora @tmp+1
	tax
	pla
	rts
