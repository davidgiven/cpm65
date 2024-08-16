	.code

	.export __and
	.export __ands
	.export __andtmp
	.export __andtmps
__and:
__ands:
	jsr __poptmp
__andtmp:
__andtmps:
	and @tmp
	pha
	txa
	and @tmp+1
	tax
	pla
	rts
