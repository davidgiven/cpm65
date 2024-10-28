; Memory map:
;
; WRAM:
;   $7e0000-$7effff  (the first 8kB is also mapped at $000000)
;      The CP/M userspace. This has to be here because the 65816 stack pointer
;      has to be in bank 0.  This is in the window mapped at $7e0000, so when in
;      6502 mode with the stack pointer between $000100 and $0001ff then the
;      stack appears between $7e0100 and $7e01ff.
;   $7f0000-$7fffff
;      Supervisor workspace and buffers (yet to be determined).
;
; ROM:
;   $400000-$407fff
;      Fonts, the BIOS, and other resources.
;   $408000-$40ffff  (also mapped at $008000)
;      The main supervisor code. When the bank registers get set to zero, this
;      gets mapped in automatically.

.cpu "65816"
.enc "ascii"
.cdef " ~", 32
.include "snes.inc"

SCC_B_CTRL      = $5F00 ; SCC channel B control port
SCC_B_DATA      = $5F01 ; SCC channel B data port
SCC_A_CTRL      = $5F02 ; SCC channel A control port
SCC_A_DATA      = $5F03 ; SCC channel A data port

VRAM_MAP1_LOC   =  $0000
VRAM_MAP2_LOC   =  $0800
VRAM_TILES_LOC  =  $2000
VRAM_TILES2_LOC =  $6000

LOADER_ADDRESS  = $7e8000

SCREEN_WIDTH    = 64
SCREEN_HEIGHT   = 28
VSCROLL_POS     = 1024-8

MOD_SHIFT       = %10000000 ; n bit
MOD_CTRL        = %01000000 ; v bit
MOD_CAPS        = %00000100

CURSOR_SHOWN    = %10000000 ; n bit

; From driver.inc (which is the wrong syntax for 64tass to import)
STYLE_REVERSE   = 1

.virtual $7f0000
sector:         .long 0     ; 24 bits!
pending_key:    .byte 0
modifier_state: .byte 0
cursorp:        .word 0     ; character count from top left of screen
screen_flags:   .byte 0
style_word:     .byte 0     ; always zero
style_byte:     .byte 0     ; current screen drawing style
tick_counter:   .byte 0

vram_mirror_start:
map1_mirror:    .fill 2*32*SCREEN_HEIGHT
                .fill 2*32*(32 - SCREEN_HEIGHT) ; padding to match up with VRAM
map2_mirror:    .fill 2*32*SCREEN_HEIGHT
vram_mirror_end:

.endvirtual

.virtual 0
dma:            .long 0     ; 24 bits!
ptr:            .long 0     ; 24 bits!
.endvirtual

.dpage ?                ; Reserve $0006-$00ff for user programs

* = $000000
.logical $400000
font_data:
    .binary "4bpp.bin"
font_data_end:
font2_data:
    .binary "2bpp.bin"
font2_data_end:
bios_data:
    .binary "bios"
bios_data_end:
.endlogical

a16 .macro
    rep #$20
.endmacro

a8 .macro
    sep #$20
.endmacro

i16 .macro
    rep #$10
.endmacro

i8 .macro
    sep #$10
.endmacro

a8i8 .macro
    sep #$30
.endmacro

a16i16 .macro
    rep #$30
.endmacro

* = $008000
start:
    .autsiz
    sei
    clc
    xce
    a16i16

    ; Wipe memory.

    a8
    ldx #0
    txa
    -
        sta $7e0000, x
        sta $7f0000, x
        dex
        bne -

    ldx #$01ff          ; 6502-compatible
    txs
    pea #0              ; databank to zero for I/O access
    pld

    lda #$7e
    sta dma+2        ; top byte of DMA address

    ; Clear registers
    ldx #$33
    jsr clear_vram
-
    stz INIDISP,x
    stz NMITIMEN,x
    dex
    bpl -

    ; Initialise the screen.

    jsr init_screen

    ; Other hardware.

    jsr init_keyboard
    jsr screen_clear

    ; Wipe memory and copy the BIOS loader to its final position.

    a16
    lda #(bios_data_end-bios_data)-1
    ldx #<>bios_data
    ldy #<>LOADER_ADDRESS
    mvn #`bios_data, #`LOADER_ADDRESS
    lda #0

    ; Jump into the loader.

    lda #`LOADER_ADDRESS
    pha
    plb                     ; set DB so direct accesses go into user memory
    lda #0
    tad                     ; direct page register to 0

    jml LOADER_ADDRESS      ; ...and go

