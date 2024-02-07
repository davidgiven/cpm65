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

.global ptr, ptr1, user_dma, param, temp

ptr:			.fill 2
ptr1:			.fill 2
user_dma:		.fill 2 ; current DMA
param:        	.fill 2 ; current user input parameter

temp:           .fill 2

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

zproc bdosstart
	zloop
		jsr tty_conin
		jsr tty_conout
	zendloop
zendproc

; ===========================================================================
;                            BDOS IMPLEMENTATION
; ===========================================================================

; --- BDOS entrypoint -------------------------------------------------------

zproc bdos_entrypoint
    sta param+0
    stx param+1

;    lda #$ff
;    sta old_fcb_drive       ; mark FCB as not fiddled with

    ; Reset per-system-call state

;    lda #0
;    sta block_needs_clearing

    jsr icall               ; preserve carry from this!
    php
    pha
    tya
    pha

;    lda old_fcb_drive
;    zif_pl
;        ldy #FCB_DR
;        sta (param), y      ; restore user FCB
;    zendif

    pla
    tay
    pla
    plp
    rts

unimplemented:
    clc
    rts

icall:
    lda jumptable_hi, y
    pha
    lda jumptable_lo, y
    pha
    rts

jumptable_lo:
    jmptablo bdos_EXIT ; exit_program = 0
    jmptablo bdos_CONIN ; console_input = 1
    jmptablo bdos_CONOUT ; console_output = 2
    jmptablo bdos_UNIMPLEMENTED ; aux_input = 3 UNSUPPORTED
    jmptablo bdos_UNIMPLEMENTED ; aux_output = 4 UNSUPPORTED
    jmptablo bdos_UNIMPLEMENTED ; printer_output = 5 UNSUPPORTED
    jmptablo bdos_DIRECTIO ; direct_io = 6
    jmptablo bdos_GETIOBYTE ; get_io_byte = 7 UNSUPPORTED
    jmptablo bdos_UNIMPLEMENTED ; set_io_byte = 8 UNSUPPORTED
    jmptablo bdos_WRITESTRING ; write_string = 9
    jmptablo bdos_READLINE ; read_line = 10
    jmptablo bdos_GETCONSOLESTATUS ; console_status = 11
    jmptablo bdos_GETVERSION ; get_version = 12
    jmptablo bdos_RESET ; reset_disks = 13
    jmptablo bdos_LOGINDRIVE ; select_disk = 14
    jmptablo bdos_OPENFILE ; open_file = 15
    jmptablo bdos_CLOSEFILE ; close_file = 16
    jmptablo bdos_FINDFIRST ; find_first = 17
    jmptablo bdos_FINDNEXT ; find_next = 18
    jmptablo bdos_DELETEFILE ; delete_file = 19
    jmptablo bdos_READSEQUENTIAL ; read_sequential = 20
    jmptablo bdos_WRITESEQUENTIAL ; write_sequential = 21
    jmptablo bdos_CREATEFILE ; create_file = 22
    jmptablo bdos_RENAMEFILE ; rename_file = 23
    jmptablo bdos_GETLOGINBITMAP ; get_login_bitmap = 24
    jmptablo bdos_GETDRIVE ; get_current_drive = 25
    jmptablo bdos_SETDMAADDRESS ; set_dma_address = 26
    jmptablo bdos_GETALLOCATIONBITMAP ; get_allocation_bitmap = 27
    jmptablo bdos_SETDRIVEREADONLY ; set_drive_readonly = 28
    jmptablo bdos_GETREADONLYBITMAP ; get_readonly_bitmap = 29
    jmptablo bdos_SETFILEATTRS ; set_file_attributes = 30
    jmptablo bdos_GETDPB ; get_DPB = 31
    jmptablo bdos_GETSETUSER ; get_set_user_number = 32
    jmptablo bdos_READRANDOM ; read_random = 33
    jmptablo bdos_WRITERANDOM ; write_random = 34
    jmptablo bdos_COMPUTEFILESIZE ; compute_file_size = 35
    jmptablo bdos_COMPUTEPOINTER ; compute_random_pointer = 36
    jmptablo bdos_RESETDISK ; reset_disk = 37
    jmptablo bdos_GETBIOS ; get_bios = 38
    jmptablo unimplemented ; 39
    jmptablo bdos_WRITERANDOMFILLED ; write_random_filled = 40
    jmptablo bios_GETZP ; get_zp = 41
    jmptablo bios_GETTPA ; get_tpa = 42
    jmptablo bdos_PARSEFCB ; 43
