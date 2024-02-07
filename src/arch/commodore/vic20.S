; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "wait.inc"
#include "driver.inc"

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

zproc _init, .init
    ; Initialise the VIC.

    ldx #vic_tab_end - vic_tab
    zrepeat
        lda vic_tab-1, x
        sta 0x9000-1, x
        dex
    zuntil_eq

    lda #0x08           ; black border, black background, inverted
    sta 0x900f

    jsr initdrivers
    jsr clear_screen

    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr bios_CONOUT
        pla
        tay
        dey
    zuntil_eq

    ; Miscellaneous initialisation.

    ; Y is 0
    sty ieee_eoi
    sty pending_key
    jsr ieee_init

    ldy #7
    lda #0xff
    zrepeat
        sta keyboard_state, y
        dey
    zuntil_mi

    ; Set up for sector I/O.

    lda #0xf2               ; OPEN channel 2 (for use with sector I/O)
    jsr ieee_listen
    ldx #allocate_cmd_end - allocate_cmd
    zrepeat
        lda allocate_cmd-1, x
        jsr ieee_write
        dex
    zuntil_eq
    jsr ieee_unlisten

    ; Load the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy #>__HIGHTPA_START__
    jsr loadfile

    ; Relocate the BDOS.

    lda #>__HIGHTPA_START__
    ldx #__ZEROPAGE_START__
    jsr bios_RELOCATE

    ; Go!

    lda #<biosentry
    ldx #>biosentry
    jmp __HIGHTPA_START__ + COMHDR_ENTRY

bdos_filename:
    .ascii "BDOS    SYS"

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

zproc bios_GETTPA
    ldy current_bank
    lda mem_base, y
    ldx mem_end, y
    clc
    rts
zendproc

zproc bios_SETTPA
    ldy current_bank
    sta mem_base, y
    txa                 ; BUG: stx mem_end, y - invalid 6502 instruction
    sta mem_end, y
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
    sta current_bank
    rts
zendproc

; --- Keyboard handling -----------------------------------------------------

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    pha
    lda jmptable_lo, y
    sta ptr+0
    lda jmptable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

jmptable_lo:
    .byte tty_const@mos16lo
    .byte tty_conin@mos16lo
    .byte tty_conout@mos16lo
jmptable_hi:
    .byte tty_const@mos16hi
    .byte tty_conin@mos16hi
    .byte tty_conout@mos16hi
zendproc

; Returns 0xff if no key is pending, 0 if one is.

zproc tty_const
    jsr scan_keyboard

    lda pending_key
    zif_ne
        lda #0xff
    zendif

    clc
    rts
zendproc

; Blocks until a key is pressed; returns it in A.

zproc tty_conin
    jsr toggle_cursor

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
    jsr toggle_cursor
    pla

    clc
    rts
zendproc

; Does a single keyboard scan, processing any pressed keys. Last pressed key
; wins.

zproc scan_keyboard
    lda #0xfe
    sta VIA2_PB

    ldy #0
    zrepeat
        zrepeat
            ldx VIA2_PA
            cpx VIA2_PA
        zuntil_eq

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

        sec
        rol VIA2_PB

        iny
        cpy #8
    zuntil_eq
    rts
rts

; The key with scancode Y has changed state. Whether it's up or down is in
; the top bit of ptr1+1.

zproc change_key_state
    bit ptr1+1
    zif_pl
        lda keyboard_state+2
        and #0x01
        beq control_pressed

        lda keyboard_state+3
        and #0x02
        beq shift_pressed       ; left shift

        lda keyboard_state+4
        and #0x40
        beq shift_pressed       ; right shift

        ; Normal keypress

        lda normal_keytab, y
        sta pending_key
    zendif
    rts

shift_pressed:
    lda shift_keytab, y
    sta pending_key
    rts

control_pressed:
    lda normal_keytab, y
    and #0x1f
    sta pending_key
    rts

normal_keytab:
    .byte 0x08, '#',  '+',  '9',  '7',  '5',  '3',  '1'  ; 08
    .byte 0x0d, '*',  'p',  'i',  'y',  'r',  'w',  '`'  ; 10
    .byte 0x00, ';',  'l',  'j',  'g',  'd',  'a',  0x00 ; 18
    .byte '/',  ',',  0x00, 'n',  'v',  'x',  0x00, 0x1b ; 20
    .byte 0x00, 0x00, '.',  'm',  'b',  'c',  'z',  ' '  ; 28
    .byte 0x00, '=',  ':',  'k',  'h',  'f',  's',  0x00 ; 30
    .byte 0x00, 0x00, '@',  'o',  'u',  't',  'e',  'q'  ; 38
    .byte 0x00, 0x00, '-',  '0',  '8',  '6',  '4',  '2'  ; 40