break:
    rts

init_screen
.block
    php
    phd
    a8
    i16

    ldx #$2100
    phx
    pld
    .dpage $2100

    lda #%10000000          ; force blank
    sta INIDISP

    lda #5 | $00            ; mode 5, 16x8 tiles all layers
    sta BGMODE
    lda #%00001100          ; high res mode, interlacing off
    sta SETINI
    lda #(VRAM_MAP1_LOC >> 9) | %00 ; tilemap 1 address, 32x32
    sta BG1SC
    lda #(VRAM_MAP2_LOC >> 9) | %00 ; tilemap 2 address, 32x32
    sta BG2SC
    lda #((>VRAM_TILES_LOC >> 5) | ((>VRAM_TILES2_LOC >> 1) & $f0))
    sta BG12NBA
    lda #%00000011          ; main screen turn on: BG1 and BG2
    sta TM
    sta TS                  ; ditto subscreen

    lda #<VSCROLL_POS
    sta BG1VOFS
    xba
    lda #>VSCROLL_POS
    sta BG1VOFS
    xba
    sta BG2VOFS
    xba
    sta BG2VOFS

    jsr load_font_data
    jsr load_palette_data

    lda #%10000000          ; enable vsync NMI
    sta NMITIMEN

    lda #%00001111          ; blank off, maximum brightness
    sta INIDISP

    lda #CURSOR_SHOWN
    sta screen_flags
    lda #$20
    sta style_byte

    pld
    plp
    rts
.endblock

wait_for_vblank:
    php
    a8 

-
    lda HVBJOY
    and #%10000000          ; test for v-blank flag
    beq -

    plp
    rts

load_palette_data:
    php
    a8i8

    lda #2
    sta CGADD

    stz CGDATA
    stz CGDATA
    lda #$ff
    sta CGDATA
    sta CGDATA

    ldx #4+2
    stx CGADD

    sta CGDATA
    sta CGDATA
    stz CGDATA
    stz CGDATA

    ldx #16+2
    stx CGADD

    sta CGDATA
    sta CGDATA
    stz CGDATA
    stz CGDATA

    plp
    rts

load_font_data:
    php
    a16i16

    lda #%10000000       ; autoincrement by one word
    sta VMAIN
   
    ldx #VRAM_TILES_LOC>>1 ; set dest VRAM address
    stx VMADDL
    ldx #0               ; source offset
-
    lda @l font_data, x
    sta VMDATAL
    inx
    inx
    cpx #(font_data_end - font_data)
    bne -

    ldx #VRAM_TILES2_LOC>>1 ; set dest VRAM address
    stx VMADDL
    ldx #0
-
    lda @l font2_data, x
    sta VMDATAL
    inx
    inx
    cpx #(font2_data_end - font2_data)
    bne -

    plp
    rts

clear_vram:
    pha
    phx
    php

    a8

    lda #$80
    sta $2115         ;Set VRAM port to.word access
    ldx #$1809
    stx $4300         ;Set DMA mode to fixed source,.word to $2118/9
    ldx #$0000
    stx $2116         ;Set VRAM port address to $0000
    stx $0000         ;Set $00:0000 to $0000 (assumes scratchpad ram)
    stx $4302         ;Set source address to $xx:0000
    lda #$00
    sta $4304         ;Set source bank to $00
    ldx #$FFFF
    stx $4305         ;Set transfer size to 64k-1.bytes
    lda #$01
    sta $420b         ;Initiate transfer

    stz $2119         ;clear the last.byte of the VRAM

    plp
    plx
    pla
    rts

exit_cop_e:


brk_e_entry:
abt_e_entry:
int_e_entry:
    rti

nmi_n_entry:
    a16i16
    pha
    jsr nmi_handler
    pla
return_int:
    rti

nmi_e_entry:
    clc
    xce             ; out of emulation mode

    a16i16
    pha
    jsr nmi_handler
    pla

    jml $7eff00     ; run the sec/sce/rti instructions from bank 7e

; --- Keyboard handling -----------------------------------------------------

init_keyboard:
    php
    a8

    lda #0
    sta pending_key
    sta modifier_state

    ldx #keyboard_init_data1
    jsr write_keyboard_init_data
    jsr wait
    ldx #keyboard_init_data2
    jsr write_keyboard_init_data
    jsr wait

    plp
    rts

