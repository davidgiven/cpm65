	ldy #9
	lda #>msg
	ldx #<msg
	jmp BDOS

msg:
	.ascii "Hello, world!"
	.byte 13, 10, 0


