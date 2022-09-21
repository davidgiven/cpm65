	.include "cpm65.inc"
	.include "zif.inc"

	.zeropage
cmdoffset:	.byte 0	; current offset into command line (not including size byte)
fcb:		.word 0 ; current FCB being worked on
temp:		.word 0

	.code
	CPM65_COM_HEADER

	zloop
		; Print prompt.

		jsr bdos_GETDRIVE
		clc
		adc #'A'
		jsr bdos_CONOUT
		lda #'>'
		jsr bdos_CONOUT

		; Read command line.

		lda #127
		sta cmdline
		lda #<cmdline
		ldx #>cmdline
		jsr bdos_READLINE

		; Zero terminate it.

		ldy cmdline
		lda #0
		sta cmdline+1, y

		; Convert to uppercase.

		ldy #0
		zrepeat
			lda cmdline+1, y
			cmp #'a'
			zif_cs
				cmp #'z'+1
				zif_cc
					and #$5f
				zendif
			zendif
			sta cmdline+1, y
			iny
			cpy cmdline
		zuntil_eq

		; Empty command line?

		lda #0
		sta cmdoffset
		jsr skip_whitespace			; leaves cmdoffset in X
		lda cmdline+1, x
		zif_eq
			jsr newline
			zcontinue
		zendif
	
		; Parse it.

		lda #<cmdfcb
		ldx #>cmdfcb
		jsr parse_fcb

		; Decode.

		jsr decode_command
		jsr execute_command
	zendloop

    ldy #bdos::exit_program
    jmp BDOS

execute_command:
	tax
	lda commands_hi, x
	pha
	lda commands_lo, x
	pha
	rts

commands_lo:
	.lobytes entry_DIR - 1
	.lobytes entry_ERA - 1
	.lobytes entry_TYPE - 1
	.lobytes entry_SAVE - 1
	.lobytes entry_REN - 1
	.lobytes entry_USER - 1
	.lobytes entry_TRANSIENT - 1
commands_hi:
	.hibytes entry_DIR - 1
	.hibytes entry_ERA - 1
	.hibytes entry_TYPE - 1
	.hibytes entry_SAVE - 1
	.hibytes entry_REN - 1
	.hibytes entry_USER - 1
	.hibytes entry_TRANSIENT - 1

.proc invalid_filename
	lda #<msg
	ldx #>msg
	jmp bdos_WRITESTRING
msg:
	.byte "Invalid filename", 13, 10, 0
.endproc

.proc cannot_open
	lda #<msg
	ldx #>msg
	jmp bdos_WRITESTRING
msg:
	.byte "Cannot open file", 13, 10, 0
.endproc

.proc entry_DIR
	rts
.endproc

.proc entry_ERA
	rts
.endproc

.proc entry_TYPE
	jsr newline

	lda #<userfcb
	ldx #>userfcb
	jsr parse_fcb
	zif_cs
		jmp invalid_filename
	zendif
	
	; Open the FCB.

	lda #<userfcb
	ldx #>userfcb
	jsr bdos_OPENFILE
	zif_cs
		jmp cannot_open
	zendif
	
	; Read and print it.

	zloop
		lda #<cmdline
		ldx #>cmdline
		jsr bdos_SETDMA

		lda #<userfcb
		ldx #>userfcb
		jsr bdos_READSEQUENTIAL
		zbreakif_cs

		ldy #128
		sty temp
		zrepeat
			ldy temp
			lda cmdline-128, y
			cmp #26
			beq exit
			jsr bdos_CONOUT

			inc temp
		zuntil_eq
	zendloop
exit:
	jmp newline
.endproc

.proc entry_SAVE
	rts
.endproc

.proc entry_REN
	rts
.endproc

.proc entry_USER
	rts
.endproc

.proc entry_TRANSIENT
	rts
.endproc

; Decodes the cmdfcb, checking for one of the intrinsic commands.
.proc decode_command
	ldx #0					; cmdtable index
	zrepeat
		ldy #0				; FCB index
		zrepeat
			lda cmdtable, x
			cmp cmdfcb+fcb::f1, y
			bne next_command
			inx
			iny
			cpy #4
		zuntil_eq
		dex					; compensate for next_command
		lda cmdfcb+fcb::f5
		cmp #' '
		beq exit
	next_command:
		txa
		and #<~3
		clc
		adc #4
		tax
	
		lda cmdtable, x
	zuntil_eq
exit:
	txa
	lsr a
	lsr a
	rts

cmdtable:
	.byte "DIR "
	.byte "ERA "
	.byte "TYPE"
	.byte "SAVE"
	.byte "REN "
	.byte "USER"
	.byte 0
.endproc

