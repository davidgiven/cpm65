; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"

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

MEMCTRL = 0xfff0

VIDEO   = 0x8000
#if defined PET4032
SCREEN_WIDTH = 40
#elif defined PET8032 || defined PET8096
SCREEN_WIDTH = 80
#endif
SCREEN_HEIGHT = 25

#if defined PET8096
.macro IO_ON
    lda #0b11100000
    sta MEMCTRL
.endm

.macro IO_OFF
    lda #0b10000000
    sta MEMCTRL
.endm
#else
.macro IO_ON
.endm

.macro IO_OFF
.endm
#endif

ZEROPAGE

.global ptr
.global ptr1
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

zproc _start, .init
    ; Copy the BIOS to its final location at 0x200. This overwrites the current
    ; memory image, so care needs to be taken. This routine runs at 0x7000 so
    ; it is unaffected.

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

    jsr screen_clear

    IO_ON
    lda #14
    sta VIA_PCR             ; lowercase

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

    ; Miscellaneous initialisation.

    lda #0
    sta shift_pressed
    sta pending_key
    sta buffer_dirty
    jsr initdrivers

    jsr ieee_init

    ldx #10
    lda #0xff
    zrepeat
        sta keyboard_state, x
        dex
    zuntil_mi

    ; Set up sector IO.

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
    ldy #>__TPA_START__
    jsr loadfile

    ; Relocate the BDOS.

    lda #>__TPA_START__
    ldx #__ZEROPAGE_START__
    jsr bios_RELOCATE

    ; Go!

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA_START__ + COMHDR_ENTRY

bdos_filename:
    .ascii "BDOS    SYS"
bdos_filename_end:

allocate_cmd: ; reversed!
    .ascii "2#"
allocate_cmd_end:

banner: ; reversed!
    .byte 13, 10
#if defined PET4032
    .ascii "2304"
#elif defined PET8032
    .ascii "2308"
#elif defined PET8096
    .ascii "6908"
#endif
    .ascii " TEP erodommoC eht rof 56-M/PC"
banner_end:
zendproc

; --- BIOS entrypoints ------------------------------------------------------

zproc bios_GETTPA
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc bios_SETTPA
    sta mem_base
    stx mem_end
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
    rts
zendproc

; --- SCREEN driver ---------------------------------------------------------

defdriver SCREEN, DRVID_SCREEN, drvstrat_SCREEN, 0

; SCREEN driver strategy routine.
; Y=SCREEN opcode.
zproc drvstrat_SCREEN
    jmpdispatch screen_jmptable_lo, screen_jmptable_hi

screen_jmptable_lo:
    jmptablo screen_version
    jmptablo screen_getsize
    jmptablo screen_clear
    jmptablo screen_setcursor
    jmptablo screen_getcursor
    jmptablo screen_putchar
    jmptablo screen_putstring
    jmptablo screen_getchar
    jmptablo fail
    jmptablo screen_scrollup
    jmptablo screen_scrolldown
    jmptablo screen_cleartoeol
    jmptablo fail
screen_jmptable_hi:
    jmptabhi screen_version
    jmptabhi screen_getsize
    jmptabhi screen_clear
    jmptabhi screen_setcursor
    jmptabhi screen_getcursor
    jmptabhi screen_putchar
    jmptabhi screen_putstring
    jmptabhi screen_getchar
    jmptabhi fail
    jmptabhi screen_scrollup
    jmptabhi screen_scrolldown
    jmptabhi screen_cleartoeol
    jmptabhi fail
zendproc

zproc fail
    sec
    rts
zendproc

zproc screen_version
    lda #0
    rts
zendproc

zproc screen_getsize
    lda #SCREEN_WIDTH-1
    ldx #SCREEN_HEIGHT-1
    rts
zendproc

