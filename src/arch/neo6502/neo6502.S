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

	lda #<biosentry ; force biosentry to be linked
	jmp bdosstart

.global cpm_header
cpm_header:
    .byte 0   ; zero page used
    .byte 0   ; tpa used

zproc bdosstart
	zloop
		jsr tty_conin
		jsr tty_conout
	zendloop
    jmp bdos_core
zendproc

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

internal_RESETFILESYSTEM:
internal_BEGINSYS:
internal_ENDSYS:

bdos_UNIMPLEMENTED:
bdos_LOGINDRIVE:
bdos_OPENFILE:
bdos_CLOSEFILE:
bdos_FINDFIRST:
bdos_FINDNEXT:
bdos_DELETEFILE:
bdos_READSEQUENTIAL:
internal_READSEQUENTIAL:
bdos_WRITESEQUENTIAL:
bdos_CREATEFILE:
bdos_RENAMEFILE:
bdos_GETLOGINBITMAP:
bdos_GETALLOCATIONBITMAP:
bdos_SETDRIVEREADONLY:
bdos_GETREADONLYBITMAP:
bdos_SETFILEATTRS:
bdos_GETDPB:
bdos_READRANDOM:
bdos_WRITERANDOM:
bdos_COMPUTEFILESIZE:
bdos_COMPUTEPOINTER:
bdos_RESETDISK:
bdos_WRITERANDOMFILLED:
	sec
	rts

zproc bdos_GETBIOS
    lda #<biosentry
    sta param+0
    ldx #>biosentry
    stx param+1
    rts
zendproc


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
    txa                 ; BUG: stx mem_end, y - invalid 6502 instruction
    sta mem_end
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


