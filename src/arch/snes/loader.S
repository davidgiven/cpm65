; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "wait.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

.global ptr, ptr1

ptr:            .fill 2
ptr1:           .fill 2

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

.if 0
    jsr initdrivers

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

.section header, "ax"
    ;       012345678901234567890
    .ascii "CP/M-65 SNES         "
    .byte %00110001     ; fast, HiROM
    .byte $02           ; ROM + RAM + battery
    .byte 9              ; ROM size: 512kB
    .byte 5              ; RAM size: 32kB
    .byte 0              ; country
    .byte 0              ; developer ID
    .byte 0              ; version
    .word 0              ; checksum complement (filled in later)
    .word 0              ; checksum (filled in later)

    ; Native mode vectors

    .word $ffff         ; reserved
    .word $ffff         ; reserved
    .word return_int     ; COP
    .word return_int     ; BRK
    .word return_int     ; ABT
    .word nmi_n_entry    ; NMI
    .word $ffff         ; reserved
    .word return_int     ; IRQ

     ; Emulation mode vectors

    .word $ffff         ; reserved
    .word $ffff         ; reserved
    .word return_int    ; COP
    .word brk_e_entry
    .word return_int     ; ABT
    .word nmi_n_entry    ; NMI
    .word _start         ; reserved
    .word int_e_entry    ; IRQ
