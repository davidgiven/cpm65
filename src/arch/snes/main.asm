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

VRAM_MAP1_LOC    =  $0000
VRAM_MAP2_LOC    =  $1000
VRAM_TILES_LOC   =  $2000
VRAM_TILES2_LOC  =  $6000

.virtual $7f0000
cursor_addr:
    .word 0
.endvirtual

.dpage ?                ; Reserve $0000-$00ff for user programs

* = $000000
.logical $400000
font_data:
   .binary "4bpp.bin"
font_data_end:
font2_data:
   .binary "2bpp.bin"
font2_data_end:
.endlogical

a16 .macro
    rep #$20
.endmacro

a8 .macro
    sep #$20
.endmacro

* = $008000
start:
    .autsiz
    clc
    xce
    rep #$30            ; A/X/Y 16-bit

    ldx #$01ff          ; 6502-compatible
    txs

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
   
    jsr clear_screen

    lda #1
    jsr putc
    lda #2
    jsr putc
    lda #3
    jsr putc
    lda #4
    jsr putc
    lda #5
    jsr putc
    lda #6
    jsr putc

game_loop:
   wai ; Pause until next interrupt complete (i.e. V-blank processing is done)
   ; Do something
   jmp game_loop


    rts

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

    plp
    rts

putc:
    php
    a16

    asl a
    and #$00ff
    ora #$2000
    pha

    jsr wait_for_vblank

    lda cursor_addr
    bit #1
    beq +
    ora #VRAM_MAP2_LOC
+
    lsr a
    sta VMADDL

    pla
    sta VMDATAL

    lda cursor_addr
    inc a
    sta cursor_addr

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
    RTS

cop_e_entry:
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
    .word return_int     ; ABT
    .word nmi_n_entry    ; NMI
    .word start          ; reserved
    .word int_e_entry    ; IRQ

* = $010000
.binary "+diskimage.img"
