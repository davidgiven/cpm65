	.include "cpm65.inc"
	.include "zif.inc"
	.include "xfcb.inc"

	.import xfcb_open
	.import xfcb_readsequential
	.import xfcb_erase

	.zeropage
cmdoffset:	.byte 0	; current offset into command line (not including size byte)
fcb:		.word 0 ; current FCB being worked on
temp:		.word 0

	.code
	CPM65_BARE_HEADER
.export BDOS
BDOS:
	jmp 0
ENTRY:

	ldy #bdos::get_bios
	jsr BDOS
	sta bios+0
	stx bios+1

	jsr bdos_GETDRIVE
	sta drive

	zloop
		; Print prompt.

		lda #$ff
		jsr bdos_GETSETUSER
		cmp #0
		zif_ne
			jsr print_dec_number
		zendif

		lda drive
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
		jsr newline

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
	.lobytes entry_FREE - 1
	.lobytes entry_REN - 1
	.lobytes entry_USER - 1
	.lobytes entry_TRANSIENT - 1
commands_hi:
	.hibytes entry_DIR - 1
	.hibytes entry_ERA - 1
	.hibytes entry_TYPE - 1
	.hibytes entry_FREE - 1
	.hibytes entry_REN - 1
	.hibytes entry_USER - 1
	.hibytes entry_TRANSIENT - 1

.proc parse_valid_user_fcb
	lda #<userfcb
	ldx #>userfcb
	jsr parse_fcb
	bcs invalid_filename
	rts
.endproc

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
	file_counter = temp+2
	index = temp+3

	; Parse the filename.

	jsr parse_valid_user_fcb

	; Just the drive?

	lda userfcb+xfcb::f1
	cmp #' '
	zif_eq
		; If empty FCB, fill with ????...

		ldx #10
		lda #'?'
		zrepeat
			sta userfcb+xfcb::f1, x
			dex
		zuntil_mi
	zendif

	; Set the drive.

	ldx userfcb+xfcb::dr
	dex
	zif_mi
		ldx drive
	zendif
	txa
	jsr bdos_SELECTDISK

	; Start iterating.

	lda #0
	sta file_counter

	lda #<cmdline
	ldx #>cmdline
	jsr bdos_SETDMA

	lda #<userfcb
	ldx #>userfcb
	jsr bdos_FINDFIRST
	bcs exit

	zrepeat
		; Get the offset of the directory item.

		asl a
		asl a
		asl a
		asl a
		asl a
		clc
		adc #<cmdline
		sta temp+0
		ldx #>cmdline
		zif_cs
			inx
		zendif
		stx temp+1

		; Skip if this is a system file.

		ldy #fcb::t2
		lda (temp), y
		and #$80				; check attribute bit
		zif_eq
			; Line header.

			ldx file_counter
			txa
			inx
			stx file_counter
			and #$01
			zif_eq
				jsr bdos_GETDRIVE
				clc
				adc #'A'
				jsr bdos_CONOUT
			zendif

			lda #':'
			jsr bdos_CONOUT
			jsr space
			
			; Print the filename.

			lda #8
			sta index
			zrepeat
				inc temp+0
				zif_eq
					inc temp+1
				zendif

				ldy #0
				lda (temp), y
				jsr bdos_CONOUT

				dec index
			zuntil_eq

			jsr space

			; Print the extension.

			lda #3
			sta index
			zrepeat
				inc temp+0
				zif_eq
					inc temp+1
				zendif

				ldy #0
				lda (temp), y
				jsr bdos_CONOUT

				dec index
			zuntil_eq

			jsr space

			lda file_counter
			and #$01
			zif_eq
				jsr newline
			zendif
		zendif

		; Get the next directory entry.

		lda #<userfcb
		ldx #>userfcb
		jsr bdos_FINDNEXT
	zuntil_cs

exit:
	jmp newline
.endproc

.proc entry_ERA
	jsr parse_valid_user_fcb

	; Just delete everything which matches.

	lda #<userfcb
	ldx #>userfcb
	jmp xfcb_erase
.endproc

.proc entry_TYPE
	jsr parse_valid_user_fcb
	
	; Open the FCB.

	lda #<userfcb
	ldx #>userfcb
	jsr xfcb_open
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
		jsr xfcb_readsequential
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

