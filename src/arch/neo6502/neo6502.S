#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"

CP = 0xff00
CP_GROUP    = CP + 0
CP_FUNCTION = CP + 1
CP_ERRNO    = CP + 2
CP_INFO     = CP + 3
CP_PARAM    = CP + 4

GROUP_TTY        = 2
FUNC_TTY_READCH  = 1
FUNC_TTY_POLLCH  = 2
FUNC_TTY_WRITECH = 6

GROUP_FILE		  = 3
FUNC_FILE_OPEN	  = 4
FUNC_FILE_CLOSE	  = 5
FUNC_FILE_SEEK    = 6
FUNC_FILE_TELL    = 7
FUNC_FILE_READH   = 8
FUNC_FILE_WRITEH  = 9
FUNC_FILE_GETSIZE = 10
FUNC_FILE_SETSIZE = 11

FIOMODE_RDONLY 	    = 0
FIOMODE_WRONLY      = 1
FIOMODE_RDWR        = 2
FIOMODE_RDWR_CREATE = 3

; Filenames are of the form: "/A10/ABCDEFGH.XYZ"

FT_FILENAMELEN    = 0 ; 0 if not in use
FT_FILENAME       = 1
FT__SIZE          = 18

NUM_FILES         = 8

ZEROPAGE

.global ptr, ptr1

ptr:			.fill 2
ptr1:			.fill 2

; --- Initialisation code ---------------------------------------------------

; Boot sector and relocator. Loaded at 0x8000 when the system starts. Called
; once on startup and then never again.

.global _start
.section loader, "ax"
_start:
	ldx #0xff
	txs					; reset stack

    ; Relocate the BIOS to the top of memory.

    zloop
        load = .
        lda BIOS_LOAD_ADDR
        store = .
        sta BIOS_EXEC_ADDR

        inc load+1
        zif_eq
            inc load+2
        zendif

        inc store+1
        zif_eq
            inc store+2
            zbreakif_eq
        zendif
    zendloop

    jsr initdrivers
	jmp bdos_core

; ===========================================================================
;                            BDOS IMPLEMENTATION
; ===========================================================================

.global internal_RESETFILESYSTEM, internal_BEGINSYS, internal_ENDSYS
.global internal_READSEQUENTIAL

.global bdos_UNIMPLEMENTED, bdos_LOGINDRIVE, bdos_OPENFILE, bdos_CLOSEFILE
.global bdos_FINDFIRST, bdos_FINDNEXT, bdos_DELETEFILE, bdos_READSEQUENTIAL
.global bdos_WRITESEQUENTIAL, bdos_CREATEFILE, bdos_RENAMEFILE, bdos_GETLOGINBITMAP
.global bdos_GETALLOCATIONBITMAP, bdos_SETDRIVEREADONLY
.global bdos_GETREADONLYBITMAP, bdos_SETFILEATTRS, bdos_GETDPB
.global bdos_READRANDOM, bdos_WRITERANDOM, bdos_COMPUTEFILESIZE, bdos_COMPUTEPOINTER
.global bdos_RESETDISK, bdos_WRITERANDOMFILLED

zproc internal_RESETFILESYSTEM
	; Close all files.

	lda #0xff
	sta CP_PARAM+0
	lda #FUNC_FILE_CLOSE
	jsr neo_file_func

	; Clear the file allocation table.

	ldx #0
	zrepeat
		stz file_table+FT_FILENAMELEN, x

		txa
		clc
		adc #FT__SIZE
		tax

		cpx #NUM_FILES*FT__SIZE
	zuntil_eq
	rts
zendproc


internal_BEGINSYS:
internal_ENDSYS:
bdos_LOGINDRIVE:
	rts

