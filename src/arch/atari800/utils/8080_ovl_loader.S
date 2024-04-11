; -------------------------------------------------------------------------
;
; 8080 Overlay Loader
;
; Copyright © 2024 Ivo van poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; -------------------------------------------------------------------------

; This program is intended for Atari's equiped with at least 128kB of RAM.
; It first checks if the required memory is free, i.e. not too many resident
; drivers in either low or high memory, and then proceeds to load the file
; 8080.OVL. The structure of the file is similar to regular binary executables
; used by Atari DOS, with a few restrictions.
;
; 8080.OVL file consists of several blocks. Each block looks like this:
;
; FF FF     Header marker (optional, except for the first block)
; lb hb     Start address $hblb
; lb hb     End address $hblb
; xx ...    End-Start+1 bytes of data
;
; Two special blocks are recognized.
;
; e2 02 e3 02 lb hb     Init. JSR to $hblb, continue loading after RTS.
; e0 02 e1 02 lb hb     Run. JMP to $hblb.
;
; The loader does no sanity checks on loaded blocks, so be sure it only
; defines blocks between the end of the loader and the end of TPA memory.
; The file _MUST_ end with a Run block. A "Run" is executed immediately,
; unlike Atari DOS which waits until EOF.

; -------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"
#ifdef MASTER128

#else
#include "atari800.inc"
#endif

ZEROPAGE

ZP_START:

ptr:        .fill 2
end:        .fill 2
tmp:        .fill 1
bufidx:     .fill 1

ZP_END:

; Add this to GETZP's low to see if we extend into $e0-$ff
; ZP and TPA are not automatically adjusted before the (this) program is called.

ZP_WE_USE = ZP_END-ZP_START

#ifdef MASTER128
    TEST_TPA_TOP    = $68
    TEST_TPA_BOTTOM = $30
    TEST_ZP_BOTTOM  = $70
    TEST_ZP_TOP     = $8f
#else
    TEST_TPA_TOP    = $b6
    TEST_TPA_BOTTOM = $40
    TEST_ZP_BOTTOM  = $e0
    TEST_ZP_TOP     = $ff
#endif

; -------------------------------------------------------------------------

zproc main
    ldy #BDOS_WRITE_STRING
    lda #<title
    ldx #>title
    jsr BDOS

; check end of TPA

    ldy #BIOS_GETTPA
    jsr BIOS
    cpx #TEST_TPA_TOP
    bcs top_ok

    lda #<top_error
    ldx #>top_error
error_out:
    ldy #BDOS_WRITE_STRING
    jmp BDOS

top_ok:

; check end of loader program

    lda #>bottom_check
    clc
    adc #1
    cmp #TEST_TPA_BOTTOM
    bcc bottom_ok

    lda #<bottom_error
    ldx #>bottom_error
    jmp error_out

bottom_ok:

; check if $e0-$ff is free

    ldy #BIOS_GETZP
    jsr BIOS

    cmp #TEST_ZP_BOTTOM-ZP_WE_USE
    bcc bottom_zp_ok

print_zp_error:
    lda #<zp_error
    ldx #>zp_error
    jmp error_out

bottom_zp_ok:
    cpx #TEST_ZP_TOP
    bcc print_zp_error

; check if we have banked memory

#ifdef MASTER128
    ldx $f4
    lda #4
    sta $f4
    sta $fe30
    sta $8000
    cmp $8000
    beq bank_found

    stx $f4

    lda #<extmem_error
    ldx #>extmem_error
    jmp error_out

bank_found:
    stx $f4
    stx $fe30

#else
    lda PORTB
    sta $4000               ; "random" value to $4000
    eor #$10                ; enable CPU banking
    sta PORTB
    eor #$10
    cmp $4000
    bne bank_found

    sta PORTB

    lda #<extmem_error
    ldx #>extmem_error
    jmp error_out

bank_found:
    sta PORTB
#endif

; setup FCB

    ldx #$24
    lda #0
clear_fcb:
    sta my_fcb,x
    dex
    bpl clear_fcb

    ldx #10
copy_filename:
    lda filename,x
    sta my_fcb+1,x
    dex
    bpl copy_filename

; open '8080.OVL'

    ldy #BDOS_OPEN_FILE
    lda #<my_fcb
    ldx #>my_fcb
    jsr BDOS
    bcc open_ok

    lda #<open_error
    ldx #>open_error
    jmp error_out

open_ok:
    lda #$80
    sta bufidx

    jsr getbyte
    sta tmp
    jsr getbyte
    cmp #$ff
    beq FF_almost_ok

invalid_file:
    lda #<FF_error
    ldx #>FF_error
    jmp error_out

