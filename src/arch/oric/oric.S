; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
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

#define MFDC_Flag_Side0          0b10000001
#define MFDC_Flag_Side1          0b10010001

#define MFDC_ID                  0

#define MCMD_ReadSector          0x80
#define MCMD_WriteSector         0xa0
#define MCMD_Seek                0x1f

/* Jasmin interface definitions */

#define JFDC_command_register    0x03f4
#define JFDC_status_register     0x03f4
#define JFDC_track_register      0x03f5
#define JFDC_sector_register     0x03f6
#define JFDC_data                0x03f7
#define JFDC_flags               0x03f8
#define JFDC_drq                 0x03FC

#define JFDC_Flag_Side0          0b00000000
#define JFDC_Flag_Side1          0b00000001

#define JFDC_ovl_control         0x03FA
#define JFDC_rom_control         0x03FB

#define JFDC_ID                  1

#define JCMD_ReadSector          0x8c
#define JCMD_WriteSector         0xac
#define JCMD_Seek                0x1F

#define FLOPPY_DELAY            30

/* Other system definitions */

; 6522 VIA
VIA      = 0x0300
VIA_PB   = VIA + 0
VIA_PA   = VIA + 1
VIA_DDRB = VIA + 2
VIA_DDRA = VIA + 3
VIA_T1CL = VIA + 4
VIA_T1CH = VIA + 5
VIA_T1LL = VIA + 6
VIA_T1LH = VIA + 7
VIA_T2CL = VIA + 8
VIA_T2CH = VIA + 9
VIA_SR   = VIA + 10
VIA_ACR  = VIA + 11
VIA_PCR  = VIA + 12
VIA_IFR  = VIA + 13
VIA_IER  = VIA + 14
VIA_ORA  = VIA + 15

VIA_PB_NDAC_IN  = 1<<0
VIA_PB_NRFD_OUT = 1<<1
VIA_PB_ATN_OUT  = 1<<2
VIA_PB_NRFD_IN  = 1<<6
VIA_PB_DAV_IN   = 1<<7

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
dma:              .fill 2     ; current DMA

; --- Bootloader code -------------------------------------------------------

/* The Oric boot process is a bit complicated due to there being two different
 * disk systems we need to support. */

.section "sector1", "ax"

; Jasmin will load this at 0x0400.

    jmp jasmin_start

; Microdisk requires this literal data.

    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x20, 0x20 ; :.....   :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x03 ; :     ...:
    .byte 0x00, 0x00, 0x00, 0x01, 0x00, 0x53, 0x45, 0x44 ; :.....SED:
    .byte 0x4F, 0x52, 0x49, 0x43, 0x20, 0x20, 0x20, 0x20 ; :ORIC    :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 ; :        :
    .byte 0x20, 0x20, 0x20, 0x20, 0x20                   ; :    ....:

; Jasmin boot code starts here.

jasmin_start:
    /* Turn off the EPROM, exposing RAM. */

    sei
    lda #1
    sta JFDC_ovl_control        ; enable overlay RAM
    sta JFDC_rom_control        ; disable ROM

    /* Set up for reading the BIOS. */

    lda #<BIOS_LOAD_ADDR        ; set read pointer
    sta ptr+0
    lda #>BIOS_LOAD_ADDR
    sta ptr+1

    ldx #4                      ; sector to read
    zrepeat
        stx JFDC_sector_register    ; sector to read

        /* Do the read. */

        lda #JCMD_ReadSector
        sta JFDC_command_register

        ldy #FLOPPY_DELAY
        zrepeat
            nop
            nop
            dey
        zuntil_eq

        ldy #0
        zrepeat
            zrepeat
                lda JFDC_drq
            zuntil_pl
            lda JFDC_data
            sta (ptr), y
            iny
        zuntil_eq

        /* Advance to next sector. */

        inx
        inc ptr+1
        cpx #4 + BIOS_SECTOR_COUNT
    zuntil_eq

    /* Patch the BIOS floppy routines to use the Jasmin registers. */

    lda #JFDC_Flag_Side0
    sta __fdc_side0_flag
    lda #JFDC_Flag_Side1
    sta __fdc_side1_flag
    lda #JCMD_ReadSector
    sta __fdc_readsector_cmd
    lda #JCMD_WriteSector
    sta __fdc_writesector_cmd
    lda #JCMD_Seek
    sta __fdc_seek_cmd
    lda #<JFDC_command_register
    sta __fdc_command_reg
    lda #<JFDC_drq
    sta __fdc_drq_reg_0
    sta __fdc_drq_reg_1
    lda #<JFDC_status_register
    sta __fdc_status_reg
    lda #<JFDC_flags
    sta __fdc_flags_reg
    lda #<JFDC_data
    sta __fdc_data_reg_0
    sta __fdc_data_reg_1
    sta __fdc_data_reg_2
    lda #<JFDC_track_register
    sta __fdc_track_reg
    lda #<JFDC_sector_register
    sta __fdc_sector_reg

    lda #JFDC_ID
    jmp _start

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

    lda #MFDC_Flag_Side0        ; EPROM off, FDC interrupts off
    sta MFDC_flags

    /* Set up for reading the BIOS. */

    lda #<BIOS_LOAD_ADDR        ; set read pointer
    sta ptr+0
    lda #>BIOS_LOAD_ADDR
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
        cpx #4 + BIOS_SECTOR_COUNT
    zuntil_eq

    lda #MFDC_ID
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
    pha                     ; store xFDC_ID
    jsr init_hardware
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

    pla                     ; get xFDC_ID back
    zif_ne
      ldy #msg_jasmin_end - msg_jasmin
      zrepeat
          tya
          pha
          lda msg_jasmin-1, y
          jsr tty_conout
          pla
          tay
          dey
      zuntil_eq
      beq msg_crlf
    zendif

    ldy #msg_microdisc_end - msg_microdisc
    zrepeat
        tya
        pha
        lda msg_microdisc-1, y
        jsr tty_conout
        pla
        tay
        dey
    zuntil_eq

