; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "wait.inc"
#include "driver.inc"
#include "vic20.inc"
#include "jumptables.inc"

SCREEN_WIDTH = 40
SCREEN_HEIGHT = 24

zproc _start, .start
    ; Goodbye interrupts, we'll never use you again...

    sei

    ; Relocate the BIOS.

    zrepeat
        load1 = .
        lda bios_load_addr
        store1 = .
        sta bios_exec_addr

        inc load1+1
        zif eq
            inc load1+2
        zendif

        inc store1+1
        zif eq
            inc store1+2
            zbreakif eq
        zendif

        lda store1+1
        cmp #<bios_end_addr
        zcontinueif ne
        lda store1+2
        cmp #>bios_end_addr
    zuntil eq

    ; Initialise the VIC.

    ldx #vic_tab_end - vic_tab
    zrepeat
        lda vic_tab-1, x
        sta 0x9000-1, x
        dex
    zuntil eq

    lda #0x08           ; black border, black background, inverted
    sta 0x900f

    jsr initdrivers
    jsr screen_clear

    ldy #0
    sty reverse_flag

    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr bios_CONOUT
        pla
        tay
        dey
    zuntil eq

    ; Disk system.

    jsr io_init
    jsr rw_init
    #if defined GENERICDISK
        jsr genericdisk_init
    #endif

    ; Miscellaneous initialisation.

    ldy #0
    sty pending_key

    ldy #7
    lda #0xff
    zrepeat
        sta keyboard_state, y
        dey
    zuntil mi

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
    txa
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
drvtop: .word drv_SCREEN

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
    zif ne
        lda #0xff
    zendif

    clc
    rts
zendproc

; Blocks until a key is pressed; returns it in A.

zproc tty_conin
    jmp screen_getchar
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
        zuntil eq

        txa
        eor keyboard_state, y
        zif ne
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
                zif mi
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
            zuntil eq

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
    zuntil eq
    rts
rts

; The key with scancode Y has changed state. Whether it's up or down is in
; the top bit of ptr1+1.

zproc change_key_state
    bit ptr1+1
    zif pl
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
    .byte 0x89, ';',  'l',  'j',  'g',  'd',  'a',  0x00 ; 18
    .byte 0x8a, '/',  ',',  'n',  'v',  'x',  0x00, 0x1b ; 20
    .byte 0x00, 0x00, '.',  'm',  'b',  'c',  'z',  ' '  ; 28
    .byte 0x00, '=',  ':',  'k',  'h',  'f',  's',  0x00 ; 30
    .byte 0x00, 0x00, '@',  'o',  'u',  't',  'e',  'q'  ; 38
    .byte 0x00, 0x00, '-',  '0',  '8',  '6',  '4',  '2'  ; 40

shift_keytab:
    .byte 0x08, '#',  '+',  ')',  '\'', '%',  '#',  '!'  ; 08
    .byte 0x0d, '*',  'P',  'I',  'Y',  'R',  'W',  '|'  ; 10
    .byte 0x88, ']',  'L',  'J',  'G',  'D',  'A',  0x00 ; 18
    .byte 0x8b, '?',  '<',  'N',  'V',  'X',  0x00, 0x1b ; 20
    .byte 0x00, 0x00, '>',  'M',  'B',  'C',  'Z',  ' '  ; 28
    .byte 0x00, '=',  '[',  'K',  'H',  'F',  'S',  0x00 ; 30
    .byte 0x00, 0x00, '@',  'O',  'U',  'T',  'E',  'Q'  ; 38
    .byte 0x00, 0x00, '_',  '0',  '(',  '&',  '$',  '"'  ; 40

zendproc

; Writes the character in A.

zproc tty_conout
    cmp #13
    zif eq
        lda #0
        sta cursorx
        rts
    zendif
    cmp #127
    zif eq
        dec cursorx
        zif mi
            lda #SCREEN_WIDTH-1
            sta cursorx

            dec cursory
            zif eq              ; line 0 is omitted
                lda #1
                sta cursory
                jsr screen_scrolldown
            zendif
        zendif
        lda #' '
        jsr screen_putchar
        dec cursorx
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
    inc cursory
    lda cursory
    cmp #SCREEN_HEIGHT
    zif eq
        jsr screen_scrollup
        dec cursory
    zendif
    lda #0
    sta cursorx
    rts
zendproc

; --- Screen handling ----------------------------------------------------

