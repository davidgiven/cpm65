
\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.bss pblock, 165
cpm_fcb = pblock
cpm_default_dma = pblock + 0x25

BDOS_WARMBOOT          =  0
BDOS_CONIN             =  1
BDOS_CONOUT            =  2
BDOS_AUXIN             =  3
BDOS_AUXOUT            =  4
BDOS_LSTOUT            =  5
BDOS_CONIO             =  6
BDOS_GET_IOBYTE        =  7
BDOS_SET_IOBYTE        =  8
BDOS_PRINTSTRING       =  9
BDOS_READLINE          = 10
BDOS_CONST             = 11
BDOS_GET_VERSION       = 12
BDOS_RESET_DISK_SYSTEM = 13
BDOS_SELECT_DRIVE      = 14
BDOS_OPEN_FILE         = 15
BDOS_CLOSE_FILE        = 16
BDOS_FINDFIRST         = 17
BDOS_FINDNEXT          = 18
BDOS_DELETE_FILE       = 19
BDOS_READ_SEQUENTIAL   = 20
BDOS_WRITE_SEQUENTIAL  = 21
BDOS_MAKE_FILE         = 22
BDOS_RENAME_FILE       = 23
BDOS_GET_LOGIN_VECTOR  = 24
BDOS_GET_CURRENT_DRIVE = 25
BDOS_SET_DMA           = 26
BDOS_GET_ALLOC_VECTOR  = 27
BDOS_WRITE_PROT_DRIVE  = 28
BDOS_GET_READONLY_VEC  = 29
BDOS_SET_FILE_ATTRS    = 30
BDOS_GET_DPB           = 31
BDOS_GET_SET_USER      = 32
BDOS_READ_RANDOM       = 33
BDOS_WRITE_RANDOM      = 34
BDOS_SEEK_TO_END       = 35
BDOS_SEEK_TO_SEQ_POS   = 36
BDOS_RESET_DRIVES      = 37
BDOS_WRITE_RANDOM_FILL = 40

FCB_DR = 0x00
FCB_F1 = 0x01
FCB_F2 = 0x02
FCB_F3 = 0x03
FCB_F4 = 0x04
FCB_F5 = 0x05
FCB_F6 = 0x06
FCB_F7 = 0x07
FCB_F8 = 0x08
FCB_T1 = 0x09
FCB_T2 = 0x0a
FCB_T3 = 0x0b
FCB_EX = 0x0c
FCB_S1 = 0x0d
FCB_S2 = 0x0e
FCB_RC = 0x0f
FCB_AL = 0x10
FCB_CR = 0x20
FCB_R0 = 0x21
FCB_R1 = 0x22
FCB_R2 = 0x23
FCB_SIZE = 0x24

BDOS = start - 3
start:
.expand 1

.zp ptr1, 2
.zp ptr2, 2
.zp current_line, 2
.zp line_length, 1
.zp line_number, 2
.zp io_ptr, 1

.label load_file
.label putchar
.label crlf

.bss line_buffer, 128
.bss text_start, 0

.zproc main
	lda #<cpm_default_dma
	ldx #>cpm_default_dma
	ldy #BDOS_SET_DMA
	jsr BDOS

	jsr load_file
.zendproc
	\ fall through
.zproc mainloop
	ldx #0xff
	txs

	.zloop
		lda #'>'
		jsr putchar

		lda #0x80
		sta cpm_default_dma
		lda #<cpm_default_dma+0
		ldx #>cpm_default_dma+1
		ldy #BDOS_READLINE
		jsr BDOS

		jsr crlf
	.zendloop
.zendproc

.zproc putchar
	ldy #BDOS_CONOUT
	jmp BDOS
.zendproc

.zproc crlf
	lda #0x0d
	jsr putchar

	lda #0x0a
	jmp putchar
.zendproc

\ Processes a simple error. The text string must immediately follow the
\ subroutine call.

.zproc error
	pla
	tay
	pla
	tax
	tya

	ldy #BDOS_PRINTSTRING
	jsr BDOS
	jsr crlf

	jmp mainloop
.zendproc

\ Sets ptr1 to point at the terminating 0 at the end of the document.

