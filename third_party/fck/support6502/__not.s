;
;	Turn XA into 0 or 1 and flags
;

	.export __not
__not:
	stx @tmp
	ldx #0
	ora @tmp
	beq setit
	txa
	rts
setit:
	lda #1
	rts
