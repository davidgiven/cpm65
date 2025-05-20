; -------------------------------------------------------------------------
;
; TTY and SCREEN driver for the Ohio Scientific Model 540B Grapphics Card
;
; Copyright © 2024 Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; -------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

drv_zp_begin:

ptr:        .fill 2
ptr1:       .fill 2
ptr2:       .fill 2
ptr3:       .fill 2

curx:       .fill 1
cury:       .fill 1

drv_zp_end:

; Invisible overscan areas:
;
; 64x32 --> 48x26 worst case, hidden: 13L, 3R, 3T, 3B
; 64x16 --> 48x12 worst case, hidden: 13L, 3R, 2T, 2B

#if OSI630

XSCREEN_WIDTH = 64
XSCREEN_HEIGHT = 16

SCREEN_WIDTH   = 48
SCREEN_HEIGHT  = 12
SCREEN_LMARGIN = 13
SCREEN_TMARGIN = 2
SCREEN_BMARGIN = 2

CONTROL = $d800

ENABLE_64 = 0x01
ENABLE_COLOR = 0x02

NORMAL    = $00
INVERSE   = $01
CURSORXOR = (NORMAL ^ INVERSE)

SCREENMEM   = $d000
SECLASTLINE = $d380 - SCREEN_BMARGIN*XSCREEN_WIDTH + SCREEN_LMARGIN
LASTLINE    = $d3c0 - SCREEN_BMARGIN*XSCREEN_WIDTH + SCREEN_LMARGIN
FIRSTLINE   = $d000 + SCREEN_TMARGIN*XSCREEN_WIDTH + SCREEN_LMARGIN
SECLINE     = $d040 + SCREEN_TMARGIN*XSCREEN_WIDTH + SCREEN_LMARGIN

COLORMEM    = $d400
COLORXOR    = ((SCREENMEM ^ COLORMEM) / 256)

#else

XSCREEN_WIDTH = 64
XSCREEN_HEIGHT = 32

SCREEN_WIDTH   = 48
SCREEN_HEIGHT  = 26
SCREEN_LMARGIN = 13
SCREEN_TMARGIN = 3
SCREEN_BMARGIN = 3

CONTROL = $de00

ENABLE_64 = 0x01
ENABLE_COLOR = 0x04

NORMAL    = $0e
INVERSE   = $0f
CURSORXOR = (NORMAL ^ INVERSE)

SCREENMEM   = $d000
SECLASTLINE = $d780 - SCREEN_BMARGIN*XSCREEN_WIDTH + SCREEN_LMARGIN
LASTLINE    = $d7c0 - SCREEN_BMARGIN*XSCREEN_WIDTH + SCREEN_LMARGIN
FIRSTLINE   = $d000 + SCREEN_TMARGIN*XSCREEN_WIDTH + SCREEN_LMARGIN
SECLINE     = $d040 + SCREEN_TMARGIN*XSCREEN_WIDTH + SCREEN_LMARGIN

COLORMEM    = $e000
COLORXOR    = ((SCREENMEM ^ COLORMEM) / 256)

#endif

#define SCREEN_HOMEPOS_OFFSET SCREEN_LMARGIN+(SCREEN_TMARGIN * XSCREEN_WIDTH)

; -------------------------------------------------------------------------

zproc main
    jmp init
zendproc

; -------------------------------------------------------------------------

; SCREEN DESCRIPTION AND DISPATCHER

drv_screen540b:
    .word DRVID_SCREEN
    .word drv_screen540b_strat
    .word 0
#if OSI630
    .ascii "SCREEN630"
#else
    .ascii "SCREEN540B"
#endif
    .byte 0

zproc drv_screen540b_strat
    jmpdispatch drv_screen540b_jump_lo, drv_screen540b_jump_hi

drv_screen540b_jump_lo:
    jmptablo screen540b_version
    jmptablo screen540b_getsize
    jmptablo screen540b_clear
    jmptablo screen540b_setcursor
    jmptablo screen540b_getcursor
    jmptablo screen540b_putchar
    jmptablo screen540b_putstring
    jmptablo screen540b_getchar
    jmptablo screen540b_showcursor
    jmptablo screen540b_scrollup
    jmptablo screen540b_scrolldown
    jmptablo screen540b_cleartoeol
    jmptablo screen540b_setstyle

drv_screen540b_jump_hi:
    jmptabhi screen540b_version
    jmptabhi screen540b_getsize
    jmptabhi screen540b_clear
    jmptabhi screen540b_setcursor
    jmptabhi screen540b_getcursor
    jmptabhi screen540b_putchar
    jmptabhi screen540b_putstring
    jmptabhi screen540b_getchar
    jmptabhi screen540b_showcursor
    jmptabhi screen540b_scrollup
    jmptabhi screen540b_scrolldown
    jmptabhi screen540b_cleartoeol
    jmptabhi screen540b_setstyle
zendproc

; -------------------------------------------------------------------------

; TTY DESCRIPTION AND DISPATCHER

drv_tty540b:
    .word DRVID_TTY
    .word drv_tty540b_strat
    .word 0
#if OSI630
    .ascii "TTY630"
