; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; Atari 800 XL/XE Port Copyright © 2023 Ivo van Poorten

; Disk layout SS SD 40 tracks x 18 sectors = 720 sectors.
; or
; 455 tracks x 18 sectors = 8190 sectors (CP/M FS uses 8176)

; The first track is reserved for the boot code.

#include "zif.inc"
#include "cpm65.inc"
#include "atari800.inc"
#include "driver.inc"
#include "jumptables.inc"

ZEROPAGE

.global ptr
.global ptr1

ptr = FMSZPG
ptr1 = FMSZPG+2

save_y = FMSZPG+4

; 2 bytes of FMSZPG left

charin = PTEMP      ; temporary on ZP that we don't use
charout = PTEMP

SCREEN_WIDTH = 40
SCREEN_HEIGHT = 24

cursorx = COLCRS
cursory = ROWCRS

    .text

; Boot code and initialization is ran only once. Eventually it is overwritten
; by the directory buffer.

.global _start

.section loader, "ax"

_start:

    ; Boot sector

    .byte 0

#ifdef ATARI_XL
    .byte 17            ; (filesize(atari800xlhd.exe)+127)/128
#else
#   ifdef ATARI_HD
        .byte 13        ; (filesize(atari800hd.exe)+127)/128
#   else
        .byte 13        ; (filesize(atari800.exe)+127)/128
#   endif
#endif

    .word $3000
    .word init      ; just use init and never return

init:
#ifdef ATARI_XL

    sei
    lda #0
    sta NMIEN
    sta IRQEN

    lda #<KIR
    sta VKEYBD
    lda #>KIR
    sta VKEYBD+1

    lda #<IVNM
    sta VVBLKI
    lda #>IVNM
    sta VVBLKI+1

    lda #$fe        ; BASIC OFF, OS ROM OFF
    sta PORTB

    lda #<IRQ
    sta $fffe
    lda #>IRQ
    sta $ffff

    lda #<NMI
    sta $fffa
    lda #>NMI
    sta $fffb

#endif

    ; Copy BIOS to bios RAM

    jsr memcpy          ; default values copy BIOS, XL port reuses memcpy

#ifdef ATARI_XL
    ; Copy ROM font to temporary RAM

    lda #$ff
    sta PORTB

    lda #<FONT
    sta memload
    lda #>FONT
    sta memload+1
    lda #<TMPFONT
    sta memstore
    lda #>TMPFONT
    sta memstore+1
    lda #<TMPFONTEND
    sta memcmplsb
    lda #>TMPFONTEND
    sta memcmpmsb
    jsr memcpy

    ; and back "under" the ROM

    lda #$fe
    sta PORTB

    lda #<TMPFONT
    sta memload
    lda #>TMPFONT
    sta memload+1
    lda #<FONT
    sta memstore
    lda #>FONT
    sta memstore+1
    lda #<FONTEND
    sta memcmplsb
    lda #>FONTEND
    sta memcmpmsb
    jsr memcpy

    ; Copy wrappers and handlers to low RAM

    lda #<wrappers_load_addr
    sta memload
    lda #>wrappers_load_addr
    sta memload+1
    lda #<wrappers_exec_addr
    sta memstore
    lda #>wrappers_exec_addr
    sta memstore+1
    lda #<wrappers_end_addr
    sta memcmplsb
    lda #>wrappers_end_addr
    sta memcmpmsb
    jsr memcpy

    lda #$40
    sta POKMSK      ; Keyboard only
    sta IRQEN

;    lda #$40
    sta NMIEN       ; VBI only
    cli
#endif

#ifdef ATARI_XL
    lda #$d0
#else
    lda RAMSIZ