jumptable_hi:
    jmptabhi bdos_EXIT ;exit_program = 0
    jmptabhi bdos_CONIN ; console_input = 1
    jmptabhi bdos_CONOUT ; console_output = 2
    jmptabhi bdos_UNIMPLEMENTED ; aux_input = 3 UNSUPPORTED
    jmptabhi bdos_UNIMPLEMENTED ; aux_output = 4 UNSUPPORTED
    jmptabhi bdos_UNIMPLEMENTED ; printer_output = 5 UNSUPPORTED
    jmptabhi bdos_DIRECTIO ; direct_console_io = 6
    jmptabhi bdos_GETIOBYTE ; get_io_byte = 7 UNSUPPORTED
    jmptabhi bdos_UNIMPLEMENTED ; set_io_byte = 8 UNSUPPORTED
    jmptabhi bdos_WRITESTRING ; write_string = 9
    jmptabhi bdos_READLINE ; read_line = 10
    jmptabhi bdos_GETCONSOLESTATUS ; console_status = 11
    jmptabhi bdos_GETVERSION ; get_version = 12
    jmptabhi bdos_RESET ; reset_disks = 13
    jmptabhi bdos_LOGINDRIVE ; select_disk = 14
    jmptabhi bdos_OPENFILE ; open_file = 15
    jmptabhi bdos_CLOSEFILE ; close_file = 16
    jmptabhi bdos_FINDFIRST ; find_first = 17
    jmptabhi bdos_FINDNEXT ; find_next = 18
    jmptabhi bdos_DELETEFILE ; delete_file = 19
    jmptabhi bdos_READSEQUENTIAL ; read_sequential = 20
    jmptabhi bdos_WRITESEQUENTIAL ; write_sequential = 21
    jmptabhi bdos_CREATEFILE ; create_file = 22
    jmptabhi bdos_RENAMEFILE ; rename_file = 23
    jmptabhi bdos_GETLOGINBITMAP ; get_login_bitmap = 24
    jmptabhi bdos_GETDRIVE ; get_current_drive = 25
    jmptabhi bdos_SETDMAADDRESS ; set_dma_address = 26
    jmptabhi bdos_GETALLOCATIONBITMAP ; get_allocation_bitmap = 27
    jmptabhi bdos_SETDRIVEREADONLY ; set_drive_readonly = 28
    jmptabhi bdos_GETREADONLYBITMAP ; get_readonly_bitmap = 29
    jmptabhi bdos_SETFILEATTRS ; set_file_attributes = 30
    jmptabhi bdos_GETDPB ; get_dpb = 31
    jmptabhi bdos_GETSETUSER ; get_set_user_number = 32
    jmptabhi bdos_READRANDOM ; read_random = 33
    jmptabhi bdos_WRITERANDOM ; write_random = 34
    jmptabhi bdos_COMPUTEFILESIZE ; compute_file_size = 35
    jmptabhi bdos_COMPUTEPOINTER ; compute_random_pointer = 36
    jmptabhi bdos_RESETDISK ; reset_disk = 37
    jmptabhi bdos_GETBIOS ; 38
    jmptabhi unimplemented ; 39
    jmptabhi bdos_WRITERANDOMFILLED ; write_random_filled = 40
    jmptabhi bios_GETZP ; get_zp = 41
    jmptabhi bios_GETTPA ; get_tpa = 42
    jmptabhi bdos_PARSEFCB ; 43
zendproc

.global bdos_EXIT

bdos_EXIT:
bdos_UNIMPLEMENTED:
bdos_GETIOBYTE:
bdos_GETCONSOLESTATUS:
bdos_GETVERSION:
bdos_RESET:
bdos_LOGINDRIVE:
bdos_OPENFILE:
bdos_CLOSEFILE:
bdos_FINDFIRST:
bdos_FINDNEXT:
bdos_DELETEFILE:
bdos_READSEQUENTIAL:
bdos_WRITESEQUENTIAL:
bdos_CREATEFILE:
bdos_RENAMEFILE:
bdos_GETLOGINBITMAP:
bdos_GETDRIVE:
bdos_SETDMAADDRESS:
bdos_GETALLOCATIONBITMAP:
bdos_SETDRIVEREADONLY:
bdos_GETREADONLYBITMAP:
bdos_SETFILEATTRS:
bdos_GETDPB:
bdos_GETSETUSER:
bdos_READRANDOM:
bdos_WRITERANDOM:
bdos_COMPUTEFILESIZE:
bdos_COMPUTEPOINTER:
bdos_RESETDISK:
bdos_GETBIOS:
bdos_WRITERANDOMFILLED:
	sec
	rts

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