#else
    .ascii "TTY540B"
#endif
    .byte 0

zproc drv_tty540b_strat
    jmpdispatch drv_tty540b_jump_lo, drv_tty540b_jump_hi

drv_tty540b_jump_lo:
    jmptablo tty540b_const
    jmptablo tty540b_conin
    jmptablo tty540b_conout

drv_tty540b_jump_hi:
    jmptabhi tty540b_const
    jmptabhi tty540b_conin
    jmptabhi tty540b_conout

zendproc

; -------------------------------------------------------------------------

; INITIALIZE DRIVERS

zproc init
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

; find current TTY driver which we reuse for keyboard input

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta next_tty+1
    stx next_tty+2

; register new drivers

    lda #<drv_screen540b
    ldx #>drv_screen540b
    ldy #BIOS_ADDDRV
    jsr BIOS

    lda #<drv_tty540b
    ldx #>drv_tty540b
    ldy #BIOS_ADDDRV
    jsr BIOS

; claim memory

    ldy #BIOS_GETTPA
    jsr BIOS
    lda #>(reserve_tpa_end+256)
    ldy #BIOS_SETTPA
    jsr BIOS

    ldy #BIOS_GETZP
    jsr BIOS
    clc
    adc #drv_zp_end-drv_zp_begin
    ldy #BIOS_SETZP
    jsr BIOS

; init display

    jsr screen540b_clear

    lda #(ENABLE_64 | ENABLE_COLOR)
    sta CONTROL

    lda #<banner
    ldx #>banner
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    rts
zendproc

; -------------------------------------------------------------------------

; SCREEN IMPLEMENTATION

zproc screen540b_version
    lda #0
    rts
zendproc

zproc screen540b_getsize
    lda #SCREEN_WIDTH-1
    ldx #SCREEN_HEIGHT-1
    rts
zendproc

zproc screen540b_clear
    ldy #0
clearscrn:
    lda #' '
    sta SCREENMEM+0*256,y
    sta SCREENMEM+1*256,y
    sta SCREENMEM+2*256,y
    sta SCREENMEM+3*256,y
#ifndef OSI630
    sta SCREENMEM+4*256,y
    sta SCREENMEM+5*256,y
    sta SCREENMEM+6*256,y
    sta SCREENMEM+7*256,y
#endif
    lda #NORMAL
    sta COLORMEM+0*256,y
    sta COLORMEM+1*256,y
    sta COLORMEM+2*256,y
    sta COLORMEM+3*256,y
#ifndef OSI630
    sta COLORMEM+4*256,y
    sta COLORMEM+5*256,y
    sta COLORMEM+6*256,y
    sta COLORMEM+7*256,y
#endif
    dey
    bne clearscrn

    sty curx        ; home cursor
    sty cury

    rts
zendproc

zproc screen540b_cleartoeol
    jsr calculate_cursor_address

    ldy curx
    zloop
        lda #' '
        sta (ptr),y
        lda #NORMAL
        sta (ptr1),y
        iny
        cpy #SCREEN_WIDTH
    zuntil eq

    rts
zendproc

; On top of the official specification, we clip (A,X) at the screen edges

zproc screen540b_setcursor
    cmp #SCREEN_WIDTH
    zif cs
        lda #SCREEN_WIDTH-1
    zendif
    sta curx

    txa
    cmp #SCREEN_HEIGHT
    zif cs
        lda #SCREEN_HEIGHT-1
    zendif
    sta cury

    rts
zendproc

zproc screen540b_getcursor
    lda curx
    ldx cury
    rts
zendproc

zproc screen540b_putchar
    pha
    jsr calculate_cursor_address
    pla
    ldy curx
    sta (ptr),y
stylebg=.+1
    lda #NORMAL
    sta (ptr1),y

    cpy #XSCREEN_WIDTH-1
    zif ne
        inc curx
    zendif
    rts
zendproc

zproc screen540b_setstyle
    cmp #STYLE_REVERSE
    zif eq
        lda #INVERSE
    zelse
        lda #NORMAL
    zendif
    sta stylebg
    rts
zendproc

zproc screen540b_putstring
    sta 1f+1
    stx 1f+2

    lda curx
    pha

    ldx #0
    zloop
    1:
        lda $1234,x
        zbreakif eq

        jsr screen540b_putchar

        lda curx
        cmp #SCREEN_WIDTH
        zbreakif eq
        inx
    zendloop

    pla
    sta curx
    rts
zendproc

; We don't have timers on the OSI, just block for now
zproc screen540b_getchar
    jsr tty540b_conin
    clc
    rts
zendproc

zproc screen540b_scrollup
    lda #<FIRSTLINE
    sta ptr
    sta ptr2
    lda #>FIRSTLINE
    sta ptr+1
    eor #COLORXOR
    sta ptr2+1

    lda #<SECLINE
    sta ptr1
    sta ptr3
    lda #>SECLINE
    sta ptr1+1
    eor #COLORXOR
    sta ptr3+1

    ldx #SCREEN_HEIGHT-1
    zloop
        ldy #SCREEN_WIDTH-1
        zloop
            lda (ptr1),y
            sta (ptr),y
            lda (ptr3),y
            sta (ptr2),y
            dey
        zuntil mi

        lda ptr1
        sta ptr
        sta ptr2
        lda ptr1+1
        sta ptr+1
        eor #COLORXOR
        sta ptr2+1

        lda ptr1
        clc
        adc #XSCREEN_WIDTH
        sta ptr1
        zif cs
            inc ptr1+1
            inc ptr3+1
        zendif

        dex
    zuntil eq

common_clear:
    ldy #SCREEN_WIDTH-1
    zloop
        lda #' '
        sta (ptr),y
        lda #NORMAL
        sta (ptr2),y
        dey
    zuntil mi

    rts
zendproc

zproc screen540b_scrolldown
    lda #<SECLASTLINE
    sta ptr1
    sta ptr3
    lda #<LASTLINE
    sta ptr
    sta ptr2
    lda #>LASTLINE
    sta ptr+1
    eor #COLORXOR
    sta ptr2+1
    lda #>SECLASTLINE
    sta ptr1+1
    eor #COLORXOR
    sta ptr3+1

    ldx #SCREEN_HEIGHT-1
    zloop
        ldy #SCREEN_WIDTH-1
        zloop
            lda (ptr1),y
            sta (ptr),y
            lda (ptr3),y
            sta (ptr2),y
            dey
        zuntil mi

        lda ptr1
        sta ptr
        sta ptr2
        lda ptr1+1
        sta ptr+1
        eor #COLORXOR
        sta ptr2+1

        lda ptr1
        sec
        sbc #XSCREEN_WIDTH
        sta ptr1
        sta ptr3
        zif cc
            dec ptr1+1
            dec ptr3+1
        zendif

        dex
    zuntil eq

    jmp common_clear
zendproc

zproc screen540b_showcursor
    cmp #0
    zif eq
        lda #0
    zelse
        lda #CURSORXOR
    zendif
    sta cursor_xor
    rts
zendproc

; -------------------------------------------------------------------------

; TTY IMPLEMENTATION

; Call embedded BIOS tty driver for input

zproc tty540b_const
    jmp next_tty
zendproc

; We use CONST first so we can be sure that the old CONIN will return
; a character immediately without drawing and erasing the old cursor(!)

zproc tty540b_conin
    jsr toggle_cursor

    zloop
        ldy #BIOS_CONST
        jsr next_tty
        cmp #$ff
    zuntil eq

    jsr toggle_cursor
    ldy #BIOS_CONIN
    jmp next_tty
zendproc

zproc tty540b_conout
    cmp #13
    zif eq
        lda #0
        sta curx
        rts
    zendif
    cmp #10
    zif eq
do_lf:
        inc cury
        lda cury
        cmp #SCREEN_HEIGHT
        zif eq
            dec cury
            jmp screen540b_scrollup
        zendif
        rts
    zendif
    cmp #127
    zif eq
        dec curx
        zif mi
            lda #SCREEN_WIDTH-1
            sta curx

            dec cury
            zif mi
                inc cury
                jsr screen540b_scrolldown
            zendif
        zendif
        jsr calculate_cursor_address
        ldy curx
        lda #' '
        sta (ptr),y
        lda #NORMAL
        sta (ptr1),y
        rts
    zendif
    cmp #$20
    zif cc
        rts
    zendif

    ldx curx
    stx ptr3                    ; temporary save location

    and #$7f
    jsr screen540b_putchar

    lda ptr3                    ; retrieve previous x position
    cmp #SCREEN_WIDTH-1
    zif eq
        lda #0
        sta curx
        beq do_lf
    zendif
    rts
zendproc

; -------------------------------------------------------------------------

; Return ptr to line where cursor is in SCREENMEM, use curx as index later
; Return ptr1 to line where cursor is in COLORMEM

zproc calculate_cursor_address
    lda #0
    sta ptr
    lda cury            ; * 64 ---> * 256 / 4
    lsr
    ror ptr
    lsr
    ror ptr
    adc #>SCREENMEM     ; only MSB because SCREENMEM is page aligned
    sta ptr+1

    lda ptr
    clc
    adc #SCREEN_HOMEPOS_OFFSET  ; offset is always < 256
    sta ptr
    sta ptr1
    zif cs
        inc ptr+1
    zendif

    lda ptr+1
    eor #COLORXOR
    sta ptr1+1

    rts
zendproc

zproc toggle_cursor
    jsr calculate_cursor_address

    ldy curx
    lda (ptr1),y
cursor_xor=.+1
    eor #CURSORXOR
    sta (ptr1),y

    rts
zendproc

; Trampolines

zproc BIOS
    jmp $1234
zendproc

zproc next_tty
    jmp $1234
zendproc

; -------------------------------------------------------------------------

; MISCELLANEOUS DATA

    .data

banner:
#if OSI630
    .ascii "tty630/screen630 driver loaded."
#else
    .ascii "tty540b/screen540b driver loaded."
#endif
    .byte 13, 10, 0

; -------------------------------------------------------------------------

; UNINITIALIZED

    .bss

reserve_tpa_end:

; -------------------------------------------------------------------------
