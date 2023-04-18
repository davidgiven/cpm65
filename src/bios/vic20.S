; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

;https://www.antimon.org/dl/c64/code/stable.txt

TEXT = 0x1000
FRAMEBUFFER = 0x1100
COLOURRAM = 0x9400

VIA1     = 0x9110
VIA1_PB  = VIA1 + 0x0
VIA1_PCR = VIA1 + 0xc
VIA1_DRA = VIA1 + 0xf

VIA2     = 0x9120
VIA2_PB  = VIA2 + 0x0
VIA2_PCR = VIA2 + 0xc
VIA2_DRA = VIA2 + 0xf

ZEROPAGE

ptr:		.fill 2
ptr1:		.fill 2
ptr2:		.fill 2
dma:		.fill 2

.section header, "ax"
    .word $1201
    .word 1f, 1
    .byte $9e
    .asciz "4621"
1:
    .word 0
.global _start
_start:
    ; Goodbye interrupts, we'll never use you again...

    sei

    ; Relocate the BIOS.

    zrepeat
        load1 = .
        lda bios_load_addr
        store1 = .
        sta bios_exec_addr

        inc load1+1
        zif_eq
            inc load1+2
        zendif

        inc store1+1
        zif_eq
            inc store1+2
            zbreakif_eq
        zendif

		lda store1+1
		cmp #<bios_end_addr
		zcontinueif_ne
		lda store1+2
		cmp #>bios_end_addr
    zuntil_eq

	; Relocate the init code --- we can't execute it here because BASIC will
	; load it right into the middle of what we're going to use as video memory.

    zrepeat
        load2 = .
        lda init_load_addr
        store2 = .
        sta init_exec_addr

        inc load2+1
        zif_eq
            inc load2+2
        zendif

        inc store2+1
        zif_eq
            inc store2+2
            zbreakif_eq
        zendif

		lda store2+1
		cmp #<init_end_addr
		zcontinueif_ne
		lda store2+2
		cmp #>init_end_addr
    zuntil_eq

	jmp _init

.section init, "ax"
_init:
	; Initialise the VIC.

	ldx #vic_tab_end - vic_tab
	zrepeat
		lda vic_tab-1, x
		sta 0x9000-1, x
		dex
	zuntil_eq

	lda #0x08			; black border, black background, inverted
	sta 0x900f

	jsr clear_screen

	lda #0
	sta cursorx
	sta cursory

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

	; IEC initialisation.

	; Y is 0
	sty ieee_eoi

	jmp .

banner:
	.byte 10, 13
	.ascii "02-CIV eht rof 56-M/PC"
banner_end:

vic_tab:
	.byte 14   			; 0x9000: abbbbbbb: interlace, screen X
	.byte 35            ; 0x9001: cccccccc: screen Y
	.byte 0x00 | 20     ; 0x9002: hddddddd: screen address, screen width
	.byte (12<<1) | 1   ; 0x9003: geeeeeef: screen height, char size
	.byte 0             ; 0x9004: gggggggg: variable
	.byte 0xcc          ; 0x9005: hhhhiiii: screen address, char address
vic_tab_end:
zendproc

; --- Screen handling ----------------------------------------------------

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
        jsr draw_glyph
        rts
    zendif
    cmp #10
    beq write_nl

    pha
    jsr calculate_cursor_address
    pla
    jsr draw_glyph

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
	rts
zendproc

zproc clear_screen
	; Reset the character mapping on the screen.

	ldx #16
	zrepeat
		txa
		sta TEXT-0x10, x
		lda #1
		sta COLOURRAM-0x10, x
		inx
	zuntil_eq

	; Clear the bitmap itself.

	ldx #>(FRAMEBUFFER + 0xf00)
	ldy #0
	tya
	sta ptr+0
	zrepeat
		stx ptr+1
		zrepeat
			lda #0
			sta (ptr), y
			dec ptr+1
			lda ptr+1
			cmp #>(FRAMEBUFFER - 0x100)
		zuntil_eq
		iny
	zuntil_eq

	rts
zendproc

; Calculates into ptr the address of bitmap line A.

zproc calculate_line_address
	; The bottom bit of Y turns into a +8 offset at the end.

	pha
	and #0xfe		; 'x2'
	asl a			; x4
	sta ptr+0
	asl a			; x8
	asl a			; x16
	clc
	adc ptr+0		; =x20; may overflow
	sta ptr+0
	lda #0
	zif_cs
		lda #1
	zendif

	; Now multiply the whole lot by 16 to get the byte address.

	asl ptr+0
	rol a
	asl ptr+0
	rol a
	asl ptr+0
	rol a
	asl ptr+0
	rol a
	
	; Add on the actual framebuffer address.

	clc
	adc #>FRAMEBUFFER
	sta ptr+1

	; Add on the +8 offset for odd lines.

	pla
	ror a
	zif_cs
		clc
		lda #8
		adc ptr+0
		sta ptr+0
		zif_cs
			inc ptr+1
		zendif
	zendif
	rts
zendproc

