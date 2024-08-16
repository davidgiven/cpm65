;
;	General plusplus operation for 16bits. This one is used when
;	there are complex forms boht sides. In this case the top of the
;	data stack is the pointer

	.export	__plusplus
	.code

__plusplus:
	jsr	__poptmp	; pop TOS into @tmp, preserve XA
				; Y is set to 0 after this
	clc
	adc	(@tmp),y
	sta	(@tmp),y
	iny
	sta	@tmp1
	txa
	adc	(@tmp),y
	sta	(@tmp),y
	tax
	lda	@tmp1
	rts

