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

.logical 0
cursor_addr:
    .word 0
.endlogical

* = $000000
.logical $400000
font_data:
   .binary "4bpp.bin"
font_data_end:
font2_data:
   .binary "2bpp.bin"
font2_data_end:
.endlogical

* = $008000
start:
    .autsiz
    clc
    xce
    rep #$10        ; X/Y 16-bit
    sep #$20        ; A 8-bit

    ; Clear registers
    ldx #$33
    jsr clear_vram
-
    stz INIDISP,x
    stz NMITIMEN,x
    dex
    bpl -

    ; Initialise the screen.

    lda #$80             ; screen off during initialisation
    sta INIDISP
    lda #5 | $00         ; mode 5, 16x8 tiles all layers
    sta BGMODE
    lda #%00001000       ; high res mode, interlacing off
    sta SETINI
    lda #(VRAM_MAP1_LOC >> 9) | %00 ; tilemap 1 address, 32x32
    sta BG1SC
    lda #(VRAM_MAP2_LOC >> 9) | %00 ; tilemap 2 address, 32x32
    sta BG2SC
    lda #((>VRAM_TILES_LOC >> 5) | ((>VRAM_TILES2_LOC >> 1) & $f0))
    sta BG12NBA
    lda #%00000011       ; main screen turn on: BG1 and BG2
    sta TM
    sta TS               ; ditto subscreen

    jsr load_font_data
    jsr load_palette_data
   
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

enable_display:
   ; Maximum screen brightness
   lda #$0F
   sta INIDISP

game_loop:
   wai ; Pause until next interrupt complete (i.e. V-blank processing is done)
   ; Do something
   jmp game_loop


    rts

putc:
    php
    rep #$30            ; A/X/Y 16 bit
    asl a
    and #$00ff
    ora #$2000
    pha

    lda cursor_addr
    bit #1
    beq +
    ora #VRAM_MAP2_LOC
+
    lsr a
    sta VMADDL

    pla
    sta VMDATAL

    inc cursor_addr

    plp
    rts

load_palette_data:
    php
    sep #$30             ; A/X/Y 8 bit
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
   rep #$30             ; A/X/Y 16 bit

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

    REP #$30		; mem/A = 8 bit, X/Y = 16 bit
    SEP #$20

    LDA #$80
    STA $2115         ;Set VRAM port to.word access
    LDX #$1809
    STX $4300         ;Set DMA mode to fixed source,.word to $2118/9
    LDX #$0000
    STX $2116         ;Set VRAM port address to $0000
    STX $0000         ;Set $00:0000 to $0000 (assumes scratchpad ram)
    STX $4302         ;Set source address to $xx:0000
    LDA #$00
    STA $4304         ;Set source bank to $00
    LDX #$FFFF
    STX $4305         ;Set transfer size to 64k-1.bytes
    LDA #$01
    sta $420b         ;Initiate transfer

    STZ $2119         ;clear the last.byte of the VRAM

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
