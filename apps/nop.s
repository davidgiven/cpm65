	.include "cpm65.inc"
	.include "zif.inc"

	.zeropage

index: .byte 0

	.code
	CPM65_COM_HEADER

	lda #0
	sta index
	zrepeat
		ldy index
		lda FCB+0, y
		jsr print_hex_number
		jsr space

		inc index
		lda index
		cmp #128
	zuntil_eq
	rts

; Prints an 8-bit hex number in A.
.proc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr h4
    pla
h4:
    and #%00001111
    ora #'0'
    cmp #'9'+1
	zif_cs
		adc #6
	zendif
   	pha
	jsr bdos_CONOUT
	pla
	rts
.endproc

space:
	lda #' '
	jmp bdos_CONOUT

newline:
	lda #13
	jsr bdos_CONOUT
	lda #10
	; fall through
bdos_CONOUT:
	ldy #bdos::console_output
	jmp BDOS

bdos_WRITESTRING:
	ldy #bdos::write_string
	jmp BDOS

	.data
msg:
	.byte "Hello, world!", 13, 10, 0