msg_crlf:
    lda #10
    jsr tty_conout
    lda #13
    jsr tty_conout

    ; Miscellaneous initialisation.

    ldx #bss_top - bss_bottom
    lda #0
    zrepeat
        sta bss_bottom-1, x
        dex
    zuntil_eq

    ldx #0xff
    stx buffered_host_sector
    stx buffered_track
    jsr initdrivers

    ; Read the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy #>__TPA1_START__
    jsr loadfile

    ; Relocate it.

    lda #>__TPA1_START__
    ldx #__ZEROPAGE_START__
    jsr bios_RELOCATE

    ; Go!

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA1_START__ + COMHDR_ENTRY

bdos_filename:
    .ascii "BDOS    SYS"

msg_jasmin:
    .ascii "nimsaJ"
msg_jasmin_end:

msg_microdisc:
    .ascii "csidorciM"
msg_microdisc_end:

banner: ; reversed!
    .ascii "/cirO eht rof 56-M/PC"
banner_end:

zendproc

; Initializes VIA and AY-3-8912 defaults (iss)
zproc init_hardware

    lda   #0xff
    sta   VIA_PA
    sta   VIA_ORA
    sta   VIA_DDRA
    lda   #0xb7
    sta   VIA_PB
    lda   #0xf7
    sta   VIA_DDRB
    lda   #0xdd
    sta   VIA_PCR
    lda   #0x7f
    sta   VIA_IER
    lda   #0x40
    sta   VIA_ACR

    lda   #<50000           ; 50 msec
    ldx   #>50000
    sta   VIA_T1LL
    sta   VIA_T1CL
    stx   VIA_T1LH
    stx   VIA_T1CH

    lda   #0xc0             ; enable T1 interrupt
    sta   VIA_IER

    lda   #0x07             ; set i/o port on 8912 to output
    ldx   #0x3f             ; and disable mixer
    jsr   psg_x2a

    lda   #0x08             ; mute all channels
    ldx   #0x00
    jsr   psg_x2a
    lda   #0x09
    ldx   #0x00
    jsr   psg_x2a
    lda   #0x0a
    ldx   #0x00
    jsr   psg_x2a

    lda   #0x00
    ldx   #0x7f
    jsr   psg_x2a

    lda   #0x01
    ldx   #0x00
;   jmp   psg_x2a           ; fall trough
zendproc

; Writes X to port A
zproc psg_x2a
    sta   VIA_PA
    tay
    txa
    cpy   #0x07
    zif_eq
      ora   #0x40
    zendif
    pha
    lda   VIA_PCR
    ora   #0xee
    sta   VIA_PCR
    and   #0x11
    ora   #0xcc
    sta   VIA_PCR
    tax
    pla
    sta   VIA_PA
    txa
    ora   #0xec
    sta   VIA_PCR
    and   #0x11
    ora   #0xcc
    sta   VIA_PCR
    rts
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
    txa                 ; BUG: stx mem_end, y - invalid 6502 instruction
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