shift_keytab:
    .byte 0x08, '#',  '+',  ')',  '\'', '%',  '#',  '!'  ; 08
    .byte 0x0d, '*',  'P',  'I',  'Y',  'R',  'W',  '|'  ; 10
    .byte 0x00, ']',  'L',  'J',  'G',  'D',  'A',  0x00 ; 18
    .byte '?',  '<',  0x00, 'N',  'V',  'X',  0x00, 0x1b ; 20
    .byte 0x00, 0x00, '>',  'M',  'B',  'C',  'Z',  ' '  ; 28
    .byte 0x00, '=',  '[',  'K',  'H',  'F',  'S',  0x00 ; 30
    .byte 0x00, 0x00, '@',  'O',  'U',  'T',  'E',  'Q'  ; 38
    .byte 0x00, 0x00, '_',  '0',  '(',  '&',  '$',  '"'  ; 40

zendproc

; --- Screen handling ----------------------------------------------------

; Writes the character in A.

zproc tty_conout
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
    zif_ne
        rts
    zendif

    jsr roll_up

    lda #22
    jsr calculate_line_address

    ldy #0
    tya
    zrepeat
        sta (ptr), y
        iny
    zuntil_eq

    inc ptr+1
    ldy #0x3f
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi

    lda #22
    sta cursory

    rts
zendproc

; Rolls the screen two rows upwards.

zproc roll_up
    ; Cache the top row.

    ldy #19
    zrepeat
        lda TEXT, y
        pha
        dey
    zuntil_mi

    ; Now scroll the entire screen.

    zrepeat
        lda TEXT+20, y
        sta TEXT, y
        iny
        cpy #220
    zuntil_eq

    ; Restore the bottom row.

    ldy #0
    ldx #20
    zrepeat
        pla
        sta TEXT+220, y
        iny
        dex
    zuntil_eq

    ; Increment the scroll compensator.

    ldx scroll_compensation
    inx
    inx
    cpx #24
    zif_eq
        ldx #0
    zendif
    stx scroll_compensation

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

    lda #0
    sta cursorx
    sta cursory
    sta scroll_compensation

    rts
zendproc

; Calculates into ptr the address of bitmap line A.

zproc calculate_line_address
    ; The bottom bit of Y turns into a +8 offset at the end.

    pha

    clc
    adc scroll_compensation ; compensate for scrolling
    cmp #24
    zif_cs
        sec
        sbc #24
    zendif

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

; Calculates into ptr the address of the cursor. Leaves the bottom bit of X in
; the carry flag.

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

    lda cursorx     ; X LSB into carry
    ror a

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
    #include "4x8font.inc"
zendproc

zproc toggle_cursor
    jsr calculate_cursor_address
    ldx #0xf0
    zif_cs
        ldx #0x0f
    zendif

    ldy #7
    zrepeat
        txa
        eor (ptr), y
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

; --- Disk handling ---------------------------------------------------------

; (Most of this is implemented in ieee488.S.)

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
        ror ieee_byte
        jsr wait_for_iec_clock_assert

        dex
    zuntil_eq
    pla
    tax

    ; Acknowledge receipt by asserting data.

    jsr iec_assert_data

    lda ieee_eoi        ; bottom bit set on EOI
    ror a               ; move into C
    lda ieee_byte
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
    jsr bios_CONOUT
    pla
    rts
zendproc

ZEROPAGE

.global ptr
.global ptr1
ptr:             .fill 2
ptr1:            .fill 2
ptr2:            .fill 2

cursorx:         .fill 1
cursory:         .fill 1
scroll_compensation: .fill 1
ieee_byte:       .fill 1
ieee_eoi:        .fill 1
pending_key:     .fill 1

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi, __HIGHTPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi, __HIGHTPA_END__@mos16hi

.bss

current_bank:     .fill 1
keyboard_state:   .fill 8

; vim: sw=4 ts=4 et ft=asm

