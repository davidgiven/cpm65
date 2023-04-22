; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "wait.inc"

;https://www.antimon.org/dl/c64/code/stable.txt

TEXT = 0x1000
FRAMEBUFFER = 0x1100
COLOURRAM = 0x9400

VIA1     = 0x9110
VIA1_PB  = VIA1 + 0x0
VIA1_PA  = VIA1 + 0x1
VIA1_PCR = VIA1 + 0xc
VIA1_DRA = VIA1 + 0xf

VIA1_PA_ATN_OUT = 1<<7

VIA2      = 0x9120
VIA2_PB   = VIA2 + 0x0
VIA2_PA   = VIA2 + 0x1
VIA2_T2CL = VIA2 + 0x8
VIA2_T2CH = VIA2 + 0x9
VIA2_PCR  = VIA2 + 0xc
VIA2_IFR  = VIA2 + 0xd
VIA2_DRA  = VIA2 + 0xf

VIA2_IFR_T2 = 1<<5

VIA2_PCR_CA2_CLOCK_OUT = 1<<1
VIA2_PCR_CB1_SRQ_IN    = 1<<4
VIA2_PCR_CB2_DATA_OUT  = 1<<5

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

.macro set10 port, bitson, bitsoff
    lda \port
    ora #\bitson
    and #(~(\bitsoff)) & 0xff
    sta \port
.endm

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

    lda #0x08           ; black border, black background, inverted
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
    jsr ieee_init

    ldy #3
    zrepeat
        lda #0
        sta sector_num-1, y
        lda #0xff
        sta buffered_sector-1, y
        dey
    zuntil_eq

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

    lda #0x60
    jsr ieee_talk

    sei
    zrepeat
        jsr ieee_getb
        php

    1:
        sta __TPA_START__

        inc 1b+1
        zif_eq
            inc 1b+2

            lda #'.'
            jsr entry_CONOUT
        zendif
        plp
    zuntil_cs
    jsr ieee_untalk

    lda #'!'
    jsr entry_CONOUT

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

banner:
    .byte 10, 13
    .ascii "02-CIV eht rof 56-M/PC"
banner_end:

vic_tab:
    .byte 14            ; 0x9000: abbbbbbb: interlace, screen X
    .byte 35            ; 0x9001: cccccccc: screen Y
    .byte 0x00 | 20     ; 0x9002: hddddddd: screen address, screen width
    .byte (12<<1) | 1   ; 0x9003: geeeeeef: screen height, char size
    .byte 0             ; 0x9004: gggggggg: variable
    .byte 0xcc          ; 0x9005: hhhhiiii: screen address, char address
vic_tab_end:
zendproc

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
    lda #0
    clc
    rts

;    jsr scan_keyboard
;
;    lda pending_key
;    zif_ne
;        lda #0xff
;    zendif
;
;    clc
;    rts
zendproc

; Blocks until a key is pressed; returns it in A.

zproc entry_CONIN
    jmp .
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
    and #0xfe       ; 'x2'
    asl a           ; x4
    sta ptr+0
    asl a           ; x8
    asl a           ; x16
    clc
    adc ptr+0       ; =x20; may overflow
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
    asl a           ; x2

    sta ptr1+0
    lda #0          ; x4

    asl ptr1+0      ; x8
    rol a

    asl ptr1+0      ; x16; top bit into carry
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
    sbc #32         ; get glyph offset

    asl a           ; x2
    sta ptr1+0

    lda #0
    asl ptr1+0
    rol a           ; x4

    asl ptr1+0
    rol a           ; x8

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

.if 1
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
; Kernel ROM disassembly here:
; http://www.fox-ts.co.uk/shared/vic20kernelrom.html
;
; Description of the terrible IEC protocol here:
; https://www.pagetable.com/?p=1135

; Switch from either TALK or LISTEN mode to ATN mode.

zproc ieee_mode_atn
    jsr iec_assert_atn
    jsr iec_assert_clock
    jsr iec_release_data
    jmp wait_1ms
zendproc

; Switch from ATN mode to TALK mode.

zproc ieee_mode_talk
    jmp iec_release_atn
zendproc

; Switch from ATN mode to LISTEN mode.

zproc ieee_mode_listen
    jsr iec_release_atn
    jsr iec_assert_data
    jsr iec_release_clock
    jmp wait_for_iec_clock_assert
zendproc

; Returns a byte into A. If EOI was set, sets C.

zproc ieee_getb
    ; Wait for the talker to indicate it's ready to send.

    jsr wait_for_iec_clock_release

    ; Indicate that we're ready to receive.

    jsr iec_release_data

    ; Wait for the talker to assert clock, indicating that it's starting.
    ; There's a timeout here used for indicating EOI.

    lda #0
    sta ieee_eoi
    lda #1          ; 256us timeout
    sta VIA2_T2CH
    zrepeat
        lda VIA2_IFR
        and #VIA2_IFR_T2
        zif_ne
            ; Timeout. Acknowledge EOI by toggling data.

label:
            jsr iec_assert_data
            jsr wait_1ms
            jsr iec_release_data
            inc ieee_eoi
        zendif

        jsr get_iec_status
    zuntil_pl ; until clock is asserted

    ; The talker will clock in bits on clock release edges.

    txa
    pha
	ldx #8
    zrepeat
        jsr wait_for_iec_clock_release
        ror	ieee_byte
        jsr wait_for_iec_clock_assert

        dex
    zuntil_eq
    pla
    tax

    ; Acknowledge receipt by asserting data.

    jsr iec_assert_data

    lda ieee_eoi        ; bottom bit set on EOI
    ror a               ; move into C
	lda	ieee_byte
    rts