zproc fail
    sec
    rts
zendproc

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
    bne fail                ; invalid drive

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

    ; Copy bottom 16 of sector number to temporary (the top byte must be 0).

    ldy #0
    lda (ptr), y
    sta ptr1+0
    iny
    lda (ptr), y
    sta ptr1+1

    ; There are 34 CP/M sectors per host track. Do a 16-bit divide.

    lda #0
    sta requested_cpm_sector

    ldx #16
    lda #0
    zrepeat
        asl ptr1+0
        rol ptr1+1
        rol a
        cmp #34
        zif_cs
            sbc #34
            inc ptr1+0
        zendif
        dex
    zuntil_eq
    sta requested_cpm_sector
    lda ptr1+0
    sta requested_track

    rts
zendproc

zproc bios_READ
    jsr change_sector
    zif_cc
        lda requested_cpm_sector
        ror a
        lda #0
        ror a               ; 0x00 or 0x80
        tax

        ldy #0
        zrepeat
            lda DISK_BUFFER, x
            sta (dma), y
            inx
            iny
            cpy #0x80
        zuntil_eq
        clc
    zendif
    rts
zendproc

zproc bios_WRITE
    pha
    jsr change_sector
    pla
    zif_cc
        pha

        lda requested_cpm_sector
        ror a
        lda #0
        ror a               ; 0x00 or 0x80
        tax

        ldy #0
        zrepeat
            lda (dma), y
            sta DISK_BUFFER, x
            inx
            iny
            cpy #0x80
        zuntil_eq

        lda #0x80
        sta buffer_dirty

        clc
        pla
        zif_ne
            jsr flush_buffer
        zendif
    zendif
    rts
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
    dec const_counter
    zif_mi
        lda #16
        sta const_counter
        jsr scan_keyboard
    zendif

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
    jmptablo screen_getchar
    jmptablo fail
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
    jmptabhi fail
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
    cmp #32
    zif_cs
        pha
        jsr calculate_cursor_address
        pla
        ora screen_style
        sta (ptr), y
    zendif

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

zproc toggle_cursor
    jsr calculate_cursor_address
    lda (ptr), y
    eor #0x80
    sta (ptr), y
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
    ora screen_style
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
    ora screen_style
    zrepeat
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

zproc screen_cleartoeol
    jsr calculate_cursor_address

    lda #' '
    ora screen_style
    zrepeat
        sta (ptr), y
        iny
        cpy #SCREEN_WIDTH
    zuntil_eq
    rts
zendproc

zproc screen_setstyle
    ldx #0
    and #STYLE_REVERSE
    zif_ne
        ldx #0x80
    zendif
    stx screen_style
    rts
zendproc

; --- Keyboard --------------------------------------------------------------

zproc screen_getchar
    jsr toggle_cursor
    zrepeat
        jsr scan_keyboard
        lda pending_key
    zuntil_ne
    pha
    jsr toggle_cursor
    pla

    ldx #0
    stx pending_key

    clc
    rts
zendproc

; Does a single keyboard scan, processing any pressed keys. Last pressed key
; wins.

zproc scan_keyboard
    ldy #7                      ; row counter
    zrepeat
        sty VIA_PB

        ldx #7                      ; column counter
        zrepeat
            lda #0x0e               ; AY column register
            sta VIA_PA
            lda #0xff               ; write to AY
            sta VIA_PCR
            lda #0xdd               ; clear CB2
            sta VIA_PCR

            lda column_pa_values, x
            sta VIA_PA
            lda #0xfd
            sta VIA_PCR
            lda #0xdd
            sta VIA_PCR

            ; Bit 3 of PB is now set if a key is pressed.

            lda VIA_PB
            and #0x08
            lsr a
            lsr a
            lsr a
            lsr a                   ; C is set if key is pressed
            zif_cs
                lda column_store_values, x
            zendif
            eor keypress_bitfield, y
            and column_store_values, x ; has key changed state?
            zif_ne
                ; Key has changed state.

                eor keypress_bitfield, y
                sta keypress_bitfield, y ; update bitfield

                txa
                pha
                tya
                pha

                jsr key_state_changed

                pla
                tay
                pla
                tax
            zendif

            dex
        zuntil_mi

        dey
    zuntil_mi
    rts

column_pa_values:
    .byte 0x7f, 0xbf, 0xdf, 0xef, 0xf7, 0xfb, 0xfd, 0xfe