#endif
    sta mem_end

    lda #0
    sta ptr
    sta LMARGN
    sta FILDAT      ; no memory reserved for alternate font
    sta COLCRS      ; leftover cursor will be overwritten by banner
    sta COLCRS+1
    sta SHFLOK      ; start lower case
    sta COLOR2      ; background (black)
    sta COLPF2      ; hardware register, too, VBI might not occur during SIO

    ; IOCB0 E: is already open

    ; Create display list with a scanline of blank space between text lines to
    ; avoid ascenders and descenders touching eachother when we load a
    ; proper 7x8 font from user space.

    sta SDMCTL      ; turn off screen gracefully while we adjust the DL
    sta DMACTL      ; hardware register
    sta SDLSTL      ; set DL pointer LSB
    sta DLISTL

    ldx #>__SCREENDATA_START__
    stx SDLSTH
    stx DLISTH
    stx ptr+1
    tay

    stx dl_prologue+4
    stx SAVMSC+1
    lda #$40
    sta dl_prologue+3
    sta SAVMSC

    zrepeat
        lda dl_prologue,y
        sta (ptr),y
        iny
        cpy #5
    zuntil_eq

    ldx #23
    zrepeat
        lda #0      ; 1 black line
        sta (ptr),y
        iny
        lda #2      ; Mode 2
        sta (ptr),y
        iny
        dex
    zuntil_eq

    lda #$41
    sta (ptr),y
    txa
    iny
    sta (ptr),y
    iny
    lda #>__SCREENDATA_START__
    sta (ptr),y

    lda #$22
    sta SDMCTL      ; turn on screen again
    sta DMACTL

    ; Print banner.

    ldy #banner_end - banner
    zrepeat
        lda banner - 1, y
        sty save_y
        jsr tty_conout
        ldy save_y
        dey
    zuntil_eq

    ; Open IOCB1 for K device (no direct OS call hack)

    ldx #1*16
    lda #4
    sta ICAX1,x
    lda #0
    sta ICAX2,x
    lda #COPEN
    sta ICCOM,x
    lda #<kdevice
    sta ICBAL,x
    lda #>kdevice
    sta ICBAH,x

#ifdef ATARI_XL
    jsr CIOV_wrapper
#else
    jsr CIOV
#endif

    ; Figure out the start and end of the TPA.
    ; mem_base, mem_end are already set correctly for where BDOS loads

    ; BIOS initialisation

    jsr initdrivers

    ; Load the BDOS image

#ifdef ATARI_XL
    lda #1
    sta mem_bank
    ldy mem_base+1
#else
    ldy #>__USERTPA_START__
#endif
    lda #<bdos_filename
    ldx #>bdos_filename
    jsr loadfile

    ; Relocate it.

#ifdef ATARI_XL
    lda mem_base+1
#else
    lda #>__USERTPA_START__
#endif
    ldx #__USERZEROPAGE_START__
    jsr bios_RELOCATE

    ; Compute the entry address and jump.

#ifdef ATARI_XL
    lda mem_base+1
#else
    lda mem_base
#endif
    pha
    lda #COMHDR_ENTRY-1 ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump to BDOS

memcpy:
    zrepeat
        memload = .+1
        lda bios_load_addr
        memstore = .+1
        sta bios_exec_addr

        inc memload
        zif_eq
            inc memload+1
        zendif

        inc memstore
        zif_eq
            inc memstore+1
            zbreakif_eq
        zendif

        lda memstore
        memcmplsb = .+1
        cmp #<bios_end_addr
        zcontinueif_ne
        lda memstore+1
        memcmpmsb = .+1
        cmp #>bios_end_addr
    zuntil_eq
    rts

dl_prologue:
    .byte $70, $30, $42, 0, 0

banner: ; reversed!
    .byte 10,13
#ifdef ATARI_XL
    .ascii "LX"
#endif
    .ascii "008 iratA eht rof 56-M/PC"
banner_end:

kdevice: .ascii "K"
         .byte 155

bdos_filename:
    .ascii "BDOS    SYS"

; --- BIOS entrypoints ------------------------------------------------------

.data
.global drvtop
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
    lda SAVMSC
    sta ptr
    lda SAVMSC+1
    sta ptr+1

    ldx #SCREEN_HEIGHT              ; count lines
    zrepeat
        ldy #SCREEN_WIDTH-1
        lda #0                      ; screen memory space character
        zrepeat
            sta (ptr), y
            dey
        zuntil_mi

        lda ptr
        clc
        adc #SCREEN_WIDTH
        sta ptr
        zif_cs
            inc ptr+1
        zendif

        dex
    zuntil_eq

    ; SCREEN doesn't specify where the cursor ends up, but this code is used by
    ; TTY and homing the cursor here simplifies things.

    lda #0
    sta cursorx
    sta cursory
    rts
zendproc

; On top of the official specification, we clip (A,X) at the screen edges

zproc screen_setcursor
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