zendproc

; Sends A, with EOI set.

zproc ieee_puteoib
    pha
    lda #1
    sta ieee_eoi
    pla
zendproc
    ; fall through

; Sends A. Returns C on error.

zproc ieee_putb
    sta ieee_byte

    ; Ensure there is actually a device on the other end by releasing data and
    ; seeing if the device has it asserted. If it's not, there's nothing there.

    jsr iec_release_data
    jsr get_iec_status
    zif_cs
        ; Device not present.

        sec
        rts
    zendif

    ; Tell the device we're ready to send by releasing clock.

    jsr iec_release_clock

    ; Perform EOI sequence if necessary: we wait without sending the clock low.
    ; Eventually the receiver will aknowledge by briefly asserting data. (Not
    ; sure how this behaves with multiple receivers?)

    lda ieee_eoi
    zif_ne
        jsr wait_for_iec_data_release
        jsr wait_for_iec_data_assert
    zendif

    ; Now that we're ready, wait for the device to acknowledge by releasing
    ; data.

    jsr wait_for_iec_data_release

    ; Assert clock and go.

    jsr iec_assert_clock

    ; Now send a byte.

    txa
    pha
    ldx #8              ; bit count
    zrepeat
        zrepeat
            lda VIA1_DRA
            cmp VIA1_DRA
        zuntil_eq
        ror a
        ror a           ; put data into carry
        zif_cs
            ; timeout
        zendif

        ror ieee_byte
        jsr set_iec_data_from_carry

        ; Leave the clock released for 26 cycles.

        jsr iec_release_clock               ; uses 6 cycles after changing clock
        WAIT12                              ; 12
        lda VIA2_PCR                        ; 4
        and #~VIA2_PCR_CB2_DATA_OUT & 0xff  ; 2
        ora #VIA2_PCR_CA2_CLOCK_OUT         ; 2
        sta VIA2_PCR                        ; 4; total delay, 26 cycles

        dex
    zuntil_eq
    pla
    tax

    ; We are now done. Wait for the receivers to acknowledge by asserting data.

    jsr wait_for_iec_data_assert
    lda #0
    sta ieee_eoi
    clc
    rts
zendproc

; Sets the data bit to C.

zproc set_iec_data_from_carry
    bcc iec_assert_data
zendproc
    ; fall through
zproc iec_release_data
    ; IEC data goes high

    set0 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT
    rts
zendproc

zproc wait_for_iec_data_release
    zrepeat
        jsr get_iec_status
    zuntil_cs
    rts
zendproc

zproc wait_for_iec_data_assert
    zrepeat
        jsr get_iec_status
    zuntil_cc
    rts
zendproc

zproc iec_assert_data
    ; IEC data goes low

    set1 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT
    rts
zendproc

zproc wait_for_iec_clock_release
    zrepeat
        jsr get_iec_status
    zuntil_mi
    rts
zendproc

zproc wait_for_iec_clock_assert
    zrepeat
        jsr get_iec_status
    zuntil_pl
    rts
zendproc

zproc iec_release_clock
    ; Set low; IEC clock goes high

    set0 VIA2_PCR, VIA2_PCR_CA2_CLOCK_OUT
    rts
zendproc

zproc iec_assert_clock
    ; Set high; IEC clock goes low

    set1 VIA2_PCR, VIA2_PCR_CA2_CLOCK_OUT
    rts
zendproc

zproc iec_release_atn
    ; Set low; IEC ATN goes high

    set0 VIA1_DRA, VIA1_PA_ATN_OUT
    rts
zendproc

zproc iec_assert_atn
    ; Set high; IEC ATN goes low

    set1 VIA1_DRA, VIA1_PA_ATN_OUT
    rts
zendproc

; Returns the clock bit in N and the data bit in C.

zproc get_iec_status
    ; VIA1 PA has format xxxxxxDC.

    zrepeat
        lda VIA1_DRA
        cmp VIA1_DRA
    zuntil_eq
    ror a
    ror a
    rts
zendproc

; Waits for 60us.

zproc wait_60us
    lda #60
wait_us:
    sta VIA2_T2CL
    lda #0
    sta VIA2_T2CH
    jmp timer_wait              ; always taken
zendproc

; Waits for 1ms.

zproc wait_1ms
    lda #4
    sta VIA2_T2CH
timer_wait:
    zrepeat
        lda VIA2_IFR
        and #VIA2_IFR_T2
    zuntil_ne
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

.global ptr
ptr:        .fill 2
ptr1:       .fill 2
ptr2:       .fill 2
dma:        .fill 2

sector_num:       .fill 3 ; current absolute sector number
buffered_sector:  .fill 3 ; sector currently in disk buffer

cursorx:   .fill 1
cursory:   .fill 1
ieee_byte: .fill 1
ieee_eoi:  .fill 1
buffer_dirty:     .fill 1 ; non-zero if sector needs flushing

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi

.bss

directory_buffer: .fill 128
disk_buffer:      .fill 256

; DPH for drive 0 (our only drive)

define_drive dph, 136*10, 1024, 64, 0

; vim: sw=4 ts=4 et ft=asm