column_store_values:
    .byte 1, 2, 4, 8, 16, 32, 64, 128
zendproc

zproc key_state_changed
    tya
    asl a
    asl a
    asl a
    sta ptr+0
    txa
    clc
    adc ptr+0
    tax

    cpx #0x23
    beq shift_change
    cpx #0x3b
    beq shift_change
    cpx #0x13
    beq ctrl_change

    lda VIA_PB
    and #0x08
    zif_ne
        lda keyboard_decode_tab, x
        bit shift_pressed
        zif_mi
            lda keyboard_shift_decode_tab, x
        zendif
        bit ctrl_pressed
        zif_mi
            and #0x1f
        zendif
        sta pending_key
    zendif
    rts

shift_change:
    lda keypress_bitfield+4
    ora keypress_bitfield+7
    asl a
    asl a
    asl a
    asl a
    sta shift_pressed
    rts

ctrl_change:
    lda keypress_bitfield+2
    asl a
    asl a
    asl a
    asl a
    sta ctrl_pressed
    rts

keyboard_decode_tab:
    .byte '3', 'x', '1', 0, 'v', '5', 'n', '7'
    .byte 'd', 'q', 27,  0, 'f', 'r', 't', 'j'
    .byte 'c', '2', 'z', 0, '4', 'b', '6', 'm'
    .byte '\'', '\\', 0, 0, '-', ';', '9', 'k'
    .byte 0,   0,   0,   0, 0,   '.', ',', ' '
    .byte '[', ']', 127, 0, 'p', 'o', 'i', 'u'
    .byte 'w', 's', 'a', 0, 'e', 'g', 'h', 'y'
    .byte '=',  0,  13,  0, '/', '0', 'l', '8'

keyboard_shift_decode_tab:
    .byte '#', 'X', '!', 0, 'V', '%', 'N', '&'
    .byte 'D', 'Q', 27,  0, 'F', 'R', 'T', 'J'
    .byte 'C', '"', 'Z', 0, '$', 'B', '^', 'M'
    .byte '\'', '\\', 0, 0, '_', ':', '(', 'K'
    .byte 0,   0,   0,   0, 0,   '<', '>', ' '
    .byte '{', '}', 127, 0, 'P', 'O', 'I', 'U'
    .byte 'W', 'S', 'A', 0, 'E', 'G', 'H', 'Y'
    .byte '+',  0,  13,  0, '|', ')', 'L', '*'
zendproc


; --- Disk access -----------------------------------------------------------

zproc change_sector
    lda requested_cpm_sector
    lsr a
    cmp buffered_host_sector
    zif_eq
        lda requested_track
        cmp buffered_track
        zif_eq
            ; Buffered track/sector not changing, so do no work.

            clc
            rts
        zendif
    zendif

    bit buffer_dirty
    zif_mi
        jsr flush_buffer
        zif_cs
            rts
        zendif
    zendif

    lda requested_cpm_sector
    lsr a
    sta buffered_host_sector

    lda requested_track
    sta buffered_track

    jsr prepare_read_fdc_command

    ldy #0
    zrepeat
        zrepeat
__fdc_drq_reg_0 = . + 1
            lda MFDC_drq
        zuntil_pl
__fdc_data_reg_0 = . + 1
        lda MFDC_data
        sta DISK_BUFFER, y
        iny
    zuntil_eq

    jsr wait_for_fdc_completion
    clc
    and #0x1c
    zif_ne
        ; Some kind of read error. The data in the buffer is corrupt.

        lda #0xff
        sta buffered_track

        sec
    zendif
    rts
zendproc

zproc flush_buffer
    jsr prepare_write_fdc_command

    ldy #0
    zrepeat
        zrepeat
__fdc_drq_reg_1 = . + 1
            lda MFDC_drq
        zuntil_pl
        lda DISK_BUFFER, y
__fdc_data_reg_1 = . + 1
        sta MFDC_data
        iny
    zuntil_eq

    jsr wait_for_fdc_completion
    sec
    and #0x1c
    zif_eq
        ; A successful write, so mark the buffer as clean.

        lda #0
        sta buffer_dirty
        clc
    zendif
    rts
zendproc

; Seek to the appropriate track and prepare for a read or write transfer.

zproc prepare_fdc
    ; Seek to track.

    lda buffered_track
    lsr a                           ; bottom bit is the side
__fdc_track_reg = . + 1
    cmp MFDC_track_register
    zif_ne
__fdc_data_reg_2 = . + 1
        sta MFDC_data               ; computed track