zproc screen_getcursor
    lda cursorx
    ldx cursory
    rts
zendproc

; XA = timeout in cs

zproc screen_getchar
    sta ptr
    stx ptr+1

    clc
    ror ptr+1                       ; divide be two, we can only count
    ror ptr                         ; two centiseconds at a time

    ldy RTCLOK                      ; incremented every 1/50th of a second
    iny

    jsr toggle_cursor

    zloop
        ldx CH
        inx
        zbreakif_ne                 ; break if key is pending
        cpy RTCLOK
        zif_eq
            iny
            lda ptr
            zif_eq
                dec ptr+1
                ldx ptr+1
                cpx #$ff
                zif_eq
                    jsr toggle_cursor
                    sec             ; timer expired
                    rts
                zendif
            zendif
            dec ptr
        zendif
    zendloop

    jsr toggle_cursor
    jsr tty_conin
    clc
    rts
zendproc

zproc screen_putchar
    pha
    jsr calculate_cursor_address
    pla
    jsr convert_ascii_to_screencode
    ldy cursorx
style=.+1
    eor #$00
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

        jsr convert_ascii_to_screencode
        sta (ptr), y
        iny
        cpy #SCREEN_WIDTH
        zbreakif_eq
        inx
    zendloop
    dey
    sty cursorx

    rts
zendproc

zproc screen_scrollup
    lda SAVMSC
    sta ptr1
    lda SAVMSC+1
    sta ptr1+1          ; ptr1 is dest pointer
    sta ptr+1           ; ptr is source pointer, first source is on same page

    ldx #SCREEN_HEIGHT-1              ; count lines
    zrepeat
        lda ptr1
        clc
        adc #SCREEN_WIDTH
        sta ptr
        zif_cs
            inc ptr+1
        zendif

        ldy #SCREEN_WIDTH-1
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        lda ptr
        sta ptr1
        lda ptr+1
        sta ptr1+1

        dex
    zuntil_eq

    ldy #SCREEN_WIDTH-1
    lda #0                  ; screen memory space
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc screen_scrolldown
    lda SAVMSC
    clc
    adc #<((SCREEN_HEIGHT-1)*SCREEN_WIDTH)
    sta ptr1
    lda SAVMSC+1
    adc #>((SCREEN_HEIGHT-1)*SCREEN_WIDTH)
    sta ptr1+1              ; ptr1 is dest pointer
    sta ptr+1               ; ptr is source pointer, first time on same page

    ldx #SCREEN_HEIGHT-1             ; current line
    zrepeat
        lda ptr1
        sec
        sbc #SCREEN_WIDTH
        sta ptr
        zif_cc
            dec ptr+1
        zendif

        ldy #SCREEN_WIDTH-1
        zrepeat
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        lda ptr
        sta ptr1
        lda ptr+1
        sta ptr1+1

        dex
    zuntil_eq

    ldy #SCREEN_WIDTH-1
    lda #0                          ; screen memory space
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc screen_cleartoeol
    jsr calculate_cursor_address

    lda #0                          ; screen memory space
    zrepeat
        sta (ptr), y
        iny
        cpy #SCREEN_WIDTH
    zuntil_eq

    rts
zendproc

; --- TTY DRIVER ------------------------------------------------------------

; Blocks and waits for the next keypress; returns it in A.

zproc tty_conin
    jsr toggle_cursor

    ldx #1*16
    lda #CGBIN
    sta ICCOM,x
    lda #1
    sta ICBLL,x
    lda #0
    sta ICBLH,x
    lda #<charin
    sta ICBAL,x
    lda #>charin
    sta ICBAH,x

#ifdef ATARI_XL
    jsr CIOV_wrapper
#else
    jsr CIOV
#endif

    lda charin

    cmp #ATARI_EOL
    zif_eq
        lda #13
        bne 1f
    zendif

    cmp #ATARI_BS
    zif_eq
        lda #127            ; DEL not BS
        bne 1f
    zendif

    cmp #ATARI_TAB
    zif_eq
        lda #9
    zendif                  ; fallthrough

1:
    pha
    jsr toggle_cursor
    pla
    rts
zendproc

; Return 0 if no key is pending, $ff if there is

zproc tty_const
    ldx CH
    inx
    zif_eq
        lda #0
        rts
    zendif
    lda #$ff
    rts