; Parses text at cmdoffset into the fcb at XA, which becomes the
; current one.
.proc parse_fcb
	sta fcb+0
	stx fcb+1
	jsr skip_whitespace

	; Wipe FCB.

	ldy #fcb::dr
	tya
	sta (fcb), y				; drive
	lda #' '
	zrepeat						; 11 bytes of filename
		iny
		sta (fcb), y
		cpy #fcb::t3
	zuntil_eq
	lda #0
	zrepeat						; 4 bytes of metadata
		iny
		sta (fcb), y
		cpy #fcb::cr
	zuntil_eq

	; Check for drive.

	ldx cmdoffset
	lda cmdline+1, x			; drive letter
	zif_eq
		sec
		rts
	zendif
	ldy cmdline+2, x
	cpy #':'					; colon?
	zif_eq
		sec
		sbc #'A'-1				; to 1-based drive
		cmp #16
		zif_cs          		; out of range drive
			rts
		zendif
		ldy #fcb::dr
		sta (fcb), y			; store

		inx
		inx
	zendif

	; Read the filename.

	; x = cmdoffset
	ldy #fcb::f1
	zloop
		lda cmdline+1, x		; get a character
		beq exit				; end of line
		cpy #fcb::f8+1
		zbreakif_eq
		cmp #' '
		beq exit
		cmp #'.'
		zbreakif_eq
		cmp #'*'
		zif_eq
			; Turn "ABC*.X" -> "ABC?????.X"
			lda #'?'
			dex					; reread the * again next time
		zendif
		jsr is_valid_filename_char
		bcs invalid_fcb
		sta (fcb), y
		iny
		inx
	zendloop
	; A is the character just read
	; X is cmdoffset

	; Skip non-dot filename characters.

	zloop
		cmp #'.'
		zbreakif_eq

		inx
		lda cmdline+1, x
		beq exit
		cmp #' '
		beq exit

		jsr is_valid_filename_char
		bcs invalid_fcb
	zendloop
	; A is the character just read
	; X is cmdoffset

	; Read the extension

	inx							; skip dot
	ldy #fcb::t1
	zloop
		lda cmdline+1, x		; get a character
		beq exit				; end of line
		cpy #fcb::t3+1
		zbreakif_eq
		cmp #' '
		beq exit
		cmp #'.'
		zbreakif_eq
		cmp #'*'
		zif_eq
			; Turn "ABC.X*" -> "ABC.X*"
			lda #'?'
			dex					; reread the * again next time
		zendif
		jsr is_valid_filename_char
		bcs invalid_fcb
		sta (fcb), y
		iny
		inx
	zendloop
		
	; Discard any remaining filename characters.

	zloop
		cmp #'.'
		zbreakif_eq

		inx
		lda cmdline+1, x
		beq exit
		cmp #' '
		beq exit

		jsr is_valid_filename_char
		bcs invalid_fcb
	zendloop

	; Now A contains the terminating character --- either a space or \0.  We
	; have a valid FCB!

exit:
	stx cmdoffset				; update cmdoffset
	clc
	rts

invalid_fcb:
	sec
	rts

is_valid_filename_char:
	cmp #32
	bcc invalid_fcb
	cmp #127
	bcs invalid_fcb
	cmp #'='
	beq invalid_fcb
	cmp #':'
	beq invalid_fcb
	cmp #';'
	beq invalid_fcb
	cmp #'<'
	beq invalid_fcb
	cmp #'>'
	beq invalid_fcb
	clc
	rts

.endproc

; Leaves the updated cmdoffset in X.
.proc skip_whitespace
	ldx cmdoffset
	zloop
		lda cmdline+1, x
		cmp #' '
		zbreakif_ne
		inx
	zendloop
	stx cmdoffset
	rts
.endproc

bdos_SETDMA:
	ldy #bdos::set_dma_address
	jmp BDOS

bdos_OPENFILE:
	ldy #bdos::open_file
	jmp BDOS

bdos_READSEQUENTIAL:
	ldy #bdos::read_sequential
	jmp BDOS

bdos_GETDRIVE:
	ldy #bdos::get_current_drive
	jmp BDOS

bdos_CONIN:
	ldy #bdos::console_input
	jmp BDOS

newline:
	lda #13
	jsr bdos_CONOUT
	lda #10
	; fall through
bdos_CONOUT:
	ldy #bdos::console_output
	jmp BDOS

bdos_READLINE:
	ldy #bdos::read_line
	jmp BDOS

bdos_WRITESTRING:
	ldy #bdos::write_string
	jmp BDOS

	.bss
cmdline: .res 128	; command line buffer
cmdfcb:  .res 33	; FCB of command
userfcb: .res 33	; parameter FCB

; vim; ts=4 sw=4 et filetype=asm

