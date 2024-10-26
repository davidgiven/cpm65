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
VRAM_MAP2_LOC   =  $1000
VRAM_TILES_LOC  =  $2000
VRAM_TILES2_LOC =  $6000

LOADER_ADDRESS  = $7e8000

SCREEN_WIDTH    = 64
SCREEN_HEIGHT   = 32

MOD_SHIFT       = %10000000 ; n bit
MOD_CTRL        = %01000000 ; v bit
MOD_CAPS        = %00000100

.virtual $7f0000
cursor_addr:    .word 0
sector:         .long 0     ; 24 bits!
pending_key:    .byte 0
modifier_state: .byte 0
cursorp:        .word 0     ; character count from top left of screen
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
    clc
    xce
    rep #$30            ; A/X/Y 16-bit

    ldx #$01ff          ; 6502-compatible
    txs
    lda #0
    tad

    a8
    lda #$7e
    sta @l dma+2        ; top byte of DMA address

    ; Clear registers
    ldx #$33
    jsr clear_vram
-
    stz INIDISP,x
    stz NMITIMEN,x
    dex
    bpl -

    ; Initialise the screen.

    jsr blank_on
    jsr init_screen
    jsr load_font_data
    jsr load_palette_data
    jsr blank_off

    ; Other hardware.

    jsr init_keyboard
   
    jsr clear_screen

    ; Copy the BIOS loader to its final position.

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

    sec
    xce                     ; enable emulation mode...
    jml LOADER_ADDRESS      ; ...and go

init_screen
    php
    a8

    lda #5 | $00            ; mode 5, 16x8 tiles all layers
    sta BGMODE
    lda #%00001000          ; high res mode, interlacing off
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

    plp
    rts

blank_on:
    php
    a8

    lda #%10000000          ; force blank
    sta INIDISP

    plp
    rts

blank_off:
    php
    a8

    lda #%00001111          ; blank off, maximum brightness
    sta INIDISP

    plp
    rts

wait_for_vblank:
    php
    a8 

-
    lda HVBJOY
    and #%10000000          ; test for v-blank flag
    beq -

    plp
    rts

clear_screen:
    php

    a16
    lda #0
    sta cursor_addr
    sta cursorp

    plp
    rts

load_palette_data:
    php
    a8

    stz CGADD

    stz CGDATA
    stz CGDATA
    lda #$ff
    sta CGDATA
    sta CGDATA

    plp
    rts

load_font_data:
    php
    a16

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
    rep #$10        ; X/Y 16-bit
    sep #$20        ; A 8-bit
    phd
    pha
    phx
    phy
    ; Do stuff that needs to be done during V-Blank
    lda RDNMI ; reset NMI flag
    ply
    plx
    pla
    pld
return_int:
    rti

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
    .byte $12, $7F, $1E, $1D, $1C, $1F, $0C, $01
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
    .byte $12, $7F, $1E, $1D, $1C, $1F, $0B, $01
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
    
; --- SCREEN driver ---------------------------------------------------------

.databank $7f
.dpage $2100

screen_handler:
    rtl

screen_putchar:
    php
    a16
    pha

    lda cursorp
    lsr a
    bcs +
        ora #(VRAM_MAP2_LOC >> 1) ; remember, we're working with word addresses
    +
    tax

    a8
    -
        lda HVBJOY
        and #%10000000      ; test for v-blank flag
        beq -
    a16

    stx VMADDL

    pla
    sec
    sbc #$0020              ; convert to tile number
    asl a                   ; tiles come in pairs
    and #$00ff
    ora #$2000              ; priority bit and palette
    sta VMDATAL

    plp
    rts

.databank ?
.dpage ?

; --- TTY driver ------------------------------------------------------------

.databank $7f
.dpage $2100

tty_handler:
    php
    clc
    xce             ; switch to native mode
    phb
    phd
    a8i8

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
    jsr (tty_driver_table, x)

    pld
    plb
    sec
    xce             ; return to emulation mode
    plp
    rtl

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

tty_conin:
-
    jsr get_current_key
    cmp #0
    beq -

    pha
    lda #0
    sta pending_key
    pla

    clc
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
        ; TODO: blank erased character
        bra exit
    +
    cpx #10
    bne +
        lda cursorp
        and #$ffc0
        clc
        adc #64
        sta cursorp
        bra exit
    +

    i16
    jsr screen_putchar

    inc cursorp
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
    clc
    xce             ; switch to native mode
    rep #$30        ; A/X/Y 16-bit

    pla             ; pop address as a 16-bit value
    sta dma

    sec
    xce             ; back to emulation mode
    rtl

bios_setsec:
    phx
    pha
    clc
    xce             ; switch to native mode
    rep #$30        ; A/X/Y 16-bit

    plx             ; pop address as a 16-bit value
    lda 0,b,x       ; get bottom two bytes of sector number
    sta sector+0
    a8
    lda 2,b,x       ; get top byte of sector number
    sta sector+2

    sec
    xce             ; back to emulation mode
    rtl

bios_read:
    xce             ; switch to native mode
    rep #$30        ; A/X/Y 16-bit

    ; Compute the address in the romdisk.

    lda sector+0    ; bottom two bytes of sector number
    lsr a
    ora #$4100      ; patch in address of ROMdisk
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

    sec
    xce             ; back to emulation mode
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
    .word nmi_n_entry   ; NMI
    .word start         ; reserved
    .word int_e_entry   ; IRQ

* = $010000
.binary "+diskimage.img"