zproc screen_clear
    IO_ON
    lda #0
    zrepeat
        pha
        jsr calculate_line_address

        ldy #SCREEN_WIDTH-1
        lda #' '
        zrepeat
            sta (ptr), y
            dey
        zuntil_mi

        pla
        clc
        adc #1
        cmp #SCREEN_HEIGHT
    zuntil_eq
    IO_OFF

    ; SCREEN doesn't specify where the cursor ends up, but this code is used by
    ; TTY and homing the cursor here simplifies things.

    lda #0
    sta cursorx
    sta cursory
    rts
zendproc

zproc screen_setcursor
    sta cursorx
    stx cursory
    rts
zendproc

zproc screen_getcursor
    lda cursorx
    ldx cursory
    rts
zendproc

zproc screen_getchar
    IO_ON

    jsr calculate_cursor_address
    lda (ptr), y
    eor #0x80
    sta (ptr), y

    zrepeat
        jsr scan_keyboard
        lda pending_key
    zuntil_ne

    ldx #0
    stx pending_key

    pha
    jsr calculate_cursor_address
    lda (ptr), y
    eor #0x80
    sta (ptr), y

    IO_OFF
    pla

    clc
    rts
zendproc

zproc screen_putchar
    pha
    IO_ON
    jsr calculate_cursor_address
    pla
    jsr convert_ascii_to_screencode
    sta (ptr), y

    lda cursorx
    cmp #SCREEN_WIDTH-1
    zif_ne
        inc cursorx
    zendif

    IO_OFF
    rts
zendproc

zproc screen_putstring
    sta 1f+1
    stx 1f+2

    IO_ON
    jsr calculate_cursor_address
    ldx #0
    zloop
    1:
        lda 0xffff, x
        zbreakif_eq

        jsr convert_ascii_to_screencode
        sta (ptr), y
        iny
        inx
    zendloop

    IO_OFF
    rts
zendproc

zproc screen_scrollup
    ldx #0              ; current line
    IO_ON
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

        ldy #SCREEN_WIDTH-1
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #SCREEN_HEIGHT-1
    zuntil_eq

    ldy #SCREEN_WIDTH-1
    lda #' '
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    IO_OFF
    rts
zendproc

zproc screen_scrolldown
    ldx #SCREEN_HEIGHT-1 ; current line
    IO_ON
    zrepeat
        txa
        jsr calculate_line_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        dex
        txa
        jsr calculate_line_address ; ptr is source pointer

        ldy #SCREEN_WIDTH-1
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #0
    zuntil_eq

    ldy #SCREEN_WIDTH-1
    lda #' '
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    IO_OFF
    rts
zendproc

zproc screen_cleartoeol
    jsr calculate_cursor_address

    IO_ON
    lda #' '
    zrepeat
        sta (ptr), y
        iny
        cpy #SCREEN_WIDTH
    zuntil_eq
    IO_OFF
    rts
zendproc

; --- Keyboard handling -----------------------------------------------------

.data
.global drvtop
; This must point at the _last_ driver.
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, drv_SCREEN

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    jmpdispatch jmptable_lo, jmptable_hi

jmptable_lo:
    jmptablo tty_const
    jmptablo tty_conin
    jmptablo tty_conout
jmptable_hi:
    jmptabhi tty_const
    jmptabhi tty_conin
    jmptabhi tty_conout
zendproc

; Returns 0xff if no key is pending, 0 if one is.

zproc tty_const
    IO_ON
    jsr scan_keyboard
    IO_OFF

    lda pending_key
    zif_ne
        lda #0xff
    zendif

    clc
    rts
zendproc

; Blocks until a key is pressed; returns it in A.

zproc tty_conin
    zrepeat
        lda #0xff
        ldx #0xff
        jsr screen_getchar
    zuntil_cc

    rts
zendproc

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
            lda #SCREEN_WIDTH-1
            sta cursorx

            dec cursory
            zif_mi
                lda #0
                sta cursory
                jsr screen_scrolldown
            zendif
        zendif
        jsr calculate_cursor_address
        IO_ON
        lda #' '
        sta (ptr), y
        IO_OFF
        rts
    zendif
    cmp #10
    beq write_nl

    tax
    lda cursorx
    pha
    txa
    jsr screen_putchar

    pla
    cmp #SCREEN_WIDTH-1
    beq write_nl
    rts
