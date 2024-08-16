	.text

	.export __sbctmp
	.export __sbctmps
__sbctmp:
__sbctmps:
	ldy #0
	sec
	sbc (@tmp),y
	sta (@tmp),y
	pha
	txa
	iny
	sbc (@tmp),y
	sta (@tmp),y
	tax
	pla
	rts
