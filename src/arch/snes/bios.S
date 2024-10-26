; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "wait.inc"
#include "driver.inc"
#include "jumptables.inc"
#include "globals.inc"

; --- Zero page -------------------------------------------------------------

ZEROPAGE

.global ptr
.global ptr1
ptr:              .fill 2
ptr1:             .fill 2
cursorx:          .fill 1
cursory:          .fill 1

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

zproc bios_SETDMA
    .4byte 0x22 | (JUMP_BIOS_SETDMA << 8)
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc bios_SELDSK
    cmp #0
    bne fail                ; invalid drive

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

zproc fail
    sec
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

zproc bios_SETSEC
    .4byte 0x22 | (JUMP_BIOS_SETSEC << 8)
    rts
zendproc

zproc bios_READ
    .4byte 0x22 | (JUMP_BIOS_READ << 8)
    rts
zendproc

zproc bios_WRITE
    sec
    rts
zendproc

; --- TTY driver ------------------------------------------------------------

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
    .4byte 0x22 | (JUMP_TTY_CONST << 8)
    clc
    rts
zendproc

; Blocks until a key is pressed; returns it in A.

zproc tty_conin
    .4byte 0x22 | (JUMP_TTY_CONIN << 8)
    clc
    rts
zendproc

; Writes the character in A.

zproc tty_conout
    .4byte 0x22 | (JUMP_TTY_PUTCHAR << 8)
    clc
    rts
zendproc

; --- Data ------------------------------------------------------------------

.data

.global zp_base, zp_end, mem_base, mem_end
zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi

.global drvtop
; This must point at the _last_ driver.
drvtop: .word drv_TTY

; DPH for drive 0 (our only drive)

define_drive dph, 360, 4096, 256, 0

.bss

.global directory_buffer
directory_buffer:       .fill 128   ; used by the BDOS