get_current_key:
.block
    phb
    php
    a8i8

    .databank $7f
    lda #$7f
    pha
    plb

    lda pending_key
    bne exit

    ; Block and wait for a scancode from the keyboard.

    lda SCC_A_CTRL      ; shortcut to reading register 0
    lsr a               ; Rx bit into carry
    bcc exit_nokey

    lda SCC_A_DATA      ; shortcut to reading data register

    cmp #$70
    beq shift_mod_down
    cmp #$70 | $80
    beq shift_mod_up
    cmp #$74
    beq ctrl_mod_down
    cmp #$74 | $80
    beq ctrl_mod_up
    bit #$80            ; keyup?
    bne exit_nokey      ; ignore.

    ; Got one.

    tax
    lda keymap_normal, x
    bit modifier_state
    bpl +
    lda keymap_shift, x
+
    bit modifier_state
    bvc +
    and #$1f
+
    sta pending_key
exit:
    plp
    plb
    rts

shift_mod_down:
    lda #MOD_SHIFT
    bra set_mod
ctrl_mod_down:
    lda #MOD_CTRL
set_mod:
    tsb modifier_state
    bra exit_nokey

shift_mod_up:
    lda #MOD_SHIFT
    bra clr_mod
ctrl_mod_up:
    lda #MOD_CTRL
clr_mod:
    trb modifier_state
exit_nokey:
    lda #0
    bra exit

keymap_normal:
    .byte $1B, $31, $32, $33, $34, $35, $36, $37 ; $00
    .byte $38, $39, $30, $2D, $5E, $5C, $08, $09
    .byte $71, $77, $65, $72, $74, $79, $75, $69 ; $10
    .byte $6F, $70, $40, $5B, $0D, $61, $73, $64
    .byte $66, $67, $68, $6A, $6B, $6C, $3B, $3A ; $20
    .byte $5D, $7A, $78, $63, $76, $62, $6E, $6D
    .byte $2C, $2E, $2F, $00, $20, $0E, $13, $14 ; $30
    .byte $12, $7F, $8b, $88, $89, $8a, $0C, $01
    .byte $2D, $2F, $37, $38, $39, $2A, $34, $35 ; $40
    .byte $36, $2B, $31, $32, $33, $3D, $30, $2C
    .byte $2E, $0F, $00, $00, $00, $00, $00, $00 ; $50
    .byte $00, $00, $00, $00, $00, $00, $00, $00
    .byte $03, $02, $00, $00, $00, $00, $00, $00 ; $60
    .byte $00, $00, $00, $00, $00, $00, $00, $00
keymap_shift:
    .byte $1B, $21, $22, $23, $24, $25, $26, $27 ; $00
    .byte $28, $29, $00, $3D, $60, $7C, $08, $09
    .byte $51, $57, $45, $52, $54, $59, $55, $49 ; $10
    .byte $4F, $50, $7E, $7B, $0D, $41, $53, $44
    .byte $46, $47, $48, $4A, $4B, $4C, $2B, $2A ; $20
    .byte $7D, $5A, $58, $43, $56, $42, $4E, $4D
    .byte $3C, $3E, $3F, $5F, $20, $0E, $13, $14 ; $30
    .byte $12, $7F, $8b, $88, $89, $8a, $0B, $01
    .byte $2D, $2F, $37, $38, $39, $2A, $34, $35 ; $40
    .byte $36, $2B, $31, $32, $33, $3D, $30, $2C
    .byte $2E, $0F, $00, $00, $00, $00, $00, $00 ; $50
    .byte $00, $00, $00, $00, $00, $00, $00, $00
    .byte $18, $02, $00, $00, $00, $00, $00, $00 ; $60
    .byte $00, $00, $00, $00, $00, $00, $00, $00

    .databank ?
.endblock

write_keyboard_init_data:
-
    lda 0, x
    bmi +
    sta SCC_A_CTRL
    inx
    lda 0, x
    sta SCC_A_CTRL
    inx
    bra -
+
    rts

wait:
    php
    a16
    lda #$9000
-
    dec a
    bne -
    plp
    rts

keyboard_init_data1:
    .byte $09, %10000000 ; Reset SCC channel A
    .byte $0e, %00000000 ; Stop baudrate generator
    .byte $01, %00000000 ; Disable interrupt
    .byte $03, %11000000 ; Disable serial input
    .byte $05, %01100010 ; Disable serial output
    .byte $0f, %00000000 ; Disable all status interrupts
    .byte $00, %00010000 ; Reset status interrupt
    .byte $00, %00010000 ; Reset status interrupt
    .byte $04, %01000101 ; Set StopBit-1,NonParity
    .byte $0b, %11010100 ; Set clock mode
    .byte $ff

