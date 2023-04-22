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
ptr:              .fill 2
ptr1:             .fill 2
dma:              .fill 2    ; current DMA
sector_num:       .fill 3 ; current absolute sector number
buffered_sector:  .fill 3 ; sector currently in disk buffer

pending_key:      .fill 1 ; pending keypress from system
buffer_dirty:     .fill 1 ; non-zero if sector needs flushing
cursorx:          .fill 1
cursory:          .fill 1

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

    ; Miscellaneous initialisation.

    lda #0
    sta shift_pressed
    sta pending_key
    sta buffer_dirty

    jsr ieee_init

    ldx #10
    lda #0xff
    zrepeat
        sta keyboard_state, x
        dex
    zuntil_mi

    ; Load the BDOS.

    lda #0xf0               ; OPEN channel 0
    jsr ieee_listen

    ldx #bdos_filename_end - bdos_filename
    zrepeat
        lda bdos_filename-1, x
        jsr ieee_write
        dex
    zuntil_eq
    jsr ieee_unlisten

    lda #0                  ; channel 0
    jsr ieee_talk

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

    jsr ieee_untalk

    lda #0xe0               ; CLOSE channel 0
    jsr ieee_listen
    jsr ieee_unlisten

    lda #0xf2               ; OPEN channel 2 (for use with sector I/O)
    jsr ieee_listen
    ldx #allocate_cmd_end - allocate_cmd
    zrepeat
        lda allocate_cmd-1, x
        jsr ieee_write
        dex
    zuntil_eq
    jsr ieee_unlisten

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

allocate_cmd: ; reversed!
    .ascii "2#"
allocate_cmd_end:

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

; Returns 0xff if no key is pending, 0 if one is.

zproc entry_CONST
    jsr scan_keyboard

    lda pending_key
    zif_ne
        lda #0xff
    zendif

    clc
    rts
zendproc

; Blocks until a key is pressed; returns it in A.

zproc entry_CONIN
    jsr calculate_cursor_address
    lda (ptr), y
    eor #0x80
    sta (ptr), y

    lda pending_key
    zif_eq
        zrepeat
            jsr scan_keyboard
            lda pending_key
        zuntil_ne
    zendif

    ldx #0
    stx pending_key

    pha
    jsr calculate_cursor_address
    lda (ptr), y
    eor #0x80
    sta (ptr), y
    pla

    clc
    rts
zendproc

; Does a single keyboard scan, processing any pressed keys. Last pressed key
; wins.

zproc scan_keyboard
    ldy #0
    zrepeat
        sty ptr+0
        lda PIA1_PA
        and #0xf0
        ora ptr+0
        sta PIA1_PA

        ldx PIA1_PB
        txa
        eor keyboard_state, y
        zif_ne
            ; Any set bits in A correspond to a key which has changes state.
            ; The corresponding bit in X tells us whether it went up or down.

            sta ptr1+0
            stx ptr1+1

            pha
            txa
            pha
            tya
            pha

            txa
            sta keyboard_state, y

            tya
            asl a
            asl a
            asl a       ; compute row*8 to get base of scancode number
            tay

            zrepeat
                bit ptr1+0
                zif_mi
                    ; This key has changed.

                    tya
                    pha
                    jsr change_key_state
                    pla
                    tay
                zendif
    
                iny
                asl ptr1+1
                asl ptr1+0
            zuntil_eq

            pla
            tay
            pla
            tax
            pla
        zendif

        iny
        cpy #0x0a
    zuntil_eq
    rts
zendproc

; The key with scancode Y has changed state. Whether it's up or down is in
; the top bit of ptr1+1.

zproc change_key_state
    cpy #0x47               ; left shift
    beq shift_change
    cpy #0x42               ; right shift
    beq shift_change

    bit ptr1+1
    zif_pl
        lda keyboard_decode_tab, y

        bit shift_pressed
        zif_pl
            cmp #'a'
            zif_cs
                cmp #'z'+1
                eor #0x20
            zendif
        zendif
        sta pending_key
    zendif
    rts

    ; Shift gets special treatment because we care about ups as well as downs.

shift_change:
    lda keyboard_state + 8
    rol a
    rol a
    rol a
    rol a                   ; left shift state in bit 0
    and keyboard_state + 8  ; right shift state in bit 0
    ror a
    ror a
    sta shift_pressed       ; new state in top bit
    rts

keyboard_decode_tab:
    .byte 0x00, 0x00, '_',  '(',  '&',  '%',  '#',  '!'  ; 0x00
    .byte 0x7f, 0x00, 0x00, ')',  '\\', '\'', '$',  '"'  ; 0x08
    .byte '9',  '7',  '^',  'o',  'u',  't',  'e',  'q'  ; 0x10
    .byte '/',  '8',  0x00, 'p',  'i',  'y',  'r',  'w'  ; 0x18
    .byte '6',  '4',  0x00, 'l',  'j',  'g',  'd',  'a'  ; 0x20
    .byte '*',  '5',  0x00, ':',  'k',  'h',  'f',  's'  ; 0x28
    .byte '3',  '1',  0x0d, ';',  'm',  'b',  'c',  'z'  ; 0x30
    .byte '+',  '2',  0x00, '?',  '.',  'n',  'v',  'x'  ; 0x38
    .byte '-',  '0',  0x00, '>',  0x00, ']',  '@',  0x00 ; 0x40
    .byte '=',  '.',  0x00, 0x1b, '<',  ' ',  '[',  0x00 ; 0x48
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
        jsr calculate_line_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        inx
        txa
        jsr calculate_line_address ; ptr is source pointer

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

