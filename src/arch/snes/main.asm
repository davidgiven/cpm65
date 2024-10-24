.cpu "65816"
.enc "ascii"
.cdef " ~", 32
.include "snes.inc"

VRAM_CHARSET   = $0000 ; must be at $1000 boundary
VRAM_BG1       = $1000 ; must be at $0400 boundary
VRAM_BG2       = $1400 ; must be at $0400 boundary
VRAM_BG3       = $1800 ; must be at $0400 boundary
VRAM_BG4       = $1C00 ; must be at $0400 boundary
START_X        = 9
START_Y        = 14
START_TM_ADDR  = VRAM_BG1 + 32*START_Y + START_X

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

loop:
    stz INIDISP,x
    stz NMITIMEN,x
    dex
    bpl loop

   lda #128
   sta INIDISP ; undo the accidental stz to 2100h due to BPL actually being a branch on nonnegative

   ; Set palette to black background and 3 shades of red
   stz CGADD ; start with color 0 (background)
   stz CGDATA ; None more black
   stz CGDATA
   lda #$10 ; Color 1: dark red
   sta CGDATA
   stz CGDATA
   lda #$1F ; Color 2: neutral red
   sta CGDATA
   stz CGDATA
   lda #$1F  ; Color 3: light red
   sta CGDATA
   lda #$42
   sta CGDATA

   ; Setup Graphics Mode 0, 8x8 tiles all layers
   stz BGMODE
   lda #>VRAM_BG1
   sta BG1SC ; BG1 at VRAM_BG1, only single 32x32 map (4-way mirror)
   lda #((>VRAM_CHARSET >> 4) | (>VRAM_CHARSET & $f0))
   sta BG12NBA ; BG 1 and 2 both use char tiles

   ; Load character set into VRAM
   lda #$80
   sta VMAIN   ; VRAM stride of 1.word
   ldx #VRAM_CHARSET
   stx VMADDL
   ldx #0
charset_loop:
   lda NESfont,x
   stz VMDATAL ; color index low bit = 0
   sta VMDATAH ; color index high bit set -> neutral red (2)
   inx
   cpx #(128*8)
   bne charset_loop

   ; Place string tiles in background
   ldx #START_TM_ADDR
   stx VMADDL
   ldx #0
string_loop:
   lda hello_str,x
   beq enable_display
   sta VMDATAL
   lda #$20 ; priority 1
   sta VMDATAH
   inx
   bra string_loop

enable_display:
   ; Show BG1
   lda #$01
   sta TM
   ; Maximum screen brightness
   lda #$0F
   sta INIDISP

   ; enable NMI for Vertical Blank
   lda #$80
   sta NMITIMEN

game_loop:
   wai ; Pause until next interrupt complete (i.e. V-blank processing is done)
   ; Do something
   jmp game_loop


    rts

hello_str:
   .text "Hello, World!"
   .byte 0

clear_vram:
   pha
   phx
   php

   mem8
   idx16
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

.include "charset.inc"

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
