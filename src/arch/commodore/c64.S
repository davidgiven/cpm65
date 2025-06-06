; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"
#include "c64.inc"

ZEROPAGE

.global ptr
.global ptr1

ptr:        .word 0
ptr1:       .word 0

zproc bootstrap, .bootstrap
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

    ; Wipe the colour RAM.

    ldx #0
    lda #1
    zrepeat
        sta COLOUR_RAM+0x0000, x
        sta COLOUR_RAM+0x0100, x
        sta COLOUR_RAM+0x0200, x
        sta COLOUR_RAM+0x0300, x
        inx
    zuntil eq

    jmp _start
zendproc

zproc _start
    jsr init_system

    ; Load the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy mem_base
    jsr loadfile

    ; Relocate the BDOS.

    lda mem_base
    ldx zp_base
    jsr bios_RELOCATE

    ; Compute the entry address and jump.

    lda mem_base
    pha
    lda #COMHDR_ENTRY-1 ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump

bdos_filename:
    .ascii "BDOS    SYS"
zendproc

.data
.global drvtop
drvtop: .word drv_TTY

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
    rts
zendproc

zproc screen_clear
    lda #SCREEN_HEIGHT-1
    sta CURSOR_Y
    zrepeat
        lda CURSOR_Y
        jsr calculate_line_address
        jsr erase_screen_line
        dec CURSOR_Y
    zuntil mi
    lda #0
    sta CURSOR_X
    sta CURSOR_Y
    rts
zendproc

zproc screen_setcursor
    sta CURSOR_X
    stx CURSOR_Y 
    rts
zendproc

zproc screen_getcursor
    lda CURSOR_X 
    ldx CURSOR_Y
    rts
zendproc

zproc screen_putchar
    pha
    lda CURSOR_Y
    ldy CURSOR_X
    jsr calculate_line_address
    pla
    jsr convert_ascii_to_screencode
    ora reverse_flag
    sta (ptr),y
    cpy #SCREEN_WIDTH-1
    zif cc
        iny
    zendif
    sty CURSOR_X
    clc
    rts
zendproc

zproc screen_putstring
    sta ptr1+0
    stx ptr1+1
   
    lda CURSOR_Y
    jsr calculate_line_address
    
    ; Add cursor x-position to pointer
    lda CURSOR_X
    clc
    adc ptr+0
    sta ptr+0
    zif cs
        inc ptr+1
    zendif

    ldy #0
    zrepeat
        lda (ptr1),y
        zbreakif eq
        jsr convert_ascii_to_screencode
        ldx CURSOR_X
        cpx #SCREEN_WIDTH
        ; Do not linewrap
        zif cc
            ora reverse_flag
            sta (ptr),y
            inc CURSOR_X
        zendif
        iny
    zuntil eq
    
    ; Restore cursor to last character on line if needed
    ldx CURSOR_X
    cpx #SCREEN_WIDTH-1
    zif cs
        dec CURSOR_X
    zendif

    clc
    rts
zendproc

zproc screen_getchar
    jsr toggle_cursor

    zrepeat
        jsr GETIN
    zuntil ne

    pha
    jsr toggle_cursor
    pla
    clc
    rts
zendproc

zproc toggle_cursor
    lda CURSOR_Y
    jsr calculate_line_address
    ldy CURSOR_X
    lda (ptr), y
    eor #0x80
    sta (ptr), y
    rts
zendproc

zproc screen_scrollup
    ldx #0
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
        zuntil mi

        cpx #SCREEN_HEIGHT-1
    zuntil eq
    jmp erase_screen_line
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
        zuntil mi

        cpx #0
    zuntil eq
zendproc
    ; fall through
zproc erase_screen_line
    ldy #SCREEN_WIDTH-1
    lda #' '
    ora reverse_flag
    zrepeat
        sta (ptr), y
        dey
    zuntil mi
    rts
zendproc

zproc screen_cleartoeol
    lda CURSOR_Y
    ldy CURSOR_X
    jsr calculate_line_address
    
    lda #' '
    ora reverse_flag
    zrepeat
        sta (ptr), y
        iny
        cpy #SCREEN_WIDTH
    zuntil eq
    
    rts 
zendproc

zproc screen_setstyle
    and #STYLE_REVERSE
    lsr a
    lda #0
    ror a
    sta reverse_flag
    rts
zendproc

zproc screen_showcursor
    zif eq
        lda #01
        sta SHOW_CURSOR
        clc
        rts
    zendif
    lda #00
    sta SHOW_CURSOR
    clc
    rts
zendproc

defdriver TTY, DRVID_TTY, drvstrat_TTY, drv_SCREEN

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

; Blocks and waits for the next keypress; returns it in A.

zproc tty_conin
    lda pending_key
    zif eq
        jsr screen_getchar
    zendif
    ldx #0
    stx pending_key

    cmp #20         ; DEL
    zif eq
        lda #8
    zendif

    clc
    rts
zendproc

