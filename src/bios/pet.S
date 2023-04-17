; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

PIA1    = 0xe810
PIA1_PA = PIA1 + 0
PIA1_CA = PIA1 + 1
PIA1_PB = PIA1 + 2
PIA1_CB = PIA1 + 3

PIA1_PA_EOI_IN = 1<<6
PIA1_CA_EOI_OUT = 1<<2

PIA2    = 0xe820
PIA2_PA = PIA2 + 0
PIA2_CA = PIA2 + 1
PIA2_PB = PIA2 + 2
PIA2_CB = PIA2 + 3

PIA2_CA_NDAC_OUT = 1<<3

PIA2_CB_SRQ_IN = 1<<1
PIA2_CB_DAV_OUT = 1<<3

VIA     = 0xe840
VIA_PB  = VIA + 0
VIA_PCR = VIA + 12

VIA_PB_NDAC_IN  = 1<<0
VIA_PB_NRFD_OUT = 1<<1
VIA_PB_ATN_OUT  = 1<<2
VIA_PB_NRFD_IN  = 1<<6
VIA_PB_DAV_IN   = 1<<7

CRTC    = 0xe880
CRTC_ADDR = CRTC+0
CRTC_STATUS = CRTC+1
CRTC_DATA = CRTC+1

VIDEO   = 0x8000

ZEROPAGE

.global ptr
ptr:        .word 0
ptr1:       .word 0
dma:        .word 0    ; current DMA

.section header, "ax"
    .word $0401
    .word 1f, 1
    .byte $9e
    .asciz "1037"
1:
    .word 0

    ; Goodbye interrupts, we'll never use you again...

    sei
    ldx #0xff
    txs                     ; reset stack

    ; Copy the init code out of the way so we don't have to worry about
    ; overwriting it.

    lda #<init_load_addr
    sta ptr+0
    lda #>init_load_addr
    sta ptr+1
    lda #<init_exec_addr
    sta ptr1+0
    lda #>init_exec_addr
    sta ptr1+1

    ldy #0
    zrepeat
        lda (ptr), y
        sta (ptr1), y

        inc ptr+0
        zif_eq
            inc ptr+1
        zendif

        inc ptr1+0
        zif_eq
            inc ptr1+1
        zendif

        lda ptr1+0
        cmp #<init_end_addr
        zcontinueif_ne
        lda ptr1+1
        cmp #>init_end_addr
    zuntil_eq
    
    jmp _start

.section relocator, "ax"
.global _start
_start:
    ; Copy the BIOS to its final location at 0x200. This overwrites the current
    ; memory image, so care needs to be taken. This routine is _last_ in the
    ; file, so it doesn't get overwritten.

    ; Relocate the BIOS to the bottom of memory.

    zrepeat
        load = .
        lda bios_load_addr
        store = .
        sta bios_exec_addr

        inc load+1
        zif_eq
            inc load+2
        zendif

        inc store+1
        zif_eq
            inc store+2
        zendif

        lda store+1
        cmp #<bios_end_addr
        zcontinueif_ne
        lda store+2
        cmp #>bios_end_addr
    zuntil_eq
    
    ; Initialise the screen.

    jsr clear_screen

    lda #14
    sta VIA_PCR             ; lowercase

    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr entry_CONOUT
        pla
        tay
        dey
    zuntil_eq

    ; Load the BDOS.

    lda #0x28
    jsr ieee_putcmdb
    lda #0xf0               ; OPEN channel 2
    jsr ieee_putcmdb

    ldx #bdos_filename_end - bdos_filename - 1
    zrepeat
        lda bdos_filename, x
        jsr ieee_putb
        dex
    zuntil_eq
    lda bdos_filename
    jsr ieee_putlastb

    lda #0x3f               ; UNLISTEN
    jsr ieee_putcmdb

    lda #0x48               ; TALK device 8
    jsr ieee_putcmdb
    lda #0x60               ; SECOND channel 2
    jsr ieee_putcmdb

    lda #>__TPA_START__
    sta ptr1+1
    lda #0
    sta ptr1+0

    ldy #0
    zrepeat
        jsr ieee_getb
        php
        sta (ptr1), y

        iny
        zif_eq
            inc ptr1+1

            tya
            pha
            lda #'.'
            jsr entry_CONOUT
            pla
            tay
        zendif
        plp
    zuntil_cs

    lda #0x5f               ; UNTALK
    jsr ieee_putcmdb
    lda #0x28               ; LIST device 8
    jsr ieee_putcmdb
    lda #0xe0               ; CLOSE channel 0
    jsr ieee_putcmdb

    ; Relocate the BDOS.

    lda #>__TPA_START__
    ldx #__ZEROPAGE_START__
    jsr entry_RELOCATE
	
    ; Go!

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA_START__ + COMHDR_ENTRY

