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

.macro SYSIN
    clc
    .byte 0xfb      ; xce, leave emulation mode
.endm

.macro SYSOUT
    php
    sec
    .byte 0xfb      ; xce, back into emulation mode
    plp
    rts
.endm

.macro SYSCALL n
    SYSIN
    .4byte 0x22 | (\n << 8) ; jsl
    SYSOUT
.endm

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
    SYSCALL JUMP_BIOS_SETDMA
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
    SYSCALL JUMP_BIOS_SETSEC
zendproc

zproc bios_READ
    SYSCALL JUMP_BIOS_READ
zendproc

zproc bios_WRITE
    sec
    rts
zendproc

; --- TTY driver ------------------------------------------------------------

defdriver TTY, DRVID_TTY, drvstrat_TTY, drv_SCREEN

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    SYSCALL JUMP_TTY
zendproc

; --- Screen driver ---------------------------------------------------------

defdriver SCREEN, DRVID_SCREEN, drvstrat_SCREEN, 0

zproc drvstrat_SCREEN
    sec
    rts
    SYSCALL JUMP_SCREEN
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

define_drive dph, 160*72, 4096, 256, 0

.bss

.global directory_buffer
directory_buffer:       .fill 128   ; used by the BDOS