zproc tty_conout
    cmp #13
    zif eq
        lda #0
        sta CURSOR_X
        rts
    zendif
    cmp #127
    zif eq
        dec CURSOR_X
        zif mi
            lda #SCREEN_WIDTH-1
            sta CURSOR_X

            dec CURSOR_Y
            zif mi
                lda #0
                sta CURSOR_Y
                jsr screen_scrolldown
            zendif
        zendif
        jsr calculate_line_address
        ldy CURSOR_X
        lda #' '
        sta (ptr), y
        rts
    zendif
    cmp #10
    beq write_nl

    tax
    lda CURSOR_X
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
    sta CURSOR_X

    inc CURSOR_Y
    lda CURSOR_Y
    cmp #SCREEN_HEIGHT
    zif eq
        dec CURSOR_Y
        jmp screen_scrollup
    zendif
    rts
zendproc

zproc tty_const
    lda pending_key
    zif eq
        jsr GETIN
        sta pending_key
        zif eq
            lda #0
            clc
            rts
        zendif
    zendif

    lda #$ff
    clc
    rts
zendproc

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

; Reads a 256-byte sector whose LBA index is in XA.

zproc read_sector
    tay
    txa
    pha
    tya
    pha

    lda #'R'
    jsr yload_send
    pla
    jsr yload_send
    pla
    jsr yload_send

    jsr yload_recv
    zif mi
        sec
        rts
    zendif

    ldy #0
    zrepeat
        jsr yload_recv
        sta disk_buffer, y
        iny
    zuntil eq

    clc
    rts
zendproc

; Writes a 256-byte sector whose LBA index is in XA.

zproc write_sector
    tay
    txa
    pha
    tya
    pha

    lda #'W'
    jsr yload_send
    pla
    jsr yload_send
    pla
    jsr yload_send

    ldx #0
    zrepeat
        lda disk_buffer, x
        jsr yload_send
        inx
    zuntil eq

    jsr yload_recv
    clc
    zif mi
        sec
    zendif
    rts
zendproc

; Prints an 8-bit hex number in A.
zproc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr h4
    pla
h4:
    and #0x0f ; %00001111
    ora #'0'
    cmp #'9'+1
    zif cs
        adc #6
    zendif
    pha
    jsr CHROUT
    pla
    rts
zendproc

zproc get_status
    lda #8
    jsr TALK
    lda #$6f
    jsr TALKSA

    zrepeat
        jsr ACPTR
        jsr CHROUT
        cmp #13
    zuntil eq

    jsr UNTALK
    rts
zendproc

; Converts an LBA sector number in XA to track/sector in Y, A.

zproc convert_to_ts
    ldy #0
    zloop
        cpx #0
        zif eq
            cmp track_size_table, y
            zif cc
                iny     ; tracks are one-based.
                rts
            zendif
        zendif

        sec
        sbc track_size_table, y
        zif cc
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

; Prints a decimal number in A to the IEC output.

zproc decimal_out
    pha
    lda #' '
    jsr CIOUT
    pla

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #100
    zuntil cc
    adc #100
    jsr digit

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #10
    zuntil cc
    adc #10
    jsr digit
    tax
digit:
    pha
    txa
    ora #'0'
    jsr CIOUT
    pla
    rts
zendproc

zproc string_out
    sta ptr+0
    stx ptr+1

    ldy #0
    zloop
        lda (ptr), y
        zif eq
            rts
        zendif
        jsr CIOUT
        iny
    zendloop
zendproc

; Prints the string at XA with the kernel.

zproc print
    sta ptr+0
    stx ptr+1

    ldy #0
    zloop
        lda (ptr), y
        zbreakif eq

        jsr topetscii
        jsr CHROUT

        iny
    zendloop
    rts
zendproc

zproc init_system
    ; General initialisation.

    lda #0
    sta pending_key
    sta reverse_flag

    jsr yload_init
    jsr initdrivers
    jsr bios1541_init
    rts
zendproc

; Sets ptr to the address of screen line A
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

    asl a               ; = y*32
    rol ptr+1

    ; Add.

    clc
    adc ptr+0
    sta ptr+0
    zif cs
        inc ptr+1
    zendif
 
    ; On in screen address (0x400)
    lda ptr+1 
    and #0b00000011
    ora #>VIDEO
    sta ptr+1

    rts
zendproc

 ; Preserves X and Y.
zproc convert_ascii_to_screencode
    ; Flip case.

    cmp #'A'
    zif cs
        cmp #'Z'+1
        bcc swapcase
    zendif

    cmp #'a'
    zif cs
        cmp #'z'+1
        zif cc
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

.data

zp_base:    .byte __USERZEROPAGE_START__
zp_end:     .byte __USERZEROPAGE_END__
mem_base:   .byte __USERTPA_START__@mos16hi
mem_end:    .byte __USERTPA_END__@mos16hi

NOINIT

pending_key:     .byte 0 ; pending keypress from system
reverse_flag:    .byte 0 ; 0x00 or 0x80

; vim: sw=4 ts=4 et ft=asm