FF_almost_ok:
    lda tmp
    cmp #$ff
    bne invalid_file

read_blocks_loop:

skip_FF:
    jsr getbyte
    sta ptr
    jsr getbyte
    sta ptr+1
    lda ptr
    cmp #$ff
    bne read_end_addr
    lda ptr+1
    cmp #$ff
    beq skip_FF

read_end_addr:
    jsr getbyte
    sta end
    jsr getbyte
    sta end+1

    lda #'.'
    ldy #BIOS_CONOUT
    jsr BIOS

    lda #0
    sta do_init
    sta do_run

    jsr check_02e0
    jsr check_02e2

next_byte:
    jsr getbyte
    ldy #0
    sta (ptr),y

    lda ptr
    cmp end
    beq almost_end

not_end:
    inc ptr
    zif_eq
        inc ptr+1
    zendif
    jmp next_byte

almost_end:
    lda ptr+1
    cmp end+1
    bne not_end

    lda do_init
    beq skip_init

    jsr jsr_init

skip_init:
    lda do_run
    beq skip_run

    lda #13
    ldy #BIOS_CONOUT
    jsr BIOS
    lda #10
    ldy #BIOS_CONOUT
    jsr BIOS

    lda #<BIOS      ; pass along pointer to BIOS
    ldx #>BIOS
    jsr jsr_run

    lda #0                          ; be sure we can read CCP.SYS
    ldy #BDOS_GET_SET_USER_NUMBER
    jsr BDOS

    ldy #BDOS_EXIT_PROGRAM  ; warmboot, i8080 CP/M might have written to disk
    jmp BDOS

skip_run:
    jmp read_blocks_loop
zendproc

zproc check_02e0
    lda ptr+1
    cmp #$02
    zif_eq
        lda ptr
        cmp #$e0
        zif_eq
            inc do_run
            lda #>run_address
            sta ptr+1
            sta end+1
            ldx #<run_address
            stx ptr
            inx
            stx end
        zendif
    zendif
    rts
zendproc

zproc check_02e2
    lda ptr+1
    cmp #$02
    zif_eq
        lda ptr
        cmp #$e2
        zif_eq
            inc do_init
            lda #>init_address
            sta ptr+1
            sta end+1
            ldx #<init_address
            stx ptr
            inx
            stx end
        zendif
    zendif
    rts
zendproc

zproc jsr_init
    jmp (init_address)
zendproc

zproc jsr_run
    jmp (run_address)
zendproc

zproc getbyte
    ldx bufidx
    bpl still_data_available

    jsr read_next_sector
    ldx bufidx

still_data_available:
    lda sector_buffer,x
    inc bufidx
    rts
zendproc

zproc read_next_sector
    lda #<sector_buffer
    ldx #>sector_buffer
    ldy #BDOS_SET_DMA_ADDRESS
    jsr BDOS

    lda #<my_fcb
    ldx #>my_fcb
    ldy #BDOS_READ_SEQUENTIAL
    jsr BDOS

    bcs unexpected_eof

    lda #0
    sta bufidx
    rts

unexpected_eof:
    lda #<eof_error
    ldx #>eof_error
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    ldy #BDOS_EXIT_PROGRAM
    jmp BDOS
zendproc

; -------------------------------------------------------------------------

    .data

title:
#ifdef MASTER128
    .ascii "BBC Master 128 - 8080 Overlay Loader"
#else
    .ascii "Atari 130XE - 8080 Overlay Loader"
#endif
    .byte 13,10,0

top_error:
    .ascii "Error: top of TPA is too low"
    .byte 13,10,0

bottom_error:
    .ascii "Error: bottom of TPA is too high"
    .byte 13,10,0

zp_error:
#ifdef MASTER128
    .ascii "Error: ZP 70-8F must be free"
#else
    .ascii "Error: ZP E0-FF must be free"
#endif
    .byte 13,10,0

extmem_error:
    .ascii "Error: no extended memory detected"
    .byte 13,10,0

open_error:
    .ascii "Error: unable to open 8080.OVL"
    .byte 13,10,0

eof_error:
    .ascii "Error: premature EOF encountered"
    .byte 13,10,0

FF_error:
    .ascii "Error: invalid OVL file"
    .byte 13,10,0

filename:
    .ascii "8080    OVL"

; -------------------------------------------------------------------------

    .bss

my_fcb:         .fill 37

sector_buffer:  .fill 128

do_init:        .fill 1
do_run:         .fill 1

    .align 2        ; avoid page crossing jmp (abs)

init_address:   .fill 2
run_address:    .fill 2

bottom_check:

; -------------------------------------------------------------------------

; vim: filetype=asm sw=4 ts=4 et