bdos_filename: ; reversed!
    .ascii "R,P,SODB"
bdos_filename_end:

banner: ; reversed!
    .byte 13, 10
    .ascii "56-M/PC"
banner_end:

; --- BIOS entrypoints ------------------------------------------------------

zproc entry_GETTPA
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc entry_SETTPA
    sta mem_base
    stx mem_end
    clc
    rts
zendproc

zproc entry_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc

zproc entry_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc entry_SETBANK
    rts
zendproc

; --- Keyboard handling -----------------------------------------------------

zproc entry_CONST
    rts
zendproc

zproc entry_CONIN
    rts
zendproc

; --- Screen handling -------------------------------------------------------

; Writes the character in A.

zproc entry_CONOUT
    cmp #13
    zif_eq
        lda #0
        sta cursorx
        rts
    zendif
    cmp #127
    zif_eq
        dec cursorx
        zif_mi
            inc cursorx
        zendif
        jsr calculate_cursor_address
        lda #' '
        sta (ptr), y
        rts
    zendif
    cmp #10
    beq write_nl

    pha
    jsr calculate_cursor_address
    pla
    jsr convert_ascii_to_screencode
    sta (ptr), y

    inc cursorx
    lda cursorx
    cmp #40
    zif_eq
        lda #0
        sta cursorx
        jmp write_nl
    zendif
    rts
zendproc

zproc convert_ascii_to_screencode
    ; Flip case.

    cmp #'A'
    zif_cs
        cmp #'Z'+1
        bcc swapcase
    zendif

    cmp #'a'
    zif_cs
        cmp #'z'+1
        zif_cc
        swapcase:
            eor #0x20
        zendif
    zendif

    ; This is from https://codebase64.org/doku.php?id=base:petscii_to_screencode&s[]=screencodes

	cmp #0x20		; if A<32 then...
	bcc ddRev

	cmp #0x60		; if A<96 then...
	bcc dd1

	cmp #0x80		; if A<128 then...
	bcc dd2

	cmp #0xa0		; if A<160 then...
	bcc dd3

	cmp #0xc0		; if A<192 then...
	bcc dd4

	cmp #0xff		; if A<255 then...
	bcc ddRev

	lda #0x7e		; A=255, then A=126
	bne ddEnd

dd2:
    and #0x5f		; if A=96..127 then strip bits 5 and 7
	bne ddEnd
dd3:
    ora #0x40		; if A=128..159, then set bit 6
	bne ddEnd
dd4:
    eor #0xc0		; if A=160..191 then flip bits 6 and 7
	bne ddEnd
dd1:
    and #0x3f		; if A=32..95 then strip bits 6 and 7
	bpl ddEnd		; <- you could also do .byte 0x0c here
ddRev:
    eor #0x80		; flip bit 7 (reverse on when off and vice versa)
ddEnd:

    rts
zendproc

zproc write_nl
    inc cursory
    lda cursory
    cmp #24
    zif_eq
        dec cursory
        jmp scroll_up
    zendif
    rts
zendproc

zproc scroll_up
    ldx #0              ; current line
    zrepeat
        txa
        jsr calculate_cursor_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        inx
        txa
        jsr calculate_cursor_address ; ptr is source pointer

        ldy #39
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #23
    zuntil_eq

    ldy #39
    lda #' '
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc clear_screen
    lda #0
    zrepeat
        pha
        jsr calculate_line_address

        ldy #39
        lda #' '
        zrepeat
            sta (ptr), y
            dey
        zuntil_mi

        pla
        clc
        adc #1
        cmp #25
    zuntil_eq

    lda #0
    sta cursorx
    sta cursory
    rts
zendproc

; Sets (ptr), y to the location of the cursor.
zproc calculate_cursor_address
    ldy cursorx
    lda cursory
    ; fall through
zendproc
; Sets ptr to the address of screen line A.
zproc calculate_line_address
    ; x*40 = x*8 + x*32.

    ; We have 25 lines. As 25*8 will fit in a byte, we can do this easily.

    asl a               ; a = y*2
    asl a               ; a = y*4
    asl a               ; a = y*8
    sta ptr+0           ; store y*8

    ; Anything more than this needs to be 16-bit arithmetic.

    asl a               ; = y*16
    rol ptr+1

    asl a               ; = y*13
    rol ptr+1

    ; Add.

    clc
    adc ptr+0
    sta ptr+0
    zif_cs
        inc ptr+1
    zendif

    ; Or in the video address.

    lda ptr+1
    and #0b00000011
    ora #>VIDEO
    sta ptr+1

    rts
zendproc

; --- Disk handling ---------------------------------------------------------

; Sets the current DMA address.

zproc entry_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc entry_SELDSK
    cmp #0
    zif_ne
        sec                 ; invalid drive
        rts
    zendif

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

