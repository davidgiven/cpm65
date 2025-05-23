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
dma:        .word 0    ; current DMA

    .text

    .word $0801
    .word 1f, 1
    .byte $9e
    .asciz "2061"
1:
    .word 0
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
   jsr CLEAR_SCREEN
   rts
zendproc

zproc screen_setcursor
    sta CURSOR_X
    stx CURSOR_Y 
    jsr MOVE_CURSOR
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
    sta (ptr),y
    cpy #SCREEN_WIDTH-1
    zif cc
        iny
    zendif
    sty CURSOR_X
    jsr MOVE_CURSOR   
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
    jsr MOVE_CURSOR

    clc
    rts
zendproc

zproc screen_getchar
    ; Ignore timeout for now, just do a non-blocking read
    jsr GETIN
    zif eq
        sec
        rts
    zendif
    clc
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

    ldy #SCREEN_WIDTH-1
    lda #' '
    zrepeat
        sta (ptr), y
        dey
    zuntil mi
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
        zuntil mi

        cpx #0
    zuntil eq

    ldy #SCREEN_WIDTH-1
    lda #' '
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
    zrepeat
        sta (ptr), y
        iny
        cpy #SCREEN_WIDTH
    zuntil eq
    
    rts 
zendproc

zproc screen_setstyle
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
        zrepeat
            jsr GETIN
            tax
        zuntil ne
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
    jsr topetscii
    jsr CHROUT
    clc
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

; Sets the current DMA address.

zproc bios_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc bios_SELDSK
    cmp #0
    zif ne
        sec                 ; invalid drive
        rts
    zendif

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

zproc bios_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil mi
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

zproc bios_READ
    jsr change_sectors

    lda sector_num+0
    ror a               ; bottom bit -> C
    lda #0
    ror a               ; C -> top bit, producing $00 or $80
    tax

    ldy #0
    zrepeat
        lda disk_buffer, x
        sta (dma), y
        iny
        inx
        cpy #$80
    zuntil eq

    clc
    rts
zendproc

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc bios_WRITE
    pha
    jsr change_sectors

    lda sector_num+0
    ror a               ; bottom bit -> C
    lda #0
    ror a               ; C -> top bit, producing $00 or $80
    tax

    ldy #0
    zrepeat
        lda (dma), y
        sta disk_buffer, x
        iny
        inx
        cpy #$80
    zuntil eq

    lda #$80
    sta buffer_dirty

    pla
    zif ne
        jsr flush_buffered_sector
    zendif

    clc
    rts
zendproc

zproc change_sectors
    ; If the buffered sector is the one we want, just return.

    lda sector_num+0
    and #$fe
    cmp buffered_sector+0
    zif eq
        lda sector_num+1
        cmp buffered_sector+1
        zif eq
            lda sector_num+2
            cmp buffered_sector+2
            zif eq
                rts
            zendif
        zendif
    zendif

    ; We need to change sectors. Flush the current one?

    jsr flush_buffered_sector

    ; Now read the new one.

    lda sector_num+0
    and #$fe
    sta buffered_sector+0
    lda sector_num+1
    sta buffered_sector+1
    lda sector_num+2
    sta buffered_sector+2

    jsr buffered_sector_to_lba
    jmp read_sector
zendproc

; Compute the current LBA sector number in XA for the buffered sector.

zproc buffered_sector_to_lba
    lda buffered_sector+1
    lsr a
    tax
    lda buffered_sector+0
    ror
    rts
zendproc

; Flush the current buffer to disk, if necessary.

zproc flush_buffered_sector
    lda buffer_dirty
    zif mi
        jsr buffered_sector_to_lba
        jsr write_sector

        lda #0
        sta buffer_dirty
    zendif
    rts
zendproc

; Reads a 256-byte sector whose LBA index is in XA.

zproc read_sector
    jsr convert_to_ts
    pha
    tya
    pha

    lda #8
    jsr LISTEN
    lda #$6f
    jsr SECOND

    lda #'U'
    jsr CIOUT
    lda #'1'
    jsr CIOUT
    lda #2
    jsr decimal_out
    lda #0
    jsr decimal_out
    pla                 ; get sector
    jsr decimal_out
    pla                 ; get track
    jsr decimal_out

    jsr UNLSN

    ;jsr get_status

    lda #8
    jsr TALK
    lda #$62
    jsr TALKSA

    ldy #0
    zrepeat
        jsr ACPTR
        sta disk_buffer, y
        iny
    zuntil eq

    jsr UNTALK
    rts
zendproc

; Writes a 256-byte sector whose LBA index is in XA.

zproc write_sector
    jsr convert_to_ts
    pha
    tya
    pha

    ; Reset buffer pointer.

    lda #8
    jsr LISTEN
    lda #$6f
    jsr SECOND

    lda #<reset_buffer_pointer_command
    ldx #>reset_buffer_pointer_command
    jsr string_out

    jsr UNLSN

    ; Write bytes.

    lda #8
    jsr LISTEN
    lda #$62
    jsr SECOND

    ldy #0
    zrepeat
        lda disk_buffer, y
        jsr CIOUT
        iny
    zuntil eq

    jsr UNLSN

    ; Write buffer to disk.

    lda #8
    jsr LISTEN
    lda #$6f
    jsr SECOND

    lda #'U'
    jsr CIOUT
    lda #'2'
    jsr CIOUT
    lda #2
    jsr decimal_out
    lda #0
    jsr decimal_out
    pla                 ; get sector
    jsr decimal_out
    pla                 ; get track
    jsr decimal_out
    lda #13
    jsr CIOUT

    jsr UNLSN

    ; jsr get_status

    rts

reset_buffer_pointer_command:
    .ascii "B-P 2 0"
    .byte 13, 0
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
    lda #$36
    sta 1                   ; map Basic out
    lda #0
    sta 53280               ; black border
    sta 53281               ; black background

    ; Print the startup banner (directly with CHROUT).

    ldy #0
    zloop
        lda loading_msg, y
        zbreakif eq
        jsr CHROUT
        iny
    zendloop

    ; General initialisation.

    lda #0
    sta pending_key
    sta buffer_dirty
    lda #$ff
    sta buffered_sector+0
    sta buffered_sector+1
    sta buffered_sector+2

    jsr initdrivers

    lda #8
    jsr LISTEN
    lda #$f2
    jsr SECOND
    lda #'#'
    jsr CIOUT
    jsr UNLSN

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


loading_msg:
    .byte 147, 14, 5
    .ascii "cp/m-65 FOR THE cOMMODORE 64"
    .byte 13, 0

.data

zp_base:    .byte __USERZEROPAGE_START__
zp_end:     .byte __USERZEROPAGE_END__
mem_base:   .byte __USERTPA_START__@mos16hi
mem_end:    .byte __USERTPA_END__@mos16hi

; DPH for drive 0 (our only drive)

define_dpb dpb, 136*10, 1024, 64, 0
define_dph dph, dpb

NOINIT

pending_key:     .byte 0 ; pending keypress from system
sector_num:      .fill 3 ; current absolute sector number
buffered_sector: .fill 3 ; sector currently in disk buffer
buffer_dirty:    .fill 1 ; non-zero if sector needs flushing

.global directory_buffer
directory_buffer: .fill 128
disk_buffer: .fill 256

; vim: sw=4 ts=4 et ft=asm