keyboard_init_data2:
    .byte $0c, %00000110 ; Set baurate status low
    .byte $0d, %00000000 ; Set baurate status high
    .byte $0e, %00000001 ; start Baudrate generator
    .byte $05, %11101000 ; Enable serial output DTR=L,RTS=H
    .byte $03, %11000001 ; Enable serial input
    .byte $ff
    
; ===========================================================================
;                                    DRIVERS
; ===========================================================================

driver_handler .macro jt
    php
    phb
    phd
    a8i8

    xba             ; assemble XA into a 16-bit A parameter
    txa
    xba

    pha
    tya
    asl a
    tax

    lda #$7f        ; databank to $7f0000 so we can read supervisor RAM
    pha
    plb
    pea #$2100      ; direct page to $2100 so we can write to video registers
    pld

    pla
    jsr (\jt, x)

    pld
    plb
    bcs +
    plp
    clc
    rtl
+
    plp
    sec
    rtl
.endmacro

; --- SCREEN driver ---------------------------------------------------------

.databank $7f
.dpage $2100

screen_handler:
    driver_handler screen_driver_table

screen_driver_table:
    .word screen_version
    .word screen_getsize
    .word screen_clear
    .word screen_setcursor
    .word screen_getcursor
    .word screen_putchar
    .word screen_putstring
    .word screen_getchar
    .word screen_showcursor
    .word screen_scrollup
    .word screen_scrolldown
    .word screen_cleartoeol
    .word screen_setstyle

fail:
    sec
    rts

.as
.xs
screen_version:
    lda #0
    clc
    rts

.as
.xs
screen_getsize:
    lda #SCREEN_WIDTH-1
    ldx #SCREEN_HEIGHT-1
    clc
    rts

screen_clear:
    php

    a16i16
    lda #0
    sta cursorp

    lda style_word
    sta map1_mirror
    sta map2_mirror

    lda #SCREEN_WIDTH*SCREEN_HEIGHT*2/2 - 3
    ldx #<>map1_mirror
    ldy #<>map1_mirror + 2
    mvn #`map1_mirror, #`map1_mirror

    lda #SCREEN_WIDTH*SCREEN_HEIGHT*2/2 - 3
    ldx #<>map2_mirror
    ldy #<>map2_mirror + 2
    mvn #`map2_mirror, #`map2_mirror

    plp
    rts

.as
.xs
screen_setcursor:
    sta ptr
    a16
    and #$ff00
    lsr a
    lsr a
    a8
    ora ptr
    a16
    sta cursorp
    rts

.as
.xs
screen_getcursor:
    lda cursorp
    and #SCREEN_WIDTH-1
    pha

    a16
    lda cursorp
    asl a
    asl a
    a8

    xba
    tax
    pla
    rts

.as
.xs
screen_getchar:
    jsr get_current_key
    tax                 ; set flags
    bne +
        sec
        rts
    +

    stz pending_key

    clc
    rts

.as
.xs
screen_showcursor:
    pha
    lda #CURSOR_SHOWN
    trb screen_flags
    plx                 ; sets Z flag
    beq +
    tsb screen_flags
+
    rts

; Calculates the address relative to map1_mirror.

calculate_screen_address:
.block
    php
    a16

    lda @l cursorp      ; long address to make independent of databank
    lsr a
    bcs +
        ; clc ; carry clear from previous instruction
        adc #(map2_mirror - map1_mirror) >> 1
    +
    asl a

    plp
    rts
.endblock

.as
.xs
screen_putchar:
    php
    a16i16
    pha

    jsr calculate_screen_address
    tax

    pla
    sec
    sbc #$0020              ; convert to tile number
    asl a                   ; tiles come in pairs
    and #$00ff
    ora style_word          ; priority bit and palette
    sta map1_mirror, x

    inc cursorp

    plp
    rts

.as
.xs
screen_putstring:
    php
    a16i16
    tax

    lda cursorp
    pha

    -
        jsr calculate_screen_address
        inc cursorp
        tay

        a8
        lda $7e0000, x
        a16
        beq +
        sec
        sbc #$0020              ; convert to tile number
        asl a                   ; tiles come in pairs
        and #$00ff
        ora style_word          ; priority bit and palette
        sta map1_mirror, y
        inx
        bra -
    +

    pla
    sta cursorp

    plp
    rts

