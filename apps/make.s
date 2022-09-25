	.include "cpm65.inc"
	.include "zif.inc"
	.include "xfcb.inc"

	.import xfcb_writesequential
	.import xfcb_readsequential
	.import xfcb_make
	.import xfcb_close

	.zeropage

address: .res 3
index:	 .res 1

	.code
	CPM65_COM_HEADER

.scope
	; Did we get a parameter?

	lda FCB+xfcb::f1
	cmp #' '
	beq syntax_error

	; Try and create the file.

	lda #<FCB
	ldx #>FCB
	jsr xfcb_make
	bcs cannot_open

	; Write some garbage to it.

	lda #<testdata
	ldx #>testdata
	jsr bdos_SETDMA

	lda #<FCB
	ldx #>FCB
	jsr xfcb_writesequential

	; Close the file.

	lda #<FCB
	ldx #>FCB
	jsr xfcb_close

	rts
.endscope

.data
testdata:
	.res 128, 'q'
.code

.proc syntax_error
	lda #<msg
	ldx #>msg
	jmp bdos_WRITESTRING
msg:
	.byte "Syntax error", 13, 10, 0
.endproc

.proc cannot_open
	lda #<msg
	ldx #>msg
	jmp bdos_WRITESTRING
msg:
	.byte "Cannot create file", 13, 10, 0
.endproc

newline:
	lda #13
	jsr bdos_CONOUT
	lda #10
	; fall through
bdos_CONOUT:
	ldy #bdos::console_output
	jmp BDOS

bdos_SETDMA:
	ldy #bdos::set_dma_address
	jmp BDOS

bdos_WRITESTRING:
	ldy #bdos::write_string
	jmp BDOS

