; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; 40/80 columns TTY/SCREEN driver for the Apple ][
; Copyright © 2024 Andreas Baumann
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "apple2e.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

drv_zp_begin:

ptr:    .word 0
ptr1:   .word 0
ptr2:   .word 0

drv_zp_end:

; -------------------------------------------------------------------------

zproc main
    jmp init
zendproc

; --- TTY driver ---------------------------------------------------------

drv_TTY:
    .word DRVID_TTY
    .word drvstrat_TTY
    .word 0
    .ascii "TTY"
    .byte 0

zproc drvstrat_TTY
    jmpdispatch tty_jmptable_lo, tty_jmptable_hi

tty_jmptable_lo:
    jmptablo tty_const
    jmptablo tty_conin
    jmptablo tty_conout

tty_jmptable_hi:
    jmptabhi tty_const
    jmptabhi tty_conin
    jmptabhi tty_conout

zendproc

zproc tty_const
    jmp next_tty
zendproc

zproc tty_conin
    jsr cursor_on
    ; Display the cursor.
    ;~ jsr prepare_for_screen_write
    ;~ lda (ptr), y
    ;~ sta cursork
    ;~ lda #0x60           ; flashing block
    ;~ sta (ptr), y

    ; Wait for the key.

    zrepeat
        lda KBD_READ
    zuntil_mi
    sta KBD_STROBERESET
    and #0x7f
    
    jsr cursor_off
    clc

    ; Cursor off again.
    ;~ tax
    ;~ lda cursork
    ;~ sta (ptr), y
    ;~ txa

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
            inc cursorx
        zendif
        jsr prepare_for_screen_write
        lda #0xa0
        sta (ptr), y
        rts
    zendif
    cmp #10
    beq write_nl

    pha
    jsr prepare_for_screen_write
    pla
    eor #0x80
    sta (ptr), y

    inc cursorx
    lda cursorx
    cmp #SCREEN_WIDTH
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
    cmp #SCREEN_HEIGHT
    zif_eq
        dec cursory
        jmp scroll_up
    zendif
    rts
zendproc

zproc scroll_up
    ldx #0              ; current line
    zrepeat
        txa
        jsr calculate_screen_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        inx
        txa
        jsr calculate_screen_address ; ptr is source pointer

        ldy #39
        zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
            sta SCREEN_PAGE2OFF
            lda (ptr), y
            sta (ptr1), y
            sta SCREEN_PAGE2ON
#endif
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #23
    zuntil_eq

    ldy #39
    lda #32|0x80
    zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
        sta SCREEN_PAGE2OFF
        sta (ptr), y
        sta SCREEN_PAGE2ON
#endif
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

; Sets ptr to the current cursor row address; also sets up the page stuff.
; Leaves Y to the screen line offset.

zproc prepare_for_screen_write
    lda cursory
    jsr calculate_screen_address
    lda cursorx
#if TTY_MODE == TTY_MODE_80COLUMNS
    lsr a
#endif
    tay
    lda #0
    rol
    eor #1
    tax
#if TTY_MODE == TTY_MODE_80COLUMNS
    sta SCREEN_PAGE2OFF, x
#endif
    rts
zendproc

; Given a row number in A, set ptr to the address of that
; row of video memory.
;
; Given a row 000abcde, the address is 000001cd eabab000.
; Preserves X and Y.
zproc calculate_screen_address
    pha
    lsr a
    and #0x03
    ora #0x04
    sta ptr+1
    pla

    lsr a           ; 0000abcd, e -> carry
    php
    and #0x0c       ; 0000ab00
    sta ptr+0
    lsr a
    lsr a           ; 000000ab
    ora ptr+0       ; 0000abab
    asl a
    asl a
    asl a
    asl a           ; abab0000
    plp
    ror a           ; eabab000
    sta ptr+0
    rts
zendproc

zproc clear_screen
    lda #24
    sta ptr1
    zrepeat
        lda ptr1
        jsr calculate_screen_address
        ldy #40
        lda #32|0x80
        zrepeat
            dey
#if TTY_MODE == TTY_MODE_80COLUMNS
            sta SCREEN_PAGE2ON
            sta (ptr), y
            sta SCREEN_PAGE2OFF
#endif
            sta (ptr), y
        zuntil_eq

        dec ptr1
    zuntil_mi
    lda #0
    sta cursorx
    sta cursory
    rts
zendproc

zproc cursor_on
    ldx cursorvisible
    cpx #1
    zif_eq
        jsr prepare_for_screen_write
        lda (ptr), y
        sta cursork
        lda #0x60           ; flashing block
        sta (ptr), y
    zendif
    rts
zendproc

zproc cursor_off
    ldx cursorvisible
    cpx #1
    zif_eq
        tax
        lda cursork
        sta (ptr), y
        txa
    zendif
    rts
zendproc

; --- SCREEN driver ---------------------------------------------------------

drv_SCREEN:
    .word DRVID_SCREEN
    .word drvstrat_SCREEN
    .word 0
    .ascii "SCREEN"
    .byte 0

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

zproc fail
    sec
    rts
zendproc

; -------------------------------------------------------------------------

; INITIALIZE DRIVER

zproc init

; BDOS: where is the BIOS
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

; find current TTY driver which we overload (we do not call it),
; so that the TTY driver shares the same variables as the SCREEN
; driver (not so easy to to if the BDOS gets relocated during boot).
; This leads to some code duplications, which is not good.
    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta next_tty+1
    stx next_tty+2

; register new drivers
    lda #<drv_SCREEN
    ldx #>drv_SCREEN
    ldy #BIOS_ADDDRV
    jsr BIOS
    
    lda #<drv_TTY
    ldx #>drv_TTY
    ldy #BIOS_ADDDRV
    jsr BIOS
    
; claim memory for our driver (TODO: compute this)
    ldy #BIOS_GETTPA
    jsr BIOS
    clc
    adc #10
    ;~ lda #>reserve_tpa_end
    ldy #BIOS_SETTPA
    jsr BIOS

    ldy #BIOS_GETZP
    jsr BIOS
    clc
    adc #drv_zp_end-drv_zp_begin
    ldy #BIOS_SETZP
    jsr BIOS
        
; initialize variables
    lda #0
    sta cursorx
    sta cursory
    lda #1
    sta cursorvisible

; as we cannot get the position of the TTY cursor,
; so just clear the screen
    jsr clear_screen
            
; print that we are loaded
    lda #<banner
    ldx #>banner
    ldy #BDOS_WRITE_STRING
    jsr BDOS

; just returning works
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
    jmp clear_screen
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
    sta ptr2
    stx ptr2+1
    jsr cursor_on
    
_inner_loop:
    lda KBD_READ
    zif_mi
        sta KBD_STROBERESET
        and #0x7f
        jsr cursor_off
        clc
        rts       
    zendif
    dec ptr2
    bne _inner_loop
    dec ptr2
    dec ptr2+1
    bne _inner_loop
    jsr cursor_off
    sec
    rts
zendproc

zproc screen_showcursor
    sta cursorvisible
    rts
zendproc

zproc screen_putchar
    ;~ ; TODO: we have to check how the various machines do this,
    ;~ ; especially for lower-case characters
    ;~ ;sec
    ;~ ;sbc stylemask
    jmp tty_conout
zendproc

zproc screen_putstring
    sta ptr1+0
    stx ptr1+1
    zrepeat
        ldy #0
        lda (ptr1), y
        zbreakif_eq
        jsr screen_putchar
        inc ptr1+0
        zif_eq
            inc ptr1+1
        zendif
    zuntil_eq
    rts
zendproc

zproc screen_scrollup
    jmp scroll_up
zendproc

zproc screen_scrolldown
    jmp scroll_down
zendproc

zproc screen_cleartoeol
    lda cursory
    jsr calculate_screen_address ; ptr is source pointer
    ldy cursorx
    lda #32|0x80
    zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
        sta SCREEN_PAGE2OFF
        sta (ptr), y
        sta SCREEN_PAGE2ON
#endif
        sta (ptr), y
        iny
        cpy #40
    zuntil_eq
    rts
zendproc

zproc setcolour
    ; colours, are you kidding? ;-)
    rts
