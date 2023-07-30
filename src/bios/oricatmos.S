; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "mos.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"

/* Microdisk interface definitions */

#define MFDC_command_register    0x0310
#define MFDC_status_register     0x0310
#define MFDC_track_register      0x0311
#define MFDC_sector_register     0x0312
#define MFDC_data                0x0313
#define MFDC_flags               0x0314
#define MFDC_drq                 0x0318   

#define MFDC_Flag_DiscSide       0b00010000

#define MCMD_ReadSector          0x80

#define FLOPPY_DELAY            30

/* Screen stuff */

#define SCREEN_WIDTH            40
#define SCREEN_HEIGHT           28

#define SCREEN_TEXT             0xbb80

; --- Zero page -------------------------------------------------------------

ZEROPAGE

.global ptr
.global ptr1
ptr:              .fill 2
ptr1:             .fill 2
cursorx:          .fill 1
cursory:          .fill 1

; --- Bootloader code -------------------------------------------------------

/* The Oric boot process is a bit complicated due to there being two different
 * disk systems we need to support. */

.section "sector1", "ax"

; Jasmin will load this at 0x0400.

    jmp sector1

; Microdisk requires this literal data.

    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x20, 0x20 ; :.....   :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x03 ; :     ...:
    .byte 0x00, 0x00, 0x00, 0x01, 0x00, 0x53, 0x45, 0x44 ; :.....SED:
    .byte 0x4F, 0x52, 0x49, 0x43, 0x20, 0x20, 0x20, 0x20 ; :ORIC    :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20                   ; :    ....:

.section "sector2", "ax"

; This is the Microdisk boot sector. It can load at a variety of addresses, for
; maximum inconvenience. After loading, we relocate to 0x9800, which is known to be
; unused (it's in the highres screen area).

; These literal bytes go before the code itself:

    .byte 0x00, 0x00, 0xFF, 0x00, 0xD0, 0x9F, 0xD0, 0x9F
    .byte 0x02, 0xB9, 0x01, 0x00, 0xFF, 0x00, 0x00, 0xB9
    .byte 0xE4, 0xB9, 0x00, 0x00, 0xE6, 0x12, 0x00

    sei
    lda #0x60
    sta ptr                     ; place an RTS in zero page
    jsr ptr                     ; call it
return:

    tsx
    dex
    clc
    lda 0x0100, x               ; get low byte
    sbc #(return - sector2 - 2) ; adjust to beginning of sector
    sta ptr+0
    lda 0x0101, x               ; get high byte
    sbc #0
    sta ptr+1                   ; ptr points to code

    ; Copy 256 bytes.

    ldy #0
    zloop
        lda (ptr), y
        sta sector2, y
        iny
    zuntil_eq
    jmp sector2_start

sector2_start:
    /* Turn off the EPROM, exposing RAM. */

    lda #0b10000001             ; EPROM off, FDC interrupts off
    sta MFDC_flags

    /* Set up for reading the BIOS. */

    lda #<bios_exec_addr        ; set read pointer
    sta ptr+0
    lda #>bios_exec_addr
    sta ptr+1

    ldx #4                      ; sector to read
    zrepeat
        stx MFDC_sector_register    ; sector to read

        /* Do the read. */

        lda #MCMD_ReadSector
        sta MFDC_command_register

        ldy #FLOPPY_DELAY
        zrepeat
            nop
            nop
            dey
        zuntil_eq

        ldy #0
        zrepeat
            zrepeat
                lda MFDC_drq
            zuntil_pl
            lda MFDC_data
            sta (ptr), y
            iny
        zuntil_eq

        /* Advance to next sector. */

        inx
        inc ptr+1
        cpx #19
    zuntil_eq

    jmp _start

.section "sector3", "ax"

; Sector 3 of a disk must contain this exact data, or the Microdisk ROM will
; refuse to boot it. (It's a minimal Microdisk filesystem.)

    .byte $00,$00,$02,$53,$59,$53,$54,$45,$4d,$44,$4f,$53,$01,$00,$02,$00  ; ...SYSTEMDOS....
    .byte $02,$00,$00,$42,$4f,$4f,$54,$55,$50,$43,$4f,$4d,$00,$00,$00,$00  ; ...BOOTUPCOM....
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; ................

; --- Initialisation code ---------------------------------------------------

/* This is run once on startup and then discarded. */

zproc _start
    jsr screen_clear
    
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

    zloop
    zendloop

banner: ; reversed!
    .byte 13, 10
    .ascii "cirO eht rof 56-M/PC"
banner_end:

zendproc

; --- TTY driver ------------------------------------------------------------

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
    ;IO_ON
    ;jsr scan_keyboard
    ;IO_OFF

    ;lda pending_key
    ;zif_ne
        lda #0xff
    ;zendif

    ;clc
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
        lda #' '
        sta (ptr), y
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
    jmptablo fail
    jmptablo fail
    jmptablo fail
    jmptablo screen_scrollup
    jmptablo screen_scrolldown
    jmptablo screen_cleartoeol
screen_jmptable_hi:
    jmptabhi screen_version
    jmptabhi screen_getsize
    jmptabhi screen_clear
    jmptabhi screen_setcursor
    jmptabhi screen_getcursor
    jmptabhi screen_putchar
    jmptabhi screen_putstring
    jmptabhi fail
    jmptabhi fail
    jmptabhi fail
    jmptabhi screen_scrollup
    jmptabhi screen_scrolldown
    jmptabhi screen_cleartoeol
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

zproc screen_putchar
    pha
    jsr calculate_cursor_address
    pla
    sta (ptr), y

    lda cursorx
    cmp #SCREEN_WIDTH-1
    zif_ne
        inc cursorx
    zendif

    rts
zendproc

zproc screen_putstring
    sta 1f+1
    stx 1f+2

    jsr calculate_cursor_address
    ldx #0
    zloop
    1:
        lda 0xffff, x
        zbreakif_eq

        sta (ptr), y
        iny
        inx
    zendloop

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
    clc
    rol ptr+1           ; shift a zero bit into the bottom of ptr+1
    
    ; x*40 = x*8 + x*32.

    ; We have 28 lines. As 28*8 will fit in a byte, we can do this easily.

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

    ; Add in the video address.

    clc
    lda ptr+0
    adc #<SCREEN_TEXT
    sta ptr+0
    lda ptr+1
    and #0b00000111
    adc #>SCREEN_TEXT
    sta ptr+1

    rts
zendproc

zproc screen_getchar
    sec
    rts
zendproc

zproc screen_scrollup
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
    rts
zendproc

zproc screen_scrolldown
    ldx #SCREEN_HEIGHT-1 ; current line
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
    rts
zendproc

zproc screen_cleartoeol
    jsr calculate_cursor_address

    lda #' '
    zrepeat
        sta (ptr), y
        iny
        cpy #SCREEN_WIDTH
    zuntil_eq
    rts
zendproc