defdriver SCREEN, DRVID_SCREEN, drvstrat_SCREEN, drv_TTY

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
    jmptablo screen_showcursor
    jmptablo screen_scrollup
    jmptablo screen_scrolldown
    jmptablo screen_cleartoeol
    jmptablo screen_setstyle
screen_jmptable_hi:
    jmptabhi screen_version
    jmptabhi screen_getsize
    jmptabhi screen_clear
    jmptabhi screen_setcursor
    jmptabhi screen_getcursor
    jmptabhi screen_putchar
    jmptabhi screen_putstring
    jmptabhi screen_getchar
    jmptabhi screen_showcursor
    jmptabhi screen_scrollup
    jmptabhi screen_scrolldown
    jmptabhi screen_cleartoeol
    jmptabhi screen_setstyle
zendproc

zproc screen_version
    lda #0
    rts
zendproc

zproc screen_getsize
    ; Hardcode screen size for now
    lda #SCREEN_WIDTH-1
    ldx #SCREEN_HEIGHT-1
    dex                     ; one sacrificial line for scrolling
    rts
zendproc

zproc screen_clear
    ; Reset the character mapping on the screen.

    ldx #16
    zrepeat
        txa
        sta TEXT-0x10, x
        lda #1
        sta COLOURRAM-0x10, x
        inx
    zuntil eq

    ; Clear the bitmap itself.

    lda #<FRAMEBUFFER
    sta ptr+0
    lda #>FRAMEBUFFER
    sta ptr+1
    lda #0
    tay
    zrepeat
        sta (ptr), y
        inc ptr+0
        zif eq
            inc ptr+1
        zendif
        ldx ptr+1
        cpx #>(FRAMEBUFFER + 0xf00)
    zuntil eq

    sty cursorx
    lda #1
    sta cursory
    sty scroll_compensation
    sty scroll_nudge
    lda #35
    sta 0x9001

    rts
zendproc

zproc screen_setcursor
    sta cursorx
    inx                 ; sacrificial line
    stx cursory 
    rts
zendproc

zproc screen_getcursor
    lda cursorx 
    ldx cursory
    dex                 ; sacrificial line
    rts
zendproc

zproc screen_putchar
    pha
    jsr calculate_cursor_address
    pla
    jsr draw_glyph

    ldy cursorx
    cpy #SCREEN_WIDTH-1
    zif lt
        iny
    zendif
    sty cursorx
    clc
    rts
zendproc

zproc screen_putstring
    sta 1f+1
    stx 1f+2
   
    zloop
    1:
        lda 0x1234
        zbreakif eq
        jsr screen_putchar
        inc 1b+1
        zif eq
            inc 1b+2
        zendif
    zendloop

    clc
    rts
zendproc

zproc screen_getchar
    jsr toggle_cursor

    lda pending_key
    zif eq
        zrepeat
            jsr scan_keyboard
            lda pending_key
        zuntil ne
    zendif

    ldx #0
    stx pending_key

    pha
    jsr toggle_cursor
    pla

    clc
    rts
zendproc

zproc screen_scrollup
    bit scroll_nudge
    zif mi
        ; We are currently on the first line of the two-line band at the bottom
        ; of the screen. No physical scroll needed, but we do need to adjust the
        ; screen position again.

        lda #35
        sta 0x9001
        inc scroll_nudge
        jsr increment_scroll_compensation

        lda #0
        jsr calculate_line_address
        jsr wipe_line

        clc
        rts
    zendif

    ; On the bottom line of the two-line band at the bottom of the screen. We
    ; need to do a physical scroll.

    jsr roll_up

    ; Adjust the screen position.

    lda #35+4
    sta 0x9001
    dec scroll_nudge

    lda #SCREEN_HEIGHT-1
    jsr calculate_line_address
    jsr wipe_line_pair

    clc
    rts
zendproc

zproc screen_scrolldown
    bit scroll_nudge
    zif mi
        ; On the top line of the two line-band at the top of the screen. A
        ; physical scroll is needed and a screen adjustment.

        lda #35
        sta 0x9001
        inc scroll_nudge
        jsr roll_down

        lda #0
        jsr calculate_line_address
        jsr wipe_line_pair

        clc
        rts
    zendif

    ; On the bottom line the two-line band at the top of the screen. No physical
    ; scroll needed.

    lda #35+4
    sta 0x9001
    dec scroll_nudge
    jsr decrement_scroll_compensation

    lda #0
    jsr calculate_line_address
    jsr wipe_line

    clc
    rts
zendproc

; Wipes the line pair at ptr.

zproc wipe_line_pair
    ldy #0
    tya
    zrepeat
        sta (ptr), y
        iny
    zuntil eq

    inc ptr+1
    ldy #0x3f
    zrepeat
        sta (ptr), y
        dey
    zuntil mi
    rts
zendproc

; Wipes a single line at ptr.

zproc wipe_line
    ldx #20
    zrepeat
        lda #0
        ldy #7
        zrepeat
            sta (ptr), y
            dey
        zuntil mi

        clc
        lda ptr+0
        adc #16
        sta ptr+0
        zif cs
            inc ptr+1
        zendif

        dex
    zuntil eq
    rts
zendproc

; Rolls the screen video memory two rows upwards.

zproc roll_up
    ; Cache the top row.

    ldy #19
    zrepeat
        lda TEXT, y
        pha
        dey
    zuntil mi

    ; Now scroll the entire screen.

    zrepeat
        lda TEXT+20, y
        sta TEXT, y
        iny
        cpy #220
    zuntil eq

    ; Restore the bottom row.

    ldy #0
    ldx #20
    zrepeat
        pla
        sta TEXT+220, y
        iny
        dex
    zuntil eq
    ; fall through
zproc increment_scroll_compensation
    lda scroll_compensation
    clc
    adc #1
    cmp #SCREEN_HEIGHT
    zif cs ; ge
        sbc #SCREEN_HEIGHT
    zendif
    sta scroll_compensation
    rts
zendproc

; Rolls the screen video memory two rows downwards.

zproc roll_down
    ; Cache the bottom row.

    ldy #220+19
    zrepeat
        lda TEXT, y
        pha
        dey
        cpy #219
    zuntil eq

    ; Now scroll the entire screen.

    zrepeat
        lda TEXT, y
        sta TEXT+20, y
        dey
        cpy #0xff
    zuntil eq

    ; Restore the bottom row.

    ldy #0
    zrepeat
        pla
        sta TEXT, y
        iny
        cpy #20
    zuntil eq
zendproc
    ; fall through
zproc decrement_scroll_compensation
    lda scroll_compensation
    sec
    sbc #1
    zif cc 
        adc #SCREEN_HEIGHT
    zendif
    sta scroll_compensation
    rts
zendproc

zproc screen_cleartoeol
    lda cursorx
    pha

    zrepeat
        jsr calculate_cursor_address
        lda #' '
        jsr draw_glyph

        inc cursorx
        lda cursorx
        cmp #SCREEN_WIDTH
    zuntil eq

    pla
    sta cursorx
    rts 
zendproc

zproc screen_setstyle
    ldx #0
    and #STYLE_REVERSE
    zif ne
        ldx #0xff
    zendif
    stx reverse_flag
    rts
zendproc

zproc screen_showcursor
    zif eq
        lda #1
        SKIP2
    zendif
    lda #0
    sta show_cursor
    clc
    rts
zendproc

; Calculates into ptr the address of bitmap line A.

zproc calculate_line_address
    ; The bottom bit of Y turns into a +8 offset at the end.

    clc
    adc scroll_compensation ; compensate for scrolling
    cmp #24
    zif cs ; ge
        sbc #24
    zendif
    
    asl a
    tay
    lda line_table+0, y
    sta ptr+0
    lda line_table+1, y
    sta ptr+1
    rts

line_table:
    i = 0
    .rept SCREEN_HEIGHT+1
        .word FRAMEBUFFER + (i & ~1)*20*8 + (i & 1)*8
        i = i + 1
    .endr
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
    zif cs
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
        eor reverse_flag
        and ptr2+1
        ora (ptr), y
        sta (ptr), y

        dey
    zuntil mi
    rts

font_tab:
    #include "4x8font.inc"
zendproc

zproc toggle_cursor
    jsr calculate_cursor_address
    ldx #0xf0
    zif cs
        ldx #0x0f
    zendif

    ldy #7
    zrepeat
        txa
        eor (ptr), y
        sta (ptr), y
        dey
    zuntil mi
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
scroll_nudge:    .fill 1
pending_key:     .fill 1

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi, __HIGHTPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi, __HIGHTPA_END__@mos16hi

.bss

current_bank:     .fill 1
keyboard_state:   .fill 8
show_cursor:      .fill 1
reverse_flag:     .fill 1 ; 0x00 or 0xff

; vim: sw=4 ts=4 et ft=asm