zendproc

; Output character in A

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
        lda #0                        ; cursor overwrites old character
        sta (ptr),y
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

; Preserves X and Y.
zproc convert_ascii_to_screencode
    cmp #32
    zif_cc
        clc
        adc #64
        rts
    zendif
    cmp #96
    zif_cc
        sec
        sbc #32
        rts
    zendif
    rts
zendproc

; Sets (ptr), y to the location of the cursor.

zproc calculate_cursor_address
    ldy cursorx
    lda cursory

    ; x*40 = x*8 + x*32.

    ; We have 24 lines. As 24*8 will fit in a byte, we can do this easily.

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

    lda ptr+0
    clc
    adc SAVMSC
    sta ptr+0
    lda ptr+1
    and #3
    adc SAVMSC+1
    sta ptr+1
    rts

zproc toggle_cursor
    jsr calculate_cursor_address
    lda (ptr),y
    eor #$80
    sta (ptr),y
    rts
zendproc

zproc screen_showcursor
    cmp #0
    zif_eq
        lda #$60            ; rts instruction
    zelse
        lda #$20            ; jsr instruction
    zendif
    sta toggle_cursor
    rts
zendproc

zproc screen_setstyle
    cmp #STYLE_REVERSE
    zif_eq
        lda #$80
    zelse
        lda #0
    zendif
    sta style
    rts
zendproc

; ---------------------------------------------------------------------------

; Sets the current DMA address.

zproc bios_SETDMA
    sta dma+0
    stx dma+1
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc bios_SELDSK
    cmp #0
    zif_ne
        sec                 ; invalid drive
        rts
    zendif

    sta drive_number

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

; BDOS looks at DPH to see how many sectors to skip.

zproc bios_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil_mi
    rts
zendproc

zproc bios_READ
    lda #$40        ; data direction receive
    sta DSTATS
    lda #SIO_READ_SECTOR
    bne do_SIO
zendproc            ; fallthrough

zproc bios_WRITE
    lda #$80        ; data direction send
    sta DSTATS
    lda #SIO_WRITE_SECTOR

do_SIO:
    sta DCOMND
    lda #$31
    clc
    adc drive_number
    sta DDEVIC
    and #$0f
    sta DUNIT

    lda dma
    sta DBUFLO
    lda dma+1
    sta DBUFHI

    lda #128
    sta DBYTLO
    lda #0
    sta DBYTHI

    lda sector_num      ; Atari starts counting at sector 1
    clc
    adc #1
    sta DAUX1
    lda sector_num+1
    adc #0
    sta DAUX2

#ifdef ATARI_XL
    jsr SIOV_wrapper
#else
    jsr SIOV
#endif

    lda DSTATS
    cmp #1
    beq status_ok

    sec
    rts

status_ok:
    clc
    rts
zendproc

zproc bios_GETTPA
#ifdef ATARI_XL
    ldy mem_bank
    lda mem_base,y
    ldx mem_end,y
#else
    lda mem_base
    ldx mem_end
#endif
    rts
zendproc

zproc bios_SETTPA
#ifdef ATARI_XL
    ldy mem_bank
    sta mem_base,y
    txa                 ; BUG: stx mem_end,y - invalid 6502 instruction
    sta mem_end,y
#else
    sta mem_base
    stx mem_end
#endif
    rts
zendproc

zproc bios_GETZP
    lda zp_base
    ldx zp_end
    rts
zendproc

zproc bios_SETZP
    sta zp_base
    stx zp_end
    rts
zendproc

zproc bios_SETBANK
#ifdef ATARI_XL
    sta mem_bank
#endif
    rts
zendproc

; ---------------------------------------------------------------------------

    .data

zp_base: .byte __USERZEROPAGE_START__
zp_end:  .byte __USERZEROPAGE_END__

#ifdef ATARI_XL
mem_bank: .byte 0
mem_base: .byte __USERTPA_START__@mos16hi, $e4
mem_end:  .byte 0, $ff
#else
mem_base: .byte __USERTPA_START__@mos16hi
mem_end:  .byte 0
#endif

; DPH for drive 0 (our only drive)

; number of sectors, blocksize, direntries, reserved _sectors_

; 54 reserved sectors = 6912 bytes for BIOS and BDOS