__fdc_seek_cmd = . + 1
        lda #MCMD_Seek
        jsr write_fdc_command

        jsr wait_for_fdc_completion
    zendif

    ; Set sector.

    ldx buffered_host_sector
    inx                             ; FDC wants 1-based sectors
__fdc_sector_reg = . + 1
    stx MFDC_sector_register

    ; Set head.

__fdc_side0_flag = . + 1
    ldx #MFDC_Flag_Side0
    lda buffered_track
    ror a
    zif_cs
__fdc_side1_flag = . + 1
        ldx #MFDC_Flag_Side1
    zendif
__fdc_flags_reg = . + 1
    stx MFDC_flags

    rts
zendproc

zproc wait_for_fdc_completion
    ; Short delay before checking the register.

    ldy #4
    zrepeat
        dey
    zuntil_eq

    zloop
__fdc_status_reg = . + 1
        lda MFDC_status_register
        lsr a
    zuntil_cc
    asl a
    rts
zendproc

zproc prepare_read_fdc_command
    jsr prepare_fdc
__fdc_readsector_cmd = . + 1
    lda #MCMD_ReadSector
zendproc
    ; fall through
zproc write_fdc_command
__fdc_command_reg = . + 1
    sta MFDC_command_register

    ldy #4
    zrepeat
        nop
        nop
        dey
    zuntil_eq
    rts
zendproc

zproc prepare_write_fdc_command
    jsr prepare_fdc
__fdc_writesector_cmd = . + 1
    lda #MCMD_WriteSector
    jmp write_fdc_command
zendproc

; --- Vectors ---------------------------------------------------------------

zproc brk_handler
    pla             ; discard flags

    ldy #brk_message_end - brk_message
    zrepeat
        tya
        pha
        lda brk_message-1, y
        jsr tty_conout
        pla
        tay
        dey
    zuntil_eq

    pla
    tay             ; low byte of fault address
    pla
    tax             ; high byte of fault address
    tya
    jsr print_hex16_number

    lda #10
    jsr tty_conout
    lda #13
    jsr tty_conout

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA1_START__ + COMHDR_ENTRY

brk_message: ; reversed!
    .ascii " KRB"
    .byte 13, 10, 13, 10
brk_message_end:
zendproc

zproc nmi_handler
    ldy #nmi_message_end - nmi_message
    zrepeat
        tya
        pha
        lda nmi_message-1, y
        jsr tty_conout
        pla
        tay
        dey
    zuntil_eq

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA1_START__ + COMHDR_ENTRY

nmi_message: ; reversed!
    .byte 13, 10
    .ascii "IMN"
    .byte 13, 10, 13, 10
nmi_message_end:
zendproc

; Prints a 16-bit hex number in XA.
zproc print_hex16_number
    pha
    txa
    jsr print_hex_number
    pla
    jmp print_hex_number
zendproc

; Prints an 8-bit hex number in A.
zproc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_hex4_number
    pla
print_hex4_number:
    and #$0f
    ora #'0'
    cmp #'9'+1
    zif_cs
        adc #6
    zendif
    pha
    jsr tty_conout
    pla
    rts
zendproc

.section "tail", "ax"

    .word nmi_handler
    .word 0
    .word brk_handler

; --- Data ------------------------------------------------------------------

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA0_START__@mos16hi, __TPA1_START__@mos16hi
mem_end:    .byte __TPA0_END__@mos16hi,   __TPA1_END__@mos16hi

; DPH for drive 0 (our only drive)

define_drive dph, 2844, 2048, 64, 34

.bss

bss_bottom:
current_bank:           .fill 1     ; which memory bank is selected
requested_cpm_sector:   .fill 1     ; CP/M sector requested by user
requested_track:        .fill 1     ; track requested by user
buffered_host_sector:   .fill 1     ; host sector in buffer
buffered_track:         .fill 1     ; track in buffer
buffer_dirty:           .fill 1     ; top bit set if the buffer was modified
directory_buffer:       .fill 128   ; used by the BDOS
keypress_bitfield:      .fill 8     ; stores which keys are pressed
pending_key:            .fill 1     ; ASCII code of pending keypress
shift_pressed:          .fill 1     ; top bit set if shift pressed
ctrl_pressed:           .fill 1     ; top bit set if ctrl pressed
const_counter:          .fill 1     ; number of consts until next key scan
screen_style:           .fill 1     ; top bit set if inverse video
bss_top:

.global directory_buffer