.proc entry_FREE
	lda #<msg_zp
	ldx #>msg_zp
	jsr bdos_WRITESTRING

	jsr bios_GETZP
	sta temp+0
	stx temp+1
	jsr print_hex_number
	jsr print_to
	lda temp+1
	jsr print_hex_number
	jsr print_free
	lda temp+1
	sec
	sbc temp+0
	jsr print_hex_number
	jsr newline

	lda #<msg_tpa
	ldx #>msg_tpa
	jsr bdos_WRITESTRING

	jsr bios_GETTPA
	sta temp+0
	stx temp+1
	jsr print_hex_number
	jsr print_zero
	jsr print_to
	lda temp+1
	jsr print_hex_number
	jsr print_zero
	jsr print_free
	lda temp+1
	sec
	sbc temp+0
	jsr print_hex_number
	jsr print_zero
	jsr newline

	lda #<msg_ccp
	ldx #>msg_ccp
	jsr bdos_WRITESTRING

	lda #>ENTRY
	jsr print_hex_number
	jsr print_zero
	jmp newline

print_zero:
	lda #0
	jmp print_hex_number

print_free:
	lda #<msg_free
	ldx #>msg_free
	jmp bdos_WRITESTRING

print_to:
	lda #<msg_to
	ldx #>msg_to
	jmp bdos_WRITESTRING

msg_zp:
	.byte "ZP: ", 0
msg_tpa:
	.byte "TPA: ", 0
msg_to:
	.byte " to ", 0
msg_free:
	.byte ". Free: ", 0
msg_ccp:
	.byte "CCP at: ", 0
.endproc

.proc entry_REN
	rts
.endproc

.proc entry_USER
	jsr parse_number
	bcs error

	cmp #16
	bcs error

	jmp bdos_GETSETUSER

error:
	lda #<msg
	ldx #>msg
	jmp bdos_WRITESTRING
msg:
	.byte "Bad number", 13, 10, 0
.endproc

.proc entry_TRANSIENT
	; Check for drive changes.

	lda cmdfcb + xfcb::f1
	cmp #' '
	zif_eq
		lda cmdfcb + xfcb::dr
		zif_eq
			sec
			sbc #1
			sta drive

			jmp bdos_SELECTDISK
		zendif
	zendif

	; If there's no .COM extension, add one.

	lda cmdfcb + xfcb::t1
	cmp #' '
	zif_eq
		ldy #2
		zrepeat
			lda com, y
			sta cmdfcb + xfcb::t1, y
			dey
		zuntil_mi
	zendif

	; Open the command.

	lda #<cmdfcb
	ldx #>cmdfcb
	jsr xfcb_open
	zif_cs
		ldy #0
		zrepeat
			lda cmdfcb + xfcb::f1, y
			cmp #' '
			zbreakif_eq
			iny
			cpy #8
		zuntil_eq

		lda #0
		sta cmdfcb + xfcb::f1, y
		lda #<(cmdfcb + xfcb::f1)
		ldx #>(cmdfcb + xfcb::f1)
		jsr bdos_WRITESTRING
		lda #'?'
		jsr bdos_CONOUT
		jmp newline
	zendif

	; Compute the start address.

	jsr bios_GETTPA			; leaves page number in A
	sta temp+1
	lda #0
	sta temp+0

    ; Read the file.

    zloop
		lda temp+0
		ldx temp+1
		jsr bdos_SETDMA
		lda #<cmdfcb
		ldx #>cmdfcb
        jsr bdos_READSEQUENTIAL
        zbreakif_cs

        lda temp+0
        eor #$80
        sta temp+0
        zif_eq
            inc temp+1
        zendif
    zendloop

	; Relocate the file.

	jsr bios_GETTPA
	tax
	lda #0
	stx temp+1
	sta temp+0
	jsr bdos_SETDMA
	jsr bios_GETZP
	tax						; ZP base
	lda temp+1				; memory page number
	jsr bios_RELOCATE

	; Patch the BDOS jump instruction.

	ldy #comhdr::bdos+0
	lda BDOS+1
	sta (temp), y
	iny
	lda BDOS+2
	sta (temp), y

	; Calculate address of the program's PBLOCK.

	lda #0
	sta temp+0				; restore temp to beginning of program

	ldy #comhdr::rel_offset+1
	lda (temp), y
	tax
	dey
	lda (temp), y			; XA = offset to PBLOCK

	sta temp+0
	stx temp+1

	; Save command line position.

	jsr skip_whitespace
	lda cmdoffset
	pha

	; Parse the command line into an FCB, if present.

	lda temp+0
	ldx temp+1
	jsr parse_fcb			; first parameter
	zif_cc
		lda temp+0
		clc
		adc #16
		ldx temp+1
		zif_cs
			inx
		zendif
		jsr parse_fcb		; second parameter
	zendif

	; Copy the command line into the program's PBLOCK.

	pla						; get save command line position
	sta cmdoffset
	tax
	ldy #.sizeof(xfcb) + 1
	zloop
		lda cmdline+1, x
		sta (temp), y
		zbreakif_eq
		inx
		iny
	zendloop

	txa						; set length of command line
	sec
	sbc cmdoffset
	ldy #.sizeof(xfcb)
	sta (temp), y

	; Run.

	jsr bios_GETTPA			; base address in A
	sta temp+1
	lda #comhdr::entry
	sta temp+0
	jsr calltemp

	; Reload disk.

	jsr bdos_GETDRIVE
	sta drive
	rts

