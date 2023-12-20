; -------------------------------------------------------------------------
;
; 80 columns TTY/SCREEN driver for the Atari 400/800 and XL/XE
;
; Copyright © 2023 Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; -------------------------------------------------------------------------

; 80 columns by 24 rows.
; We create a page aligned Antic Display List to display the following:
;   * 3x8 empty scan lines
;   * 24 rows of:
;       - 1 empty scan line
;       - 6 scanlines of Antic mode 15 (6*40=240 bytes)
;       - 1 empty scan line
;   * end of display list
;
; Each row has its own LMS to a page aligned block of 240 bytes, making
; indexing trivial, and scrollup/down is a matter of pointer adjustment.
; Page alignment wastes 24*16 bytes, but assures us we never cross a 1K
; boundary (display list) or 4K boundary (screen memory), which are Antic
; requirements.
; We save 24*2*40 bytes by utilizing the Antic's ability to display empty
; lines, at the cost of having a slightly smaller cursor.

; The 40 columns BIOS driver uses four consecutive pages for its display
; list and screen memory, starting at where SDLSTL points. We reuse this
; memory for four rows of our new screen.
;
; Antic mode 15 is 320 pixels monochrome.
; Character bounding box is 3x6 pixels, one glyph with padding is 4x6
; pixels.

; -------------------------------------------------------------------------

#include "zif.inc"

; force to include the clang version and not the asm.com version
#include "cpm65.inc"

#include "atari800.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

drv_zp_begin:

ptr:            .fill 2
ptr1:           .fill 2

drv_zp_end:

SCREEN_WIDTH = 80
SCREEN_HEIGHT = 24

; Reuse Atari OS locations, similar to the 40 columns BIOS drivers

cursorx = COLCRS
cursory = ROWCRS

; -------------------------------------------------------------------------

zproc main
    jmp init
zendproc

; -------------------------------------------------------------------------

; SCREEN80 DESCRIPTION AND DISPATCHER

drv_screen80:
    .word DRVID_SCREEN
    .word drv_screen80_strat
    .word 0
    .ascii "SCREEN80"
    .byte 0

zproc drv_screen80_strat
    jmpdispatch drv_screen80_jump_lo, drv_screen80_jump_hi

drv_screen80_jump_lo:
    jmptablo screen80_version
    jmptablo screen80_getsize
    jmptablo screen80_clear
    jmptablo screen80_setcursor
    jmptablo screen80_getcursor
    jmptablo screen80_putchar
    jmptablo screen80_putstring
    jmptablo screen80_getchar
    jmptablo screen80_showcursor
    jmptablo screen80_scrollup
    jmptablo screen80_scrolldown
    jmptablo screen80_cleartoeol
    jmptablo screen80_setstyle

drv_screen80_jump_hi:
    jmptabhi screen80_version
    jmptabhi screen80_getsize
    jmptabhi screen80_clear
    jmptabhi screen80_setcursor
    jmptabhi screen80_getcursor
    jmptabhi screen80_putchar
    jmptabhi screen80_putstring
    jmptabhi screen80_getchar
    jmptabhi screen80_showcursor
    jmptabhi screen80_scrollup
    jmptabhi screen80_scrolldown
    jmptabhi screen80_cleartoeol
    jmptabhi screen80_setstyle
zendproc

zproc fail
    sec
    rts
zendproc

; -------------------------------------------------------------------------

; TTY80 DESCRIPTION AND DISPATCHER

drv_tty80:
    .word DRVID_TTY
    .word drv_tty80_strat
    .word 0
    .ascii "TTY80"
    .byte 0

zproc drv_tty80_strat
    jmpdispatch drv_tty80_jump_lo, drv_tty80_jump_hi

drv_tty80_jump_lo:
    jmptablo tty80_const
    jmptablo tty80_conin
    jmptablo tty80_conout

drv_tty80_jump_hi:
    jmptabhi tty80_const
    jmptabhi tty80_conin
    jmptabhi tty80_conout

zendproc

; -------------------------------------------------------------------------

; INITIALIZE DRIVERS

zproc init
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

; find current drivers which we reuse for keyboard input

    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta next_screen+1
    stx next_screen+2

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta next_tty+1
    stx next_tty+2

; disable BIOS cursor

    ldy #SCREEN_SHOWCURSOR
    lda #0
    jsr next_screen

; register new drivers

    lda #<drv_screen80
    ldx #>drv_screen80
    ldy #BIOS_ADDDRV
    jsr BIOS

    lda #<drv_tty80
    ldx #>drv_tty80
    ldy #BIOS_ADDDRV
    jsr BIOS

; claim memory

    ldy #BIOS_GETTPA
    jsr BIOS
    lda #>reserve_tpa_end
    ldy #BIOS_SETTPA
    jsr BIOS

    ldy #BIOS_GETZP
    jsr BIOS
    clc
    adc #drv_zp_end-drv_zp_begin
    ldy #BIOS_SETZP
    jsr BIOS

; create new display list

    lda #$70                ; 8 empty scan lines
    sta display_list
    sta display_list+1
    sta display_list+2

    lda #24
    sta ptr                 ; counter
    lda #>screen_memory
    sta ptr+1               ; msb of lms address

    clc
    ldy #3

    zrepeat
        lda #0
        sta display_list,y      ; 1 empty scan line
        sta display_list+2,y    ; lms' lsb is always 0
        lda #$4f
        sta display_list+1,y
        lda ptr+1
        sta display_list+3,y
        inc ptr+1

        tya
        adc #4                  ; faster than 4*iny, both four bytes
        tay

        lda #$0f
        ldx #5
        zrepeat
            sta display_list,y
            iny
            dex
        zuntil_eq

        lda #0
        sta display_list,y
        iny
        dec ptr
    zuntil_eq

    sta end_dl+1
    lda #$41                ; end of display list
    sta end_dl
    lda #>display_list
    sta end_dl+2

; fixup last four lms addresses to point to old 40 column screen memory

    ldx SAVMSC+1
    stx last_lms_msb-30
    inx
    stx last_lms_msb-20
    inx
    stx last_lms_msb-10
    inx
    stx last_lms_msb

; switch to new display list

    lda #0
    sta COLOR1              ; hide non-cleared screen memory

    lda #<display_list
    sta SDLSTL
    lda #>display_list
    sta SDLSTL+1

; clear screen, home cursor, cache first curlineptr, print banner

    jsr screen80_clear

    lda #13
    sta COLOR1              ; show again

    lda #<banner
    ldx #>banner
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    rts
zendproc

; -------------------------------------------------------------------------

; SCREEN80 IMPLEMENTATION

zproc screen80_version
    lda #0
    rts
zendproc

zproc screen80_getsize
    lda #SCREEN_WIDTH-1
    ldx #SCREEN_HEIGHT-1
    rts
zendproc

; Cycle through all LMS addresses and write 240 zeroes, home cursor

zproc screen80_clear
    lda #<first_lms_msb
    sta ptr
    lda #>first_lms_msb
    sta ptr+1

    ldx #24

    zrepeat
        ldy #0
        sty ptr1            ; lsb is always 0
        lda (ptr),y         ; retrieve lms msb from display list
        sta ptr1+1

        tya
        zrepeat             ; clear line with zeroes
            sta (ptr1),y
            iny
            cpy #(SCREEN_WIDTH/2)*6
        zuntil_eq

        lda ptr
        clc
        adc #10             ; next lms
        sta ptr             ; msb always stays on the same page

        dex
    zuntil_eq

    stx cursorx
    stx cursory
    rts
zendproc

; On top of the official specification, we clip (A,X) at the screen edges

zproc screen80_setcursor
    cmp #SCREEN_WIDTH
    zif_cs
        lda #SCREEN_WIDTH-1
    zendif
    sta cursorx

    txa
    cmp #SCREEN_HEIGHT
    zif_cs
        lda #SCREEN_HEIGHT-1
    zendif
    sta cursory

    rts
zendproc

zproc screen80_getcursor
    jmp next_screen
zendproc

zproc screen80_putchar
    pha
    jsr find_cursor_line_address
    pla

putchar_for_putstring:
    pha
    and #$7f                ; just to be sure
    cmp #32
    zif_cc
        lda #32
    zendif

    sec
    sbc #32                 ; A is now in [0,95]

; find glyph location

    asl
    pha                     ; save A*2

    sta ptr1                 ; store
    lda #0
    sta ptr1+1

    asl ptr1
    rol ptr1+1               ; A*4 in (ptr1)

    pla
    adc ptr1
    sta ptr1
    zif_cs
        inc ptr1+1
    zendif                  ; A*6 in (ptr1)

    lda ptr1
    clc
    adc #<font
    sta glyph
    lda ptr1+1
    adc #>font
    sta glyph+1

; blit glyph

    lda cursorx
    lsr
    tay
    bcc char_left

char_right:
    lda #$0f
    bne set_mask

char_left:
    lda #$f0

set_mask:
    sta mask1
    ldx style
    zif_ne
        sta style
    zendif
    eor #$ff
    sta mask2

    ldx #5
    clc

    zrepeat
        lda (ptr),y
    mask2=.+1
        and #$ff
    style=.+1
        ora #$00
        sta (ptr),y

    glyph=.+1
        lda $1234,x
    mask1=.+1
        and #$ff
        eor (ptr),y
        sta (ptr),y

        tya
        adc #SCREEN_WIDTH/2
        tay
        dex
    zuntil_mi

    pla
    cmp #127                ; we did backspace space
    zif_eq
        rts
    zendif

    lda cursorx
    cmp #SCREEN_WIDTH-1
    zif_ne
        inc cursorx
    zendif

    rts
zendproc

zproc screen80_setstyle
    sta style
    rts
zendproc

; Putstring is slightly faster because it skips multiple calls to
; find_cursor_line_address. Because it uses putchar, it automatically
; "bumps" against the end of the line.

zproc screen80_putstring
    sta string
    stx string+1

    jsr find_cursor_line_address

    zloop
string=.+1
        lda $1234
        zbreakif_eq
        jsr putchar_for_putstring
        inc string
        zif_cs
            inc string+1
        zendif
    zendloop

    rts
zendproc

zproc screen80_getchar
    jsr toggle_cursor

    ldy #SCREEN_GETCHAR         ; this is faster than saving y
    jsr next_screen

    php
    pha
    jsr toggle_cursor
    pla
    plp
    rts
zendproc

; Rotate LMS addresses in display list up, find bottom line, and clear

zproc screen80_scrollup
    lda #>display_list
    sta ptr+1
    sta ptr1+1

    lda #<first_lms_msb
    sta ptr                     ; ptr is destination
    lda #<first_lms_msb+10
    sta ptr1                    ; ptr1 is source

    ldy #0
    ldx #SCREEN_HEIGHT-1

    lda (ptr),y                 ; save top line for later
    pha
    clc

    zrepeat
        lda (ptr1),y
        sta (ptr),y

        lda ptr1
        sta ptr

        adc #10
        sta ptr1

        dex
    zuntil_eq

same_code_for_scroll_down:
    pla                         ; put top line at the bottom
    sta (ptr),y

    sta ptr+1                   ; set pointer to screen memory of bottom line

    ldy #239
    lda #0
    sta ptr                     ; lsb is always zero

    zrepeat                     ; clear last line
        sta (ptr),y
        dey
        cpy #$ff
    zuntil_eq

    rts
zendproc

; Rotate LMS addresses in display list down, find top line, and clear

zproc screen80_scrolldown
    lda #>display_list
    sta ptr+1
    sta ptr1+1

    lda #<last_lms_msb
    sta ptr                     ; ptr is destination
    lda #<last_lms_msb-10
    sta ptr1                    ; ptr1 is source

    ldy #0
    ldx #SCREEN_HEIGHT-1

    lda (ptr),y
    pha
    sec

    zrepeat
        lda (ptr1),y
        sta (ptr),y

        lda ptr1
        sta ptr

        sbc #10
        sta ptr1

        dex
    zuntil_eq

    jmp same_code_for_scroll_down       ; but top line instead of bottom
zendproc

zproc screen80_cleartoeol
    lda cursorx
    lsr
    pha
    php                         ; carry is set if cursorx is odd
    zif_cs
        lda #127                ; if cursorx is odd, we first clear the
        jsr screen80_putchar    ; right half of the bytes
    zendif
    plp
    pla
    adc #0                      ; round up if carry was set

    cmp #SCREEN_WIDTH/2
    beq skip_clearing_bytes     ; we were at the last position of the line

    tay
    sty ptr1                    ; cursor position +0 or +1 in ptr1

    jsr find_cursor_line_address

    ldy ptr1
    ldx #5
    lda #0

    zrepeat
        zrepeat                 ; clear until end of scan line
            sta (ptr),y
            iny
            cpy #SCREEN_WIDTH/2
        zuntil_eq

        lda ptr
        clc
        adc #SCREEN_WIDTH/2
        sta ptr
        ldy ptr1                    ; restart from cursor position (+0 or 1)
        lda #0
        dex
    zuntil_mi

skip_clearing_bytes:
    rts
zendproc

zproc screen80_showcursor
    cmp #0
    zif_eq
        lda #$60                    ; rts instruction
    zelse
        lda #$20                    ; jsr instruction
    zendif
    sta toggle_cursor
    rts
zendproc

; -------------------------------------------------------------------------

; TTY80 IMPLEMENTATION

; Call embedded BIOS tty driver for input

zproc tty80_const
    jmp next_tty
zendproc

zproc tty80_conin
    jsr toggle_cursor

    ldy #TTY_CONIN              ; this is faster than saving y
    jsr next_tty

    pha
    jsr toggle_cursor
    pla
    rts
zendproc

zproc tty80_conout
    cmp #13                     ; Carriage Return
    zif_eq
        lda #0
        sta cursorx
        rts
    zendif
    cmp #127                    ; Backspace
    zif_eq
        dec cursorx
        zif_mi
            lda #SCREEN_WIDTH-1
            sta cursorx

            dec cursory
            zif_mi
                lda #0
                sta cursory
                jsr screen80_scrolldown
            zendif
        zendif
        jsr find_cursor_line_address
        lda #127
        jsr screen80_putchar
        rts
    zendif
    cmp #10                     ; Newline
    beq write_nl

    tax
    lda cursorx
    pha
    txa
    jsr screen80_putchar

    pla
    cmp #SCREEN_WIDTH-1
    beq write_nl

    rts
zendproc

; -------------------------------------------------------------------------

; HELPER FUNCTIONS

; Wait for vertical blank interrupt

zproc wait_for_vbi
    lda RTCLOK
    zrepeat
        cmp RTCLOK
    zuntil_ne
    rts
zendproc

; Do newline

zproc write_nl
    lda #0
    sta cursorx

    inc cursory
    lda cursory
    cmp #SCREEN_HEIGHT
    zif_eq
        dec cursory
        jmp screen80_scrollup
    zendif
    rts
zendproc

; Toggle cursor with eor mask
; It is important that the first instruction is jsr. If it's changed,
; showcursor has to be changed, too.

zproc toggle_cursor
    jsr find_cursor_line_address
    lda cursorx
    lsr
    tay             ; index in Y
    bcc mask_left

mask_right:
    lda #$0f
    sta mask
    bne do_eor

mask_left:
    lda #$f0
    sta mask

do_eor:
    clc
    ldx #5

    zrepeat
        lda (ptr),y
    mask=.+1
        eor #$ff
        sta (ptr),y
        tya
        adc #SCREEN_WIDTH/2
        tay
        dex
    zuntil_mi

    rts
zendproc

; Sets (ptr) to the line of the cursor
; cursorsx & 1 determines left (0b11110000) or right (0b00001111) mask

zproc find_cursor_line_address
    lda #>first_lms_msb
    sta ptr+1
    lda cursory
    asl
    sta ptr             ; y*2 in ptr
    asl
    asl                 ; y*8 in A
    clc
    adc ptr             ; y*10 in A
    adc #<first_lms_msb
    sta ptr             ; points msb of screen memory of cursory

    ldy #0
    lda (ptr),y         ; retrieve MSB
    sta ptr+1
    sty ptr             ; LSB is always zero
    rts
zendproc

; Trampolines

zproc BIOS
    jmp $1234
zendproc

zproc next_tty
    jmp $1234
zendproc

zproc next_screen
    jmp $1234
zendproc

; -------------------------------------------------------------------------

; MISCELLANEOUS DATA

    .data

banner:
    .ascii "tty80/screen80 driver loaded."
    .byte 13, 10, 0

; Include binary font data here. 96 glyphs * 6 bytes (both left and right
; position) equals 576 bytes

font:
    #include "third_party/fonts/atari/ivo3x6.inc"

; -------------------------------------------------------------------------

; UNINITIALIZED

    .bss

; This "trick" saves a lot of calculations. Assembler/linker calculates
; the positions and offsets.

    .align 0x0100   ; always true

; 3x$70             ; 3x8 empty scan lines
; 24x {
;   $00             ; empty scan line
;   $4f, lsb, msb   ; mode 15 + LMS, lsb+msb of screen memory
;   5x$0f           ; 5x mode 15
;   $00             ; empty scan line
; }                 ; wait for vb and jump to start of DL
; $41, lsb, msb
;
; total = 3 + 24*10 + 3 = 246, fits in one page, so it never crosses an
; important boundary.

; point to msb, not the LMS instruction.

first_lms_msb=.+6
last_lms_msb=.+236

; where the full end-of-dl instruction is

end_dl=.+243

display_list:
    .fill 256

; 20 rows here, the other 4 are at the old location of the 40 columns
; display list and screen memory

screen_memory:
    .fill 256*20

; Increase TPA bottom to here

reserve_tpa_end:

; -------------------------------------------------------------------------