bdos_OPENFILE:
	jsr get_file_handle
	sta CP_PARAM+0

	.byte 3

	clc
	txa
	adc #<file_table
	sta CP_PARAM+1
	lda #>file_table
	adc #0
	sta CP_PARAM+2

	lda #FIOMODE_RDWR
	sta CP_PARAM+3

	phx
	lda #FUNC_FILE_OPEN
	jsr neo_file_func_blocking
	plx

	lda CP_ERRNO
	zif_ne
		stz file_table+FT_FILENAMELEN, x ; mark file as unused
		sec
		rts
	zendif

	ldy #FCB_EX
	lda #0
	sta (param), y
	iny
	sta (param), y
	iny
	sta (param), y
	iny
	sta (param), y

	clc
	rts

bdos_UNIMPLEMENTED:
	.byte 3
bdos_CLOSEFILE:
	.byte 3
bdos_FINDFIRST:
	.byte 3
bdos_FINDNEXT:
	.byte 3
bdos_DELETEFILE:
	.byte 3
bdos_READSEQUENTIAL:
	.byte 3
internal_READSEQUENTIAL:
	.byte 3
bdos_WRITESEQUENTIAL:
	.byte 3
bdos_CREATEFILE:
	.byte 3
bdos_RENAMEFILE:
	.byte 3
bdos_GETLOGINBITMAP:
	.byte 3
bdos_GETALLOCATIONBITMAP:
	.byte 3
bdos_SETDRIVEREADONLY:
	.byte 3
bdos_GETREADONLYBITMAP:
	.byte 3
bdos_SETFILEATTRS:
	.byte 3
bdos_GETDPB:
	.byte 3
bdos_READRANDOM:
	.byte 3
bdos_WRITERANDOM:
	.byte 3
bdos_COMPUTEFILESIZE:
	.byte 3
bdos_COMPUTEPOINTER:
	.byte 3
bdos_RESETDISK:
	.byte 3
bdos_WRITERANDOMFILLED:
	.byte 3

zproc bdos_GETBIOS
    lda #<biosentry
    sta param+0
    ldx #>biosentry
    stx param+1
    rts
zendproc

; Gets the file handle for the FCB pointed to by param.
; A = file handle
; X = offset into file_table

zproc get_file_handle
	; Construct the template filetab entry.

	lda #'/'
	sta temp_file_entry+FT_FILENAME+0

	lda (param)     ; drive
	dec
	zif_ne			; no drive specified?
		lda current_drive
	zendif
	clc
	adc #'A'
	sta temp_file_entry+FT_FILENAME+1

	ldx #2
	lda current_user
	zif_ne
		cmp #9
		zif_cs
			lda #'1'
			sta temp_file_entry+FT_FILENAME, x
			inx
			sec
			sbc #10
		zendif

		clc
		adc #'0'
		sta temp_file_entry+FT_FILENAME, x
		inx
	zendif

	lda #'/'
	sta temp_file_entry+FT_FILENAME, x
	inx

	; Copy filename

	ldy #FCB_F1
	zrepeat
		lda (param), y
		and #0x7f

		cmp #' '
		zif_ne
			cpy #FCB_T1
			zif_eq
				pha
				lda #'.'
				sta temp_file_entry+FT_FILENAME, x
				pla
				inx
			zendif

			sta temp_file_entry+FT_FILENAME, x
			inx
		zendif

		iny
		cpy #FCB_T3+1
	zuntil_eq

	stx temp_file_entry+FT_FILENAMELEN

	; Now look for a matching slot.

	ldx #0				; offset to FT being considered
	stx ptr+0			; file handle
	zrepeat
		phx
		ldy #0
		zrepeat
			lda file_table, x
			cmp temp_file_entry, y
			zbreakif_ne

			inx
			iny
			cpy temp_file_entry
		zuntil_eq
		zif_eq
			plx
			bra found_matching_filetab
		zendif
		pla
		adc #FT__SIZE
		tax

		inc ptr+0
		cpx #FT__SIZE * NUM_FILES
	zuntil_eq

	; No slots match. Find an empty slot.

	ldx #0
	stx ptr+0
	zrepeat
		lda file_table+FT_FILENAMELEN, x
		zif_eq			; empty?
			; Yes! Copy in the template.

			lda temp_file_entry
			inc
			sta ptr+1

			phx
			ldy #0
			zrepeat
				lda temp_file_entry, y
				sta file_table, x
				inx
				iny
				cpy ptr+1
			zuntil_eq
			plx

			bra found_matching_filetab
		zendif

		inc ptr+0

		txa
		clc
		adc #FT__SIZE
		tax

		cmp #FT__SIZE * NUM_FILES
	zuntil_eq

	; A file needs to be evicted.

	.byte 3