calltemp:
	jmp (temp)

com:
	.byte "COM"

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
	.byte "FREE"
	.byte "REN "
	.byte "USER"
	.byte 0
.endproc

; Parses an 8-bit decimal number from the command line.
.proc parse_number
	jsr skip_whitespace

	lda #0
	sta temp+0

	ldx cmdoffset
	zloop
		lda cmdline+1, x
		beq exit
		cmp #' '
		beq exit

		cmp #'0'
		bcc error
		cmp #'9'+1
		bcs error

		sec
		sbc #'0'
		tay

		lda temp+0
		asl a
		sta temp+0
		asl a
		asl a
		clc
		adc temp+0
		sta temp+0

		tya
		clc
		adc temp+0
		sta temp+0
	
		inx
	zendloop

exit:
	lda temp+0
	clc
	rts
error:
	sec
	rts
.endproc

; Parses text at cmdoffset into the xfcb at XA, which becomes the
; current one.
.proc parse_fcb
	sta fcb+0
	stx fcb+1
	jsr skip_whitespace

	; Set the user number field in the XFCB.

	lda #$ff
	jsr bdos_GETSETUSER
	ldy #xfcb::us
	sta (fcb), y

	; Wipe FCB.

	ldy #xfcb::dr
	tya
	sta (fcb), y				; drive
	lda #' '
	zrepeat						; 11 bytes of filename
		iny
		sta (fcb), y
		cpy #xfcb::t3
	zuntil_eq
	lda #0
	zrepeat						; 4 bytes of metadata
		iny
		sta (fcb), y
		cpy #xfcb::cr
	zuntil_eq

	; Check for drive.

	ldx cmdoffset
	lda cmdline+1, x			; drive letter
	zif_eq
		clc
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
		ldy #xfcb::dr
		sta (fcb), y			; store

		inx
		inx
	zendif

	; Read the filename.

	; x = cmdoffset
	ldy #xfcb::f1
	zloop
		lda cmdline+1, x		; get a character
		beq exit				; end of line
		cpy #xfcb::f8+1
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

; Prints an 8-bit decimal number in A.
.proc print_dec_number
	ldy #0
	sty zflag
	ldx #$ff
	sec
	zrepeat
		inx
		sbc #100
	zuntil_cc
	adc #100
	jsr digit

	ldx #$ff
	sec
	zrepeat
		inx
		sbc #10
	zuntil_cc
	adc #10
	jsr digit
	
	tax
digit:
	pha
	txa
	zflag = * + 1
	ora #0
	zif_ne
		txa
		ora #'0'
		jsr bdos_CONOUT
		inc zflag
	zendif
	pla
	rts
.endproc

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

bdos_SETDMA:
	ldy #bdos::set_dma_address
	jmp BDOS

bdos_SELECTDISK:
	ldy #bdos::select_disk
	jmp BDOS

bdos_GETDRIVE:
	ldy #bdos::get_current_drive
	jmp BDOS

bdos_GETSETUSER:
	ldy #bdos::get_set_user_number
	jmp BDOS

bdos_CONIN:
	ldy #bdos::console_input
	jmp BDOS

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

bdos_READLINE:
	ldy #bdos::read_line
	jmp BDOS

bdos_WRITESTRING:
	ldy #bdos::write_string
	jmp BDOS

bdos_FINDFIRST:
	ldy #bdos::find_first
	jmp BDOS

bdos_FINDNEXT:
	ldy #bdos::find_next
	jmp BDOS

bdos_READSEQUENTIAL:
	ldy #bdos::read_sequential
	jmp BDOS

bios_GETZP:
    ldy #bios::getzp
    jmp (bios)

bios_GETTPA:
    ldy #bios::gettpa
    jmp (bios)

bios_RELOCATE:
	ldy #bios::relocate
	jmp (bios)

	.bss
bios:	 .res 2		; address of BIOS
drive:	 .res 1		; current drive, 0-based
cmdline: .res 128	; command line buffer
cmdfcb:  .tag xfcb	; FCB of command
userfcb: .tag xfcb	; parameter FCB

; vim; ts=4 sw=4 et filetype=asm