zendproc

zproc write_nl
    lda #0
    sta cursorx

    inc cursory
    lda cursory
    cmp #SCREEN_HEIGHT
    zif_eq
        dec cursory
        jmp screen_scrollup
    zendif
    rts
zendproc

; Does a single keyboard scan, processing any pressed keys. Last pressed key
; wins.
;
; Must be called with IO_ON.

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
#if defined PET4032
    cpy #0x47               ; left shift
    beq shift_change
    cpy #0x42               ; right shift
    beq shift_change
#elif defined PET8032 || defined PET8096
    cpy #0x37               ; left shift
    beq shift_change
    cpy #0x31               ; right shift
    beq shift_change
#endif

    bit ptr1+1
    zif_pl
        lda keyboard_decode_tab, y
        bit shift_pressed
        zif_pl
            lda keyboard_decode_tab_shifted, y
        zendif
        sta pending_key
    zendif
    rts

    ; Shift gets special treatment because we care about ups as well as downs.

shift_change:
#if defined PET4032
    lda keyboard_state + 8
    rol a
    rol a
    rol a
    rol a                   ; left shift state in bit 0
    and keyboard_state + 8  ; right shift state in bit 0
    ror a
    ror a
#elif defined PET8032 || defined PET8096
    lda keyboard_state + 6
    rol a
    rol a
    rol a                   ; right shift state in bit 0
    and keyboard_state + 6  ; left shift state in bit 0
    ror a
    ror a
#endif
    sta shift_pressed       ; new state in top bit
    rts

keyboard_decode_tab:
#if defined PET4032
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
#elif defined PET8032 || defined PET8096
    .byte '.',  0x00, 0x00, '8',  '-',  '8',  '5',  '2'  ; 0x00
    .byte '9',  0x00, '^',  '7',  '0',  '7',  '4',  '1'  ; 0x08
    .byte '5',  ';',  'k',  ']',  'h',  'f',  's',  0x1b ; 0x10
    .byte '6',  '@',  'l',  0x0d, 'j',  'g',  'd',  'a'  ; 0x18
    .byte 0x7f, 'p',  'i',  '\\', 'y',  'r',  'w',  0x09 ; 0x20
    .byte '4',  '[',  'o',  0x00, 'u',  't',  'e',  'q'  ; 0x28
    .byte '3',  0x00, 0x00, '.',  '.',  'b',  'c',  0x00 ; 0x30
    .byte '2',  0x00, 0x00, '0',  ',',  'n',  'v',  'z'  ; 0x38
    .byte '1',  '/',  0x00, 0x00, 'm',  ' ',  'x',  0x00 ; 0x40
    .byte 0x00, 0x00, ':',  0x1b, '9',  '6',  '3',  0x00 ; 0x48
#endif

keyboard_decode_tab_shifted:
#if defined PET4032
    .byte 0x00, 0x00, '_',  '(',  '&',  '%',  '#',  '!'  ; 0x00
    .byte 0x7f, 0x00, 0x00, ')',  '\\', '\'', '$',  '"'  ; 0x08
    .byte '9',  '7',  '^',  'O',  'U',  'T',  'E',  'Q'  ; 0x10
    .byte '/',  '8',  0x00, 'P',  'I',  'Y',  'R',  'W'  ; 0x18
    .byte '6',  '4',  0x00, 'L',  'J',  'G',  'D',  'A'  ; 0x20
    .byte '*',  '5',  0x00, ':',  'K',  'H',  'F',  'S'  ; 0x28
    .byte '3',  '1',  0x0d, ';',  'M',  'B',  'C',  'Z'  ; 0x30
    .byte '+',  '2',  0x00, '?',  '.',  'N',  'V',  'X'  ; 0x38
    .byte '-',  '0',  0x00, '>',  0x00, ']',  '@',  0x00 ; 0x40
    .byte '=',  '.',  0x00, 0x1b, '<',  ' ',  '[',  0x00 ; 0x48
