	.include "cpm65.inc"
	.include "zif.inc"

	.zeropage
count:	.byte 0

	.code
	CPM65_COM_HEADER

	zloop
		lda #<message
		ldx #>message
		jsr bdos_WRITESTRING

		lda #7
		sta buffer
		lda #<buffer
		ldx #>buffer
		jsr bdos_READLINE
		jsr newline

		lda #0
		sta count
		zloop
			ldy count
			cpy buffer
			zbreakif_eq

			iny
			lda buffer, y
			jsr bdos_CONOUT
			inc count
		zendloop
		jsr newline
	zendloop

    ldy #bdos::exit_program
    jmp BDOS


newline:
	lda #13
	jsr bdos_CONOUT
	lda #10
	jmp bdos_CONOUT

bdos_CONIN:
	ldy #bdos::console_input
	jmp BDOS

bdos_CONOUT:
	ldy #bdos::console_output
	jmp BDOS

bdos_READLINE:
	ldy #bdos::read_line
	jmp BDOS

bdos_WRITESTRING:
	ldy #bdos::write_string
	jmp BDOS

message:
	.byte "Type something: ", 0

	.bss
buffer:
	.res 128