; Calculates into ptr the address of the cursor.

zproc calculate_cursor_address
	lda cursory
	jsr calculate_line_address

	lda cursorx
	and #0xfe
	asl a			; x2

	sta ptr1+0
	lda #0			; x4

	asl ptr1+0		; x8
	rol a

	asl ptr1+0		; x16; top bit into carry
	rol a

	sta ptr1+1

	clc
	lda ptr+0
	adc ptr1+0
	sta ptr+0

	lda ptr+1
	adc ptr1+1
	sta ptr+1
	rts
zendproc

; Draws glyph A into (ptr), y.

zproc draw_glyph
	sec
	sbc #32			; get glyph offset

	asl a			; x2
	sta ptr1+0

	lda #0
	asl ptr1+0
	rol a			; x4

	asl ptr1+0
	rol a			; x8

	sta ptr1+1
	clc
	lda #<font_tab
	adc ptr1+0
	sta ptr1+0

	lda #>font_tab
	adc ptr1+1
	sta ptr1+1

	; ptr1 now contains the glyph address.

	lda cursorx
	ror a
	lda #0x0f
	ldy #0xf0
	zif_cs
		; Off address.

		lda #0xf0
		ldy #0x0f
	zendif

	sta ptr2+0
	sty ptr2+1

	ldy #7
	zrepeat
		lda (ptr), y
		and ptr2+0
		sta (ptr), y

		lda (ptr1), y
		and ptr2+1
		ora (ptr), y
		sta (ptr), y

		dey
	zuntil_eq
	rts

font_tab:
	#include ".obj/4x8font.inc"
zendproc

; --- Disk handling ---------------------------------------------------------

; Kernel ROM disassembly here:
; http://www.fox-ts.co.uk/shared/vic20kernelrom.html

zproc ieee_putcmdb
	pha
	jsr set_iec_data_high
	jsr set_iec_clock_high

	lda VIA1_DRA
	ora #0x80 			; set ATN low
	sta VIA1_DRA

	pla
zendproc
	; fall through
zproc ieee_putb
	sta ieee_byte

	jsr set_iec_data_high
	jsr get_iec_status
	zif_mi
		sec				; device not present
		rts
	zendif

	; Wait for the IEC data to rise.

	jsr wait_for_iec_data_high

	; Perform EOI sequence if necessary: we wait without sending the clock low.
	; Eventually the device will aknowledge by pulling the data low.

	lda ieee_eoi
	zif_ne
		zrepeat
			jsr get_iec_status
		zuntil_pl ; data low
		jsr wait_for_iec_data_high
	zendif

	; Send clock low.

	jsr set_iec_clock_low

	; Now send a byte.

	ldx #8				; bit count
	zrepeat
		jsr get_iec_status
		zif_pl
			sec
			rts			; if data low, timeout
		zendif

		ror ieee_byte
		jsr set_iec_data

		; Put the clock high for ~26 cycles.

		jsr set_iec_clock_high

		ldy #5			; 2
		zrepeat
			dey			; 2
		zuntil_eq		; 3 if taken; 5 per loop

		lda VIA2_PCR
		and #0xdf		; CB2 low (serial data high)
		ora #0x02		; CA2 high (serial data low)
		sta VIA2_PCR

		dex
	zuntil_eq

	; Wait for the device to acknowledge by pulling data low.

	zrepeat
		jsr get_iec_status
	zuntil_pl

	lda VIA1_DRA
	and #0x7f 			; release ATN
	sta VIA1_DRA

	rts
zendproc

; Sets the data bit to C.

zproc set_iec_data
	bcc set_iec_data_low
zendproc
	; fall through
zproc set_iec_data_high
	lda VIA2_PCR
	and #0xdf ; set CB2 low (iec data goes high)
	sta VIA2_PCR
	rts
zendproc

zproc wait_for_iec_data_high
	zrepeat
		jsr get_iec_status
	zuntil_cs
	rts
zendproc

zproc set_iec_data_low
	lda VIA2_PCR
	ora #0x02 ; set CB2 high (iec data goes low)
	sta VIA2_PCR
	rts
zendproc

zproc set_iec_clock_high
	lda VIA2_PCR
	and #0xfd ; set CA2 low (iec clock goes high)
	sta VIA2_PCR
	rts
zendproc

zproc set_iec_clock_low
	lda VIA2_PCR
	ora #0x02 ; set CA2 high (iec clock goes low)
	sta VIA2_PCR
	rts
zendproc

; Returns the clock bit in N and the data bit in C.

zproc get_iec_status
	zrepeat
		lda VIA1_DRA
		cmp VIA1_DRA
	zuntil_eq
	ror a
	ror a
	rts
zendproc

zproc print_hex_number
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr print
	pla
print:
	and #0x0f
	ora #48
	cmp #58
    zif_cs
        adc #6
    zendif
	pha
	jsr entry_CONOUT
	pla
	rts
zendproc

ZEROPAGE

cursorx:   .fill 1
cursory:   .fill 1
ieee_byte: .fill 1
ieee_eoi:  .fill 1
