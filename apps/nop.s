	.include "cpm65.inc"

	.code
	CPM65_COM_HEADER

	lda #<msg
	ldx #>msg
	jsr bdos_WRITESTRING

    ldy #bdos::exit_program
    jmp BDOS

bdos_WRITESTRING:
	ldy #bdos::write_string
	jmp BDOS

	.data
msg:
	.byte "Hello, world!", 13, 10, 0