; Returns C on error.

zproc change_sectors
    ; If the buffered sector is the one we want, just return.

    lda sector_num+0
    and #$fe
    cmp buffered_sector+0
    zif_eq
        lda sector_num+1
        cmp buffered_sector+1
        zif_eq
            lda sector_num+2
            cmp buffered_sector+2
            zif_eq
                clc
                rts
            zendif
        zendif
    zendif

    ; We need to change sectors. Flush the current one?

    jsr flush_buffered_sector

    ; Now read the new one.

    lda sector_num+0
    and #$fe
    sta buffered_sector+0
    lda sector_num+1
    sta buffered_sector+1
    lda sector_num+2
    sta buffered_sector+2

    jsr buffered_sector_to_lba
    jmp read_sector
zendproc

; Reads a 256-byte sector whose LBA index is in XA.

zproc read_sector
    jsr convert_to_ts
    pha
    tya
    pha

    lda #0x6f               ; SECOND channel 15
    jsr ieee_listen

    ldx #u1_string_end - u1_string
    zrepeat
        lda u1_string-1, x
        jsr ieee_write
        dex
    zuntil_eq

    pla
    jsr decimal_out

    pla
    jsr decimal_out
    jsr ieee_unlisten

    lda #0x62               ; SECOND channel 2
    jsr ieee_talk

    ldy #0
    zrepeat
        jsr ieee_getb
        sta disk_buffer, y
        iny
    zuntil_cs

    jsr ieee_untalk
    clc
    rts

u1_string:
    .ascii "0 2 1U" ; reversed!
u1_string_end:
zendproc

; Writes a 256-byte sector whose LBA index is in XA.

zproc write_sector
    jsr convert_to_ts
    pha
    tya
    pha

    ; Reset buffer pointer.

    lda #0x6f               ; SECOND channel 15
    jsr ieee_listen

    ldx #bp_string_end - bp_string
    zrepeat
        lda bp_string-1, x
        jsr ieee_write
        dex
    zuntil_eq

    jsr ieee_unlisten

    ; Write bytes.

    lda #0x62               ; SECOND channel 2
    jsr ieee_listen

    ldy #0
    zrepeat
        lda disk_buffer, y
        jsr ieee_write
        iny
    zuntil_eq

    jsr ieee_unlisten

    ; Write sector to disk.

    lda #0x6f               ; SECOND channel 15
    jsr ieee_listen

    ldx #u2_string_end - u2_string
    zrepeat
        lda u2_string-1, x
        jsr ieee_write
        dex
    zuntil_eq

    pla
    jsr decimal_out

    pla
    jsr decimal_out

    jsr ieee_unlisten

    clc
    rts

bp_string:
    .ascii "0 2 P-B" ; reversed!
bp_string_end:
u2_string:
    .ascii "0 2 2U" ; reversed!
u2_string_end:
zendproc

.if 0
zproc getstatus
    lda #0x6f
    jsr ieee_talk

    zloop
        jsr ieee_getb
        zbreakif_cs
        jsr entry_CONOUT
    zendloop
   
    lda #0x0d
    jsr entry_CONOUT
    lda #0x0a
    jsr entry_CONOUT
    jsr ieee_untalk
    rts
zendproc
.endif

; Prints a decimal number in A to the IEEE output.

zproc decimal_out
    pha
    lda #' '
    jsr ieee_write
    pla

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #100
    zuntil_cc
    adc #100
    jsr digit

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #10
    zuntil_cc
    adc #10
    jsr digit
    tax
digit:
    pha
    txa
    ora #'0'
    jsr ieee_write
    pla
    rts
zendproc

; Converts an LBA sector number in XA to track/sector in Y, A.

zproc convert_to_ts
    ldy #0
    zloop
        cpx #0
        zif_eq
            cmp track_size_table, y
            zif_cc
                iny     ; tracks are one-based.
                rts
            zendif
        zendif

        sec
        sbc track_size_table, y
        zif_cc
            dex
        zendif
        iny
    zendloop

track_size_table:
    .fill 17, 1, 21
    .fill 7, 1, 19
    .fill 6, 1, 18
    .fill 10, 1, 17
zendproc

; Compute the current LBA sector number in XA for the buffered sector.

zproc buffered_sector_to_lba
    lda buffered_sector+1
    lsr a
    tax
    lda buffered_sector+0
    ror
    rts
zendproc

zproc flush_buffered_sector
    bit buffer_dirty
    zif_mi
        jsr buffered_sector_to_lba
        jsr write_sector

        lda #0
        sta buffer_dirty
    zendif
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

zproc ieee_mode_atn
    set0 VIA_PB, VIA_PB_ATN_OUT
    rts
zendproc

zproc ieee_mode_talk
    set1 VIA_PB, VIA_PB_ATN_OUT
    rts
zendproc

; Switch from ATN mode to LISTEN mode.

zproc ieee_mode_listen
    set1 VIA_PB, VIA_PB_ATN_OUT
    rts
zendproc

zproc ieee_puteoib
    pha
    lda #0x34               ; assert EOI
    sta PIA1_CA
    pla

    bne ieee_putb           ; always taken
zendproc

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

    ; Release DAV, EOI, and the data bus.

    set1 PIA2_CB, PIA2_CB_DAV_OUT
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

directory_buffer: .fill 128
disk_buffer:      .fill 256

keyboard_state:   .fill 10
shift_pressed:    .fill 1

; vim: sw=4 ts=4 et ft=asm
