;
;	16bit signed/unsigned subtraction. The 16 + 8bit constant case
;	is handled elsewhere as are direct xa + local/const forms.
;
;
; From CC65 modified for Fuzix Compiler Kit
;
; Ullrich von Bassewitz, 05.08.1998
;
; CC65 runtime: sub ints
;
;	TODO 65C02 support lib
;
	.export __minus

__minus:
	sec
	eor	#$FF
	ldy	#0
	adc	(sp),y
	iny
	sta	@tmp
	txa
	eor	#$FF
	adc	(sp),y
	tax
	lda	@tmp
	jmp	__addysp1