zendproc

zproc screen_setstyle
    ; TODO: see "Using 6502 Assembly Language, appendix A-2"
    ; TODO: see how we handle inverse with lowercase in Apple IIe and clone case
    and #STYLE_REVERSE
    zif_eq
        lda #0x00
        sta cursorstylemask
    zelse
        lda #0x80
        sta cursorstylemask
    zendif
    rts
zendproc

zproc scroll_down
    ldx #22              ; current line
    zrepeat
        txa
        jsr calculate_screen_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        dex
        txa
        jsr calculate_screen_address ; ptr is source pointer

        ldy #39
        zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
            sta SCREEN_PAGE2OFF
            lda (ptr), y
            sta (ptr1), y
            sta SCREEN_PAGE2ON
#endif
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #0
    zuntil_eq

    ldy #39
    lda #32|0x80
    zrepeat
#if TTY_MODE == TTY_MODE_80COLUMNS
        sta SCREEN_PAGE2OFF
        sta (ptr), y
        sta SCREEN_PAGE2ON
#endif
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc BIOS
    jmp $1234
zendproc

zproc next_tty
    jmp $1234
zendproc

.data

banner:
    .ascii "Apple II screen driver loaded."
    .byte 13, 10, 0

.bss

cursorx:            .fill 1
cursory:            .fill 1
cursork:            .fill 1
cursorvisible:      .fill 1
cursorstylemask:    .fill 1

; Increase TPA bottom to here

reserve_tpa_end:
