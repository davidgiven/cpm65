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

ZEROPAGE

ptr:        .fill 2
ptr1:       .fill 2
ptr2:       .fill 2
dma:        .fill 2

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

    ; Load the BDOS.

    lda #0xf0               ; OPEN channel 0
    jsr ieee_listen

    label:
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

    jmp .

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

; Kernel ROM disassembly here:
; http://www.fox-ts.co.uk/shared/vic20kernelrom.html
;
; Description of the terrible IEC protocol here:
; https://www.pagetable.com/?p=1135

; Returns a byte into A. If EOI was set, sets the EOI flag.

zproc ieee_getb
    jsr iec_assert_data
    jsr wait_for_iec_clock_high
    jsr iec_assert_data

    ldx #8
    zrepeat
        jsr wait_for_iec_clock_high
        ror ieee_byte
        jsr wait_for_iec_clock_low

        dex
    zuntil_eq

    jsr wait_and_then_release_iec
    lda ieee_byte
    rts
zendproc

; Sends A, with EOI set.

zproc ieee_puteoib
    pha
    lda #1
    sta ieee_eoi
    pla
    bne ieee_putb       ; always taken
zendproc

; Sends A, either with or without ATN set.

zproc ieee_putcmdb
    pha

    ; Assert clock and wait for all the devices to respond.

    jsr iec_assert_atn
    jsr iec_assert_clock
    jsr iec_release_data
    jsr wait_1ms

    pla
zendproc
    ; fall through
zproc ieee_putb
    sta ieee_byte

    ; Signify we're ready to send by releasing the clock.

    jsr iec_release_data
    jsr iec_release_clock
    jsr wait_for_iec_data_high

    ; Perform EOI sequence if necessary: we wait without sending the clock low.
    ; Eventually the device will aknowledge by pulling the data low.

    lda ieee_eoi
    zif_ne
        jsr wait_for_iec_data_low
        jsr wait_for_iec_data_high
    zendif

    ; Send clock low.

    jsr iec_assert_clock
    jsr wait_60us

    ; Now send a byte.

    txa
    pha
    ldx #8              ; bit count
    zrepeat
        ror ieee_byte
        jsr set_iec_data

        ; Put the clock high for ~60us signifying that the data is ready.

        jsr iec_release_clock
        jsr wait_60us
        jsr iec_assert_clock

        dex
    zuntil_eq
    pla
    tax

    ; Wait for the device to acknowledge by pulling data low.

    jsr wait_for_iec_data_low

    ; Release ATN and exit.

    jmp iec_release_atn
zendproc

; Performs a 1ms delay and then release both clock and data.

zproc wait_and_then_release_iec
    txa
    ldx #11
    zrepeat
        dex
    zuntil_eq
    tax

    jsr iec_release_clock
zendproc
    ; falls through

; Sets the data bit to C.

zproc set_iec_data
    bcc iec_assert_data
zendproc
    ; fall through
zproc iec_release_data
    ; IEC data goes high

    set0 VIA2_PCR, VIA2_PCR_CB2_DATA_OUT
    rts
zendproc

zproc wait_for_iec_data_high
    zrepeat
        jsr get_iec_status
    zuntil_cs
    rts
zendproc

zproc wait_for_iec_data_low
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

zproc wait_for_iec_clock_high
    zrepeat
        jsr get_iec_status
    zuntil_mi
    rts
zendproc

zproc wait_for_iec_clock_low
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
    sta VIA2_T2CL
    lda #0
    sta VIA2_T2CH
    beq timer_wait              ; always taken
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

cursorx:   .fill 1
cursory:   .fill 1
ieee_byte: .fill 1
ieee_eoi:  .fill 1

; vim: sw=4 ts=4 et ft=asm