found_matching_filetab:
	lda ptr+0
	rts
zendproc

NOINIT

temp_file_entry:
	.fill FT__SIZE

; Execute RP2040 operation in A. Don't wait.

zproc neo_file_func
	jsr wait_for_command

	sta CP_FUNCTION
	lda #GROUP_FILE
	sta CP_GROUP
	rts
zendproc

; Execute RP2040 operation in A. Do wait.

zproc neo_file_func_blocking
	jsr neo_file_func
	jmp wait_for_command
zendproc

.data

file_table: .fill FT__SIZE * NUM_FILES

; ===========================================================================
;                            BIOS IMPLEMENTATION
; ===========================================================================

.data
.global drvtop
; This must point at the _last_ driver.
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    jmpdispatch jmptable_lo, jmptable_hi

jmptable_lo:
    jmptablo tty_const
    jmptablo tty_conin
    jmptablo tty_conout
jmptable_hi:
    jmptabhi tty_const
    jmptabhi tty_conin
    jmptabhi tty_conout
zendproc

; Returns 0xff if no key is pending, 0 if one is.

zproc tty_const
	lda #FUNC_TTY_POLLCH
	jsr neo_tty_func_blocking
	lda CP_PARAM+0
	clc
	rts
zendproc

; Blocks and reads a character into A.

zproc tty_conin
	zrepeat
		lda #FUNC_TTY_READCH
		jsr neo_tty_func_blocking
		lda CP_PARAM + 0
	zuntil_ne
	clc
	rts
zendproc

; Writes the character in A.

zproc tty_conout
	sta CP_PARAM + 0
	lda #FUNC_TTY_WRITECH
	jsr neo_tty_func
	clc
	rts
zendproc

; Execute RP2040 operation in A. Don't wait.

zproc neo_tty_func
	jsr wait_for_command

	sta CP_FUNCTION
	lda #GROUP_TTY
	sta CP_GROUP
	rts
zendproc

; Execute RP2040 operation in A. Do wait.

zproc neo_tty_func_blocking
	jsr neo_tty_func
	jmp wait_for_command
zendproc

.global bios_SELDSK, bios_SETSEC, bios_SETDMA, bios_READ, bios_WRITE

.text
bios_SELDSK:
bios_SETSEC:
bios_SETDMA:
bios_READ:
bios_WRITE:
	sec
	rts

zproc bios_NEWLINE
    lda #13
    jsr bios_CONOUT
    lda #10
    jmp bios_CONOUT
zendproc

; --- BIOS entrypoints ------------------------------------------------------

zproc bios_GETTPA
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc bios_SETTPA
    sta mem_base
    stx mem_end
    clc
    rts
zendproc

zproc bios_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc

zproc bios_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc bios_SETBANK
    rts
zendproc

; --- Utilities -------------------------------------------------------------

; Waits for the previous command to complete, if any.

zproc wait_for_command
	pha
	zrepeat
		lda CP_GROUP
	zuntil_eq
	pla
	rts
zendproc

; --- Data ------------------------------------------------------------------

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA0_START__@mos16hi, __TPA0_START__@mos16hi
mem_end:    .byte __TPA0_END__@mos16hi,   __TPA0_END__@mos16hi