.as
.xs
screen_scrollup:
    php
    a16i16
    phb

    ; Actually do the scroll.

    lda #(SCREEN_HEIGHT-1)*32*2 - 1
    ldx #<>(map1_mirror + 1*32*2)
    ldy #<>(map1_mirror + 0*32*2)
    mvn #`map1_mirror, #`map1_mirror

    lda #(SCREEN_HEIGHT-1)*32*2 - 1
    ldx #<>(map2_mirror + 1*32*2)
    ldy #<>(map2_mirror + 0*32*2)
    mvn #`map2_mirror, #`map2_mirror

    ; Blank the bottom line.

    lda style_word
    sta map1_mirror + (SCREEN_HEIGHT-1)*32*2
    sta map2_mirror + (SCREEN_HEIGHT-1)*32*2

    lda #(SCREEN_WIDTH*2) - 3
    ldx #<>(map1_mirror + (SCREEN_HEIGHT-1)*32*2)
    ldy #<>(map1_mirror + (SCREEN_HEIGHT-1)*32*2 + 2)
    mvn #`map1_mirror, #`map1_mirror

    lda #(SCREEN_WIDTH*2) - 3
    ldx #<>(map2_mirror + (SCREEN_HEIGHT-1)*32*2)
    ldy #<>(map2_mirror + (SCREEN_HEIGHT-1)*32*2 + 2)
    mvn #`map2_mirror, #`map2_mirror

    plb
    plp
    rts

.as
.xs
screen_scrolldown:
    php
    a16i16
    phb

    ; Actually do the scroll.

    lda #(SCREEN_HEIGHT-1)*32*2 - 1
    ldx #<>(map1_mirror + (SCREEN_HEIGHT-2)*32*2)
    ldy #<>(map1_mirror + (SCREEN_HEIGHT-1)*32*2)
    mvp #`map1_mirror, #`map1_mirror

    lda #(SCREEN_HEIGHT-1)*32*2 - 1
    ldx #<>(map2_mirror + (SCREEN_HEIGHT-2)*32*2)
    ldy #<>(map2_mirror + (SCREEN_HEIGHT-1)*32*2)
    mvp #`map2_mirror, #`map2_mirror

    ; Blank the top line.

    lda style_word
    sta map1_mirror
    sta map2_mirror

    lda #(SCREEN_WIDTH*2/2) - 3
    ldx #<>map1_mirror
    ldy #<>(map1_mirror + 2)
    mvn #`map1_mirror, #`map1_mirror

    lda #(SCREEN_WIDTH*2/2) - 3
    ldx #<>map2_mirror
    ldy #<>(map2_mirror + 2)
    mvn #`map2_mirror, #`map2_mirror

    plb
    plp
    rts

.as
.xs
screen_cleartoeol:
    php
    a16i16

    lda cursorp
    pha

    -
        jsr calculate_screen_address
        tax

        lda style_word
        sta map1_mirror, x

        inc cursorp
        lda cursorp
        and #63
        bne -
    
    pla
    sta cursorp
    plp
    rts

.as
.xs
screen_setstyle:
    ldx #$20
    and #STYLE_REVERSE
    beq +
        ldx #$24
    +
    stx style_byte
    rts

nmi_handler:
.block
    phx
    phy
    phd
    phb

    a16i16
    phk
    plb             ; databank to 0 so we can read/write registers
    pea #$4300      ; direct page to $4300 for fast access to DMA registers
    pld
    .databank 0
    .dpage $4300

    a8
    lda RDNMI       ; reset NMI flag

    lda #%10000000       ; force blank
    sta INIDISP

    lda #%10000000       ; autoincrement by one word
    sta VMAIN
   
    ; DMA the tilemaps.

    lda #%00000001      ; CPU->PPU, no HDMA, two registers write once,
    sta DMAPx + $70
    lda #<VMDATAL       ; destination address
    sta BBADx + $70
    lda #`map1_mirror   ; source bank
    ldx #<>map1_mirror  ; source address
    sta A1Bx + $70
    stx A1TxL + $70
    ldx #vram_mirror_end - vram_mirror_start
    stx DASxL + $70     ; number of bytes to transfer
    ldx #VRAM_MAP1_LOC>>1 ; word address
    stx VMADDL          ; destination VRAM address
    lda #%10000000      ; DMA enable
    sta MDMAEN

    lda tick_counter
    inc a
    sta tick_counter
    and #64
    beq +
    lda screen_flags
    bpl +
        a16
        jsr calculate_screen_address
        lsr a
        sta VMADDL
        asl a
        tax
        lda map1_mirror, x
        eor #$0400
        sta VMDATAL
    +

    a8
    lda #%00001111      ; screen on, maximum brightness
    sta INIDISP

    a16i16
    plb
    pld
    ply
    plx
    rts