zproc entry_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil_mi
    clc
    rts
zendproc

zproc entry_READ
    jsr change_sectors
    zif_cc
        lda sector_num+0
        ror a               ; bottom bit -> C
        lda #0
        ror a               ; C -> top bit, producing $00 or $80
        tax

        ldy #0
        zrepeat
            lda disk_buffer, x
            sta (dma), y
            iny
            inx
            cpy #$80
        zuntil_eq

        clc
    zendif
    rts
zendproc

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc entry_WRITE
    pha
    jsr change_sectors
    zif_cs
        pla
        sec
        rts
    zendif

    lda sector_num+0
    ror a               ; bottom bit -> C
    lda #0
    ror a               ; C -> top bit, producing $00 or $80
    tax

    ldy #0
    zrepeat
        lda (dma), y
        sta disk_buffer, x
        iny
        inx
        cpy #$80
    zuntil_eq

    lda #$80
    sta buffer_dirty

    pla
    zif_ne
        jmp flush_buffered_sector
    zendif

    clc
    rts
zendproc

zproc change_sectors
    sec
    rts
zendproc

zproc flush_buffered_sector
    sec
    rts
zendproc

.macro set1 port, bit
    lda \port
    ora #\bit
    sta \port
.endm

.macro set0 port, bit
    lda \port
    and #(~(\bit)) & 0xff
    sta \port
.endm

; See http://www.6502.org/users/andre/petindex/local/pet-io-2.txt
; https://www.pagetable.com/?p=1023
; http://www.primrosebank.net/computers/pet/documents/PET_and_the_IEEE488_Bus_text.pdf
; (appendix E)

zproc ieee_putcmdb
    pha
    set0 VIA_PB, VIA_PB_ATN_OUT
    pla
    jmp ieee_putb
zendproc

zproc ieee_putlastb
    ; Assert EOI and then send.

    pha
    lda #0x34
    sta PIA1_CA
    pla
zendproc
    ; fall through
zproc ieee_putb
    ; Deassert our own NRFD and NDAC and wait for NRFD=0 (i.e. ready for data)

    pha
    set1 VIA_PB, VIA_PB_NRFD_OUT
    set1 PIA2_CA, PIA2_CA_NDAC_OUT
    zrepeat
        lda VIA_PB
        and #VIA_PB_NRFD_IN
    zuntil_ne
    pla

    ; Send data, inverted.

    eor #0xff
    sta PIA2_PB

    ; Set DAV to 0 (i.e. data is available)

    set0 PIA2_CB, PIA2_CB_DAV_OUT

    ; Wait for acknowledgement.

    zrepeat
        lda VIA_PB
        and #VIA_PB_NDAC_IN
    zuntil_ne

    ; Release DAV, EOI, ATN and the data bus.

    set1 PIA2_CB, PIA2_CB_DAV_OUT
    set1 VIA_PB, VIA_PB_ATN_OUT
    lda #0x3c
    sta PIA1_CA
    lda #0xff
    sta PIA2_PB

    rts
zendproc

; Receives a byte into A. Sets C on EOI.

zproc ieee_getb
    ; Set NRFD = 1 (indicating we are ready for data).
    ; Set NDAC = 0 (no data acknowledgement).

    set1 VIA_PB, VIA_PB_NRFD_OUT
    set0 PIA2_CA, PIA2_CA_NDAC_OUT

    ; Wait for DAV.

    zrepeat
        lda VIA_PB
        and #VIA_PB_DAV_IN
    zuntil_eq

    ; Not ready for data.

    set0 VIA_PB, VIA_PB_NRFD_OUT
    
    ; Get the data.

    lda PIA2_PA
    eor #0xff
    pha

    ; Check for EOI.

    lda PIA1_PA
    and #PIA1_PA_EOI_IN
    clc
    zif_eq
        sec
    zendif

    ; Acknowledge the data.

    set1 PIA2_CA, PIA2_CA_NDAC_OUT

    ; Wait for !DAV.

    zrepeat
        lda VIA_PB
        and #VIA_PB_DAV_IN
    zuntil_ne

    ; Release NDAC and the data bus.

    set0 PIA2_CA, PIA2_CA_NDAC_OUT

    pla
    rts
zendproc
    
.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi

; DPH for drive 0 (our only drive)

define_drive dph, 136*10, 1024, 64, 0

.bss

pending_key:      .byte 0 ; pending keypress from system
sector_num:       .fill 3 ; current absolute sector number
buffered_sector:  .fill 3 ; sector currently in disk buffer
buffer_dirty:     .fill 1 ; non-zero if sector needs flushing

directory_buffer: .fill 128
disk_buffer:      .fill 256

cursorx:          .fill 1
cursory:          .fill 1

; vim: sw=4 ts=4 et ft=asm