.zproc find_end_of_document
	lda current_line+0
	sta ptr1+0
	lda current_line+1
	sta ptr1+1

	ldy #0
	.zloop
		lda (ptr1), y
		.zif eq
			rts
		.zendif

		clc
		adc current_line+0
		sta current_line+0
		.zif cs
			inc current_line+1
		.zendif
	.zendloop
.zendproc

\ Sets up a new, empty document.

.zproc new_file
	lda #<text_start
	sta current_line+0
	lda #>text_start
	sta current_line+1

	lda #0
	sta text_start
	rts
.zendproc

\ Inserts the contents of line_buffer into the current document before the
\ current line. The line number is unset.

.zproc insert_line
	jsr find_end_of_document \ sets ptr1

	\ Calculate the new end-of-document based on the changed line length.

	lda line_length
	clc
	adc #3				\ cannot overflow
	adc ptr1+0
	sta ptr2+0
	lda ptr1+1
	adc #0
	sta ptr2+1

	\ Open up space.

	ldy #0
	.zloop
		lda (ptr1), y
		sta (ptr2), y

		lda ptr1+0
		cmp current_line+0
		.zif eq
			lda ptr1+1
			cmp current_line+1
			.zbreak eq
		.zendif

		dec ptr1+0
		.zif cs
			dec ptr1+1
		.zendif

		dec ptr2+0
		.zif cs
			dec ptr2+1
		.zendif
	.zendloop

	\ We now have space for the new line, plus the header. Populate said header.

	lda line_length
	clc
	adc #3
	sta (current_line), y

	\ Copy the data in from the line buffer.

	ldx #0
	ldy #3
	.zloop
		cpx line_length
		.zbreak eq

		lda line_buffer, x
		sta (current_line), y
		iny
		inx
	.zendloop

	\ Advance the current line.

label:
	ldy #0
	lda (current_line), y
	clc
	adc current_line+0
	sta current_line+0
	.zif cs
		inc current_line+1
	.zendif

	\ Done. Reset the line buffer.
	\ (y is zero)

	sty line_length

	rts
.zendproc

\ Renumbers the document.

.zproc renumber_file
	lda #<text_start
	sta ptr1+0
	lda #>text_start
	sta ptr1+1

	lda #10
	sta line_number+0
	lda #0
	sta line_number+1

	.zloop
		ldy #0
		lda (ptr1), y		\ length of this line
		.zbreak eq			\ zero? end of file
		tax

		\ Update the line number in the text field.

		iny
		lda line_number+0
		sta (ptr1), y
		iny
		lda line_number+1
		sta (ptr1), y

		\ Increment the line number.

		clc
		lda line_number+0
		adc #10
		sta line_number+0
		.zif cs
			inc line_number+1
		.zendif

		\ Advance to the next line.

		clc
		txa
		adc ptr1+0
		sta ptr1+0
		.zif cs
			inc ptr1+1
		.zendif
	.zendloop

	rts
.zendproc

\ Reads the file pointed at by the FCB into memory.

.zproc load_file
	lda #0
	sta cpm_fcb+0x20

	lda #<cpm_fcb
	ldx #>cpm_fcb
	ldy #BDOS_OPEN_FILE
	jsr BDOS
	.zif cs
		jsr error
		.byte "Failed to load file", 0
	.zendif

	jsr new_file

	lda #10				\ start line number
	sta line_number+0
	lda #0
	sta line_number+1

	sta line_length
	sta io_ptr

	.zloop
		ldx io_ptr
		.zif eq
			lda #<cpm_fcb
			ldx #>cpm_fcb
			ldy #BDOS_READ_SEQUENTIAL
			jsr BDOS
			.zbreak cs
			ldx io_ptr
		.zendif

		lda cpm_default_dma, x

		cmp #0x1a
		.zbreak eq

		cmp #0x0d
		beq skip

		cmp #0x0a
		.zif eq
			\ insert line
			jsr insert_line
			jmp skip
		.zendif

		\ Insert character into line buffer.

		ldy line_length
		cpy #252
		.zif eq
			\ This line is already at the maximum length.
			jsr insert_line
			ldy #0
		.zendif

		sta line_buffer, y
		iny
		sty line_length

	skip:
		ldx io_ptr
		inx
		cpx #128
		.zif eq
			ldx #0
		.zendif
		stx io_ptr
	.zendloop

	jsr renumber_file
	rts
.zendproc
	