#ifdef ATARI_HD
define_drive dph, 8190, 2048, 128, 18
#else
define_drive dph, 720, 1024, 64, 18
#endif

    .section .noinit, "ax", @nobits

    .global directory_buffer
directory_buffer:   .fill 128           ; can be under RAM
drive_number:       .fill 1
sector_num:         .fill 3
dma:                .fill 2

; ---------------------------------------------------------------------------

#ifdef ATARI_XL

; Low memory wrappers for the Atari XL port where the original ROM OS
; is turned off and only turned on for using SIO or PBI devices, and
; reading the keyboard.
;
; We also need a minimal IRQ running while the OS is off so we can buffer
; a keypress like the original OS and CONST will work correctly.
; A minimal VBI is needed to copy just the shadow registers we need
; and handle keyboard debounce.

; During init, set POKMSK to 0b01000000 ($40 = keyboard interrupt only)

    .section wrappers, "ax"

IRQ:                        ; hardware vector here
    pha

    lda IRQST
    and #$40
    bne irq_out

    lda #$bf                ; acknowledge ~$40
    sta IRQEN
    lda POKMSK
    sta IRQEN

KIR:                        ; vector here for normal OS
    lda KBCODE
    cmp CH1
    bne not_the_same_key

    lda KEYDEL
    bne bounce

not_the_same_key:
    lda KBCODE
    sta CH
    sta CH1

    lda #3
    sta KEYDEL

bounce:
    lda KRPDEL
    sta SRTIMR

irq_out:
    pla
    rti

; We only service VBIs, not DLIs

NMI:                            ; hardware vector here
    pha
    txa
    pha
    tya
    pha

    sta NMIRES

IVNM:                           ; vector VVBLKI here
    inc RTCLOK+2                ; might come in handy later
    bne clok_done
    inc RTCLOK+1
    bne clok_done
    inc RTCLOK

clok_done:

    ldx #8
    zrepeat
        lda PCOLOR0,x
        sta COLPM0,x
        dex
    zuntil_mi

    lda CHBAS
    sta CHBASE

    lda SDLSTL
    sta DLISTL
    lda SDLSTL+1
    sta DLISTH

    ; keyboard stuff
    lda SKSTAT
    and #$04
    beq key_down

    ; key up
    lda KEYDEL
    beq counted_down

    dec KEYDEL

counted_down:
key_down:
    lda SRTIMR
    beq continue

    lda SKSTAT
    and #$04
    bne no_longer_down

    dec SRTIMR
    bne continue

    lda KEYREP
    sta SRTIMR
    lda KBCODE
    sta CH
    jmp continue

no_longer_down:
    lda #0
    sta SRTIMR

continue:

DVNM:
    pla
    tay
    pla
    tax
    pla
    rti

; Leave banking bits alone on a 130XE

SIOV_wrapper:
    lda DBUFHI          ; we cannot load directly under the ROM if it's on
    cmp #$bf            ; be safe, no 16-bit compare
    bcc actual_sio      ; definitely directly to RAM

    sta ptr+1           ; save for later
    lda DBUFLO
    sta ptr

    lda #<sector_buffer ; temporary buffer
    sta DBUFLO
    lda #>sector_buffer
    sta DBUFHI

    lda DCOMND
    cmp #SIO_WRITE_SECTOR
    bne no_write

    ldy #0              ; write: copy dma to temporary buffer
    zrepeat
        lda (ptr),y
        sta sector_buffer,y
        iny
    zuntil_mi

no_write:
    jsr actual_sio

    lda DCOMND
    cmp #SIO_READ_SECTOR
    bne siov_done

    ldy #0              ; read: copy temporary buffer to dma
    zrepeat
        lda sector_buffer,y
        sta (ptr),y
        iny
    zuntil_mi

siov_done:
    rts

actual_sio:
    lda PORTB
    ora #1              ; enable ROM
    sta PORTB

    jsr SIOV

    lda PORTB
    and #$fe            ; disable ROM
    sta PORTB

    rts

CIOV_wrapper:
    lda PORTB
    ora #1              ; enable ROM
    sta PORTB

    jsr CIOV

    lda PORTB
    and #$fe            ; disable ROM
    sta PORTB
    rts

    .section wrappersnoinit, "ax", @nobits

sector_buffer: .ds 128

#endif

; vim: filetype=asm sw=4 ts=4 et
