;
;	16bit signed/unsigned addition. The 16 + 8bit constant case
;	is handled elsewhere as are direct xa + local/const forms.
;
;
; From CC65 modified for Fuzix Compiler Kit
;
; Ullrich von Bassewitz, 05.08.1998
; Christian Krueger, 11-Mar-2017, spend two bytes for one cycle, improved 65SC02 optimization
;
; CC65 runtime: add ints
;
; Make this as fast as possible, even if it needs more space since it's
; called a lot!
;
;	TODO 65C02 support lib
;
	.export __plus

__plus:
	ldy	#0
	adc	(@sp),y
	iny
	sta	@tmp1		; tmp1 is for helpers so the compiler
	txa			; can track tmp contents in future
	adc	(@sp),y
	tax
	clc
	lda	@sp
	adc	#2
	sta	@sp
	bcc	l1
	inc	@sp+1
l1:	lda	@tmp1
	rts			; 45 cycles, 26 bytes