#elif defined PET8032 || defined PET8096
    .byte '.',  0x00, 0x00, '8',  '=',  '(',  '%',  '"'  ; 0x00
    .byte '9',  0x00, '^',  '7',  '0',  '\'', '$',  '!'  ; 0x08
    .byte '5',  '+',  'K',  ']',  'H',  'F',  'S',  0x1b ; 0x10
    .byte '6',  '@',  'L',  0x0D, 'J',  'G',  'D',  'A'  ; 0x18
    .byte 0x7f, 'P',  'I',  '\\', 'Y',  'R',  'W',  0x09 ; 0x20
    .byte '4',  '[',  'O',  0x00, 'U',  'T',  'E',  'Q'  ; 0x28
    .byte '3',  0x00, 0x00, '.',  '>',  'B',  'C',  0x00 ; 0x30
    .byte '2',  0x00, 0x00, '0',  '<',  'N',  'V',  'Z'  ; 0x38
    .byte '1',  '?',  0x00, 0x00, 'M',  ' ',  'X',  0x00 ; 0x40
    .byte 0x00, 0x00, '*',  0x00, ')',  '&',  '#',  0x00 ; 0x48
#endif
zendproc

; Preserves X and Y.
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

    cmp #0x20       ; if A<32 then...
    bcc ddRev

    cmp #0x60       ; if A<96 then...
    bcc dd1

    cmp #0x80       ; if A<128 then...
    bcc dd2

    cmp #0xa0       ; if A<160 then...
    bcc dd3

    cmp #0xc0       ; if A<192 then...
    bcc dd4

    cmp #0xff       ; if A<255 then...
    bcc ddRev

    lda #0x7e       ; A=255, then A=126
    bne ddEnd

dd2:
    and #0x5f       ; if A=96..127 then strip bits 5 and 7
    bne ddEnd
dd3:
    ora #0x40       ; if A=128..159, then set bit 6
    bne ddEnd
dd4:
    eor #0xc0       ; if A=160..191 then flip bits 6 and 7
    bne ddEnd
dd1:
    and #0x3f       ; if A=32..95 then strip bits 6 and 7
    bpl ddEnd       ; <- you could also do .byte 0x0c here
ddRev:
    eor #0x80       ; flip bit 7 (reverse on when off and vice versa)
ddEnd:

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

#if defined PET8032 || defined PET8096
    ; The 8032 and 8096 have 80-column screens, so to get x80 from x40 we do
    ; another x2.

    asl ptr+0
    rol ptr+1
#endif

    ; Or in the video address.

    lda ptr+1
    and #0b00000111
    ora #>VIDEO
    sta ptr+1

    rts
zendproc

; --- Disk handling ---------------------------------------------------------

; (Most of this is implemented in ieee488.S.)

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
    IO_ON
    set0 VIA_PB, VIA_PB_ATN_OUT
    IO_OFF
    rts
zendproc

zproc ieee_mode_talk
    IO_ON
    set1 VIA_PB, VIA_PB_ATN_OUT
    IO_OFF
    rts
zendproc

; Switch from ATN mode to LISTEN mode.

zproc ieee_mode_listen
    IO_ON
    set1 VIA_PB, VIA_PB_ATN_OUT
    IO_OFF
    rts
zendproc

zproc ieee_puteoib
    pha
    IO_ON
    lda #0x34               ; assert EOI
    sta PIA1_CA
    IO_OFF
    pla

    bne ieee_putb           ; always taken
zendproc

zproc ieee_putb
    ; Deassert our own NRFD and NDAC and wait for NRFD=0 (i.e. ready for data)

    pha
    IO_ON
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
    IO_OFF

    rts
zendproc

; Receives a byte into A. Sets C on EOI.

zproc ieee_getb
    IO_ON

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

    IO_OFF
    pla
    rts
zendproc

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi

.bss

keyboard_state:   .fill 10
shift_pressed:    .fill 1

; vim: sw=4 ts=4 et ft=asm
