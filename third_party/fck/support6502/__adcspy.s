	.code

	.export __adcspy0
	.export __adcspy0s
	.export __adcspy
	.export __adcspys
__adcspy0:
__adcspy0s:
	ldy #0
__adcspy:
__adcspys:
	clc
	adc (@sp),y
	pha
	txa
	iny
	adc (@sp),y
	tax
	pla
	rts
