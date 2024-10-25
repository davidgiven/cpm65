; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "wait.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

; --- Initialisation code ---------------------------------------------------

; Boot sector and relocator. Loaded at 0x8000 when the system starts. Called
; once on startup and then never again.

.global _start
.section loader, "ax"
_start:
    ; Relocate the BIOS to the bottom of memory.

    zrepeat
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
        zendif

        lda store+1
        cmp #<BIOS_END_ADDR
        zif_eq
            lda store+2
            cmp #>BIOS_END_ADDR
        zendif
    zuntil_eq

    ; Initialise the BIOS common code.

    jsr initdrivers
    
    ; Load the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy mem_base

    jsr loadfile
.if 0

    jsr screen_clear
    jsr set_normal_text

    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr tty_conout
        pla
        tay
        dey
    zuntil_eq
    .endif

    jmp bios_entry

return_int:
nmi_n_entry:
brk_e_entry:
int_e_entry:
    ;jmp bdos_core

banner: ; reversed!
    .ascii "\rSENS eht rof 56-M/PC"
banner_end:

bdos_filename:
    .ascii "BDOS    SYS"