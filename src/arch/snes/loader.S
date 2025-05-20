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
    ; Switch to emulation mode.

    sec
    .byte 0xfb      ; xce

    ; This is the trampoline used to return from emulation-mode interrupts.

    lda #$38        ; sec
    sta $ff00
    lda #$fb        ; xce
    sta $ff01
    lda #$40        ; rti
    sta $ff02

    ; Relocate the BIOS to the bottom of memory.

    zrepeat
        load = .
        lda BIOS_LOAD_ADDR
        store = .
        sta BIOS_EXEC_ADDR

        inc load+1
        zif eq
            inc load+2
        zendif

        inc store+1
        zif eq
            inc store+2
        zendif

        lda store+1
        cmp #<BIOS_END_ADDR
        zif eq
            lda store+2
            cmp #>BIOS_END_ADDR
        zendif
    zuntil eq

    ; Initialise the BIOS common code.

    jsr initdrivers
    
    ; Display the banner.

    ldy #banner_end - banner
    zrepeat
        phy
        lda banner-1, y
        ldy #TTY_CONOUT
        jsr drvstrat_TTY
        ply
        dey
    zuntil eq

    ; Load the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy #>__TPA_START__
    jsr loadfile

    ; Fix it up.

    lda #>__TPA_START__
    ldx #__ZEROPAGE_START__
    jsr bios_RELOCATE

    ; Go!

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA_START__ + COMHDR_ENTRY

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