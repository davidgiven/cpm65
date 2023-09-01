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
; Character bounding box is 4x6 pixels, glyphs are 3x6 pixels.

; -------------------------------------------------------------------------

#include "zif.inc"

; force to include the clang version and not the asm.com version
#include "include/cpm65.inc"

#include "atari800.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

drv_zp_begin:

ptr:            .fill 2
ptr1:           .fill 2
curlineptr:     .fill 2

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
    jmptablo fail                   ; show cursor
    jmptablo screen80_scrollup
    jmptablo screen80_scrolldown
    jmptablo screen80_cleartoeol
    jmptablo fail                   ; set style

drv_screen80_jump_hi:
    jmptabhi screen80_version
    jmptabhi screen80_getsize
    jmptabhi screen80_clear
    jmptabhi screen80_setcursor
    jmptabhi screen80_getcursor
    jmptabhi screen80_putchar
    jmptabhi screen80_putstring
    jmptabhi screen80_getchar
    jmptabhi fail
    jmptabhi screen80_scrollup
    jmptabhi screen80_scrolldown
    jmptabhi screen80_cleartoeol
    jmptabhi fail
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
    sta next_screen
    stx next_screen+1

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta next_tty
    stx next_tty+1

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

;    lda #2
;    sta COLOR2              ; debug: show where the empty line are

; create new display list

    lda #$70                ; 8 empty scan lines
    sta display_list
    sta display_list+1
    sta display_list+2

    lda #24
    sta ptr                 ; counter
    lda #>screen_memory
    sta ptr+1               ; msb of lms address

    clc                     ; necessary?
    ldy #3
loop24:
    lda #0
    sta display_list,y      ; 1 empty scan line
    sta display_list+2,y    ; lms' lsb is always 0
    lda #$4f
    sta display_list+1,y
    lda ptr+1
    sta display_list+3,y
    inc ptr+1

    tya
    adc #4                  ; faster than 4*iny
    tay

    lda #$0f
    ldx #5
five_lines:
    sta display_list,y
    iny
    dex
    bne five_lines

    lda #0
    sta display_list,y
    iny
    dec ptr
    bne loop24

    sta end_dl+1
    lda #$41
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

; switch display list

    lda #<display_list
    sta SDLSTL
    lda #>display_list
    sta SDLSTL+1

; clear screen, home cursor, cache first curlineptr, print banner

    jsr screen80_clear

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

clear_screen:
    ldy #0
    sty ptr1            ; lsb is always 0
    lda (ptr),y         ; retrieve lms msb from display list
    sta ptr1+1

    tya
clear_line:
    sta (ptr1),y
    iny
    cpy #240
    bne clear_line

    lda ptr
    clc
    adc #10             ; next lms
    sta ptr             ; msb always stays on the same page

    dex
    bne clear_screen

    stx cursorx
    stx cursory
    jmp show_cursor
zendproc

zproc screen80_setcursor
    pha
    jsr hide_cursor
    pla
    sta cursorx
    stx cursory
    jmp show_cursor
zendproc

zproc screen80_getcursor
    lda cursorx
    ldx cursory
    rts
zendproc

zproc screen80_putchar
    sec
    rts
zendproc

zproc screen80_putstring
    sec
    rts
zendproc

zproc screen80_getchar
    jmp (next_screen)           ; keyboard input through BIOS driver
zendproc

; Rotate LMS addresses in display list up, find bottom line, and clear

zproc screen80_scrollup
    sec
    rts
zendproc

; Rotate LMS addresses in display list down, find top line, and clear

zproc screen80_scrolldown
    sec
    rts
zendproc

zproc screen80_cleartoeol
    sec
    rts
zendproc

; -------------------------------------------------------------------------

; TTY80 IMPLEMENTATION

; Call embedded BIOS tty driver for input

zproc tty80_const
    jmp (next_tty)
zendproc

zproc tty80_conin
    jmp (next_tty)
zendproc

zproc tty80_conout
;    rts
    jmp (next_tty)
zendproc

; -------------------------------------------------------------------------

; HELPER FUNCTIONS

; Wait for vertical blank interrupt

zproc wait_for_vbi
    lda RTCLOK
wait:
    cmp RTCLOK
    beq wait
    rts
zendproc

; Properly coded, hide and show can be merged.
; Show cursor needs to refind the new curlineptr, hide cursor does not.
; Toggle cursor with eor mask

; Show cursor

zproc show_cursor
    nop
zendproc            ; fallthrough

; Hide cursor

zproc hide_cursor
    rts
zendproc

; Sets (ptr),y to the location of the cursor
; cache in curlineptr
; cursorsx & 1 determines left (0b11110000) or right (0b00001111) mask
; return cursorx & 1 in carry

zproc find_cursor_address
    rts
zendproc

; BIOS trampoline

zproc BIOS
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
    #include "../third_party/fonts/atari/ivo3x6.inc"

; put these here instead of in .bss saves almost a page because .bss is
; always page aligned and soon we re-align for the display list and
; screen memory

next_tty:
    .fill 2
next_screen:
    .fill 2

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

; helper offsets, point to lsb, not the LMS instruction.

first_lms_msb=.+6
last_lms_msb=.+236
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