.endblock

.databank ?
.dpage ?

; --- TTY driver ------------------------------------------------------------

.databank $7f
.dpage $2100

tty_handler:
    driver_handler tty_driver_table

tty_driver_table:
    .word tty_const
    .word tty_conin
    .word tty_conout

; Returns 0xff if no key is pending, 0 if one is.

tty_const:
    jsr get_current_key
    ldx #0
    cmp #0
    beq +
    dex
+
    txa
    
    clc
    rts

; Blocks and waits for a keypress.

.as
.xs
tty_conin:
    -
        jsr screen_getchar
        bcs -
    rts

tty_conout:
.block
    php
    i8
    a16

    tax
    cpx #13
    bne +
        lda #63
        trb cursorp
        bra exit
    +
    cpx #127
    bne +
        dec cursorp

        a16i16
        jsr calculate_screen_address
        tax
        stz map1_mirror, x
        i8

        bra exit
    +
    cpx #10
    bne +
        lda cursorp
        and #$ffc0
        clc
        adc #64
        sta cursorp
        bra maybescroll
    +

    i16
    jsr screen_putchar

    lda cursorp
maybescroll:
    cmp #SCREEN_WIDTH * SCREEN_HEIGHT
    bne +
        jsr screen_scrollup
        lda #SCREEN_WIDTH * (SCREEN_HEIGHT-1)
        sta cursorp
    +

exit:
    plp
    clc
    rts
.endblock

.databank ?
.dpage ?

; --- I/O handling ----------------------------------------------------------

bios_setdma:
    phx
    pha
    rep #$30        ; A/X/Y 16-bit

    pla             ; pop address as a 16-bit value
    sta dma

    rtl

bios_setsec:
    phx
    pha
    rep #$30        ; A/X/Y 16-bit

    plx             ; pop address as a 16-bit value
    lda 0,b,x       ; get bottom two bytes of sector number
    sta sector+0
    a8
    lda 2,b,x       ; get top byte of sector number
    sta sector+2

    rtl

bios_read:
    rep #$30        ; A/X/Y 16-bit

    ; Compute the address in the romdisk.

    lda sector+0    ; bottom two bytes of sector number
    lsr a
    clc
    adc #$4100      ; patch in address of ROMdisk
    sta ptr+1, d    ; top two bytes of address
    a8
    lda sector+0
    ror a
    lda #0
    ror a
    sta ptr+0, d    ; bottom byte of address

    ldy #$7f
-
    lda [ptr, d], y
    sta [dma, d], y
    dey
    bpl -

    clc
    rtl


; --- Jump table ------------------------------------------------------------

; This must be kept in sync with the values in globals.inc.

    * = $ff00
    jmp *               ; seldsk
    jmp bios_setdma
    jmp bios_setsec
    jmp bios_read
    jmp *               ; write
    jmp tty_handler
    jmp screen_handler

; --- ROM header ------------------------------------------------------------

    * = $ffc0

    ;      012345678901234567890
    .text 'CP/M-65 SNES         '
    .byte %00110001     ; fast, HiROM
    .byte $02           ; ROM + RAM + battery
    .byte 9              ; ROM size: 512kB
    .byte 5              ; RAM size: 32kB
    .byte 0              ; country
    .byte 0              ; developer ID
    .byte 0              ; version
    .word 0              ; checksum complement (filled in later)
    .word 0              ; checksum (filled in later)

    ; Native mode vectors

    .word $ffff         ; reserved
    .word $ffff         ; reserved
    .word return_int     ; COP
    .word return_int     ; BRK
    .word return_int     ; ABT
    .word nmi_n_entry    ; NMI
    .word $ffff         ; reserved
    .word return_int     ; IRQ

     ; Emulation mode vectors

    .word $ffff         ; reserved
    .word $ffff         ; reserved
    .word return_int    ; COP
    .word brk_e_entry
    .word return_int    ; ABT
    .word nmi_e_entry   ; NMI
    .word start         ; reserved
    .word int_e_entry   ; IRQ

* = $010000
.binary "+diskimage.img"

; vim: sw=4 ts=4 et
