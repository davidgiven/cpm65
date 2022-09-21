	.include "cpm65.inc"
	.include "zif.inc"

	.zeropage
cmdoffset:	.byte 0	; current offset into command line (not including size byte)
fcb:		.word 0 ; current FCB being worked on

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

		; Parse it.

		lda #0
		sta cmdoffset
		lda #<cmdfcb
		ldx #>cmdfcb
		jsr parse_fcb


	zendloop

    ldy #bdos::exit_program
    jmp BDOS

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
		cpy #fcb::rc
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

.proc skip_whitespace
	zloop
		ldy cmdoffset
		lda cmdline+1, y
		cmp #' '
		zbreakif_ne
		iny
	zendloop
	rts
.endproc

newline:
	lda #13
	jsr bdos_CONOUT
	lda #10
	jmp bdos_CONOUT

bdos_GETDRIVE:
	ldy #bdos::get_current_drive
	jmp BDOS

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

	.bss
cmdline: .res 128	; command line buffer
cmdfcb:  .res 33	; FCB of command

; vim; ts=4 sw=4 et filetype=asm

