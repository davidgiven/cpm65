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
BDOS_GET_BIOS          = 38
BDOS_WRITE_RANDOM_FILL = 40
BDOS_GET_TPA           = 41
BDOS_GET_ZP            = 42

BIOS_CONST             = 0
BIOS_CONIN             = 1
BIOS_CONOUT            = 2
BIOS_SELDSK            = 3
BIOS_SETSEC            = 4
BIOS_SETDMA            = 5
BIOS_READ              = 6
BIOS_WRITE             = 7
BIOS_RELOCATE          = 8
BIOS_GETTPA            = 9
BIOS_SETTPA            = 10
BIOS_GETZP             = 11
BIOS_SETZP             = 12
BIOS_SETBANK           = 13
BIOS_ADDDRV            = 14
BIOS_FINDDRV           = 15

DRVID_TTY = 1

DRVSTRUCT_ID    = 0
DRVSTRUCT_STRAT = 2
DRVSTRUCT_NEXT  = 4
DRVSTRUCT_NAME  = 6

TTY_CONST = 0
TTY_CONIN = 1
TTY_CONOUT = 2

BDOS = start - 3
start:
.expand 1

.label space
.label newline
.label printchar
.label print_hex_number

.zp ptr, 2
.zp index, 1

.zproc entry
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    \ Find the head of the driver chain.

    lda #0
	tax
    ldy #BIOS_FINDDRV
    jsr BIOS
	sta ptr+0
	stx ptr+1

	.zloop
		lda ptr+0
		ora ptr+1
		.zif eq
			rts
		.zendif

		\ Print driver address.

		lda ptr+1
		jsr print_hex_number
		lda ptr+0
		jsr print_hex_number
		jsr space

		\ Print driver name.

		ldy #DRVSTRUCT_NAME
		sty index
		.zloop
			ldy index
			lda (ptr), y
			.zbreak eq

			jsr printchar
			inc index
		.zendloop
		jsr space

		\ Print driver ID.

		lda #'('
		jsr printchar

		ldy #DRVSTRUCT_ID+1
		lda (ptr), y
		jsr print_hex_number

		ldy #DRVSTRUCT_ID+0
		lda (ptr), y
		jsr print_hex_number

		lda #')'
		jsr printchar
		jsr newline

		\ Advance to next driver.

		ldy #DRVSTRUCT_NEXT
		lda (ptr), y
		pha
		iny
		lda (ptr), y
		sta ptr+1
		pla
		sta ptr+0
	.zendloop

BIOS:
    jmp 0

\ Prints an 8-bit hex number in A.
.zproc print_hex_number
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr print
	pla
print:
	and #0x0f
	ora #48
	cmp #58
    .zif cs
        adc #6
    .zendif
	pha
	jsr printchar
	pla
	rts
.zendproc

.zproc space
	lda #' '
.zendproc
    \ fall through
.zproc printchar
    ldy #BDOS_CONOUT
    jmp BDOS
.zendproc

.zproc newline
	lda #13
	jsr printchar
	lda #10
	jmp printchar
.zendproc

\ vim: sw=4 ts=4 et



