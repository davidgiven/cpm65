include snes.inc

main sect rel
bank0 group main

VRAM_CHARSET   equ 0x0000 ; must be at $1000 boundary
VRAM_BG1       equ 0x1000 ; must be at $0400 boundary
VRAM_BG2       equ 0x1400 ; must be at $0400 boundary
VRAM_BG3       equ 0x1800 ; must be at $0400 boundary
VRAM_BG4       equ 0x1C00 ; must be at $0400 boundary
START_X        equ 9
START_Y        equ 14
START_TM_ADDR  equ VRAM_BG1 + 32*START_Y + START_X

start:
    mem8
    idx16
    clc
    xce
    rep #0x10        ; X/Y 16-bit
    sep #0x20        ; A 8-bit

    ; Clear registers
    ldx #0x33
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
   lda #0x10 ; Color 1: dark red
   sta CGDATA
   stz CGDATA
   lda #0x1F ; Color 2: neutral red
   sta CGDATA
   stz CGDATA
   lda #0x1F  ; Color 3: light red
   sta CGDATA
   lda #0x42
   sta CGDATA

   ; Setup Graphics Mode 0, 8x8 tiles all layers
   stz BGMODE
   lda #high(VRAM_BG1)
   sta BG1SC ; BG1 at VRAM_BG1, only single 32x32 map (4-way mirror)
   lda #((high(VRAM_CHARSET) » 4) | (high(VRAM_CHARSET) & 0xf0))
   sta BG12NBA ; BG 1 and 2 both use char tiles

   ; Load character set into VRAM
   lda #0x80
   sta VMAIN   ; VRAM stride of 1 word
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
   lda #0x20 ; priority 1
   sta VMDATAH
   inx
   bra string_loop

enable_display:
   ; Show BG1
   lda #0x01
   sta TM
   ; Maximum screen brightness
   lda #0x0F
   sta INIDISP

   ; enable NMI for Vertical Blank
   lda #0x80
   sta NMITIMEN

game_loop:
   wai ; Pause until next interrupt complete (i.e. V-blank processing is done)
   ; Do something
   jmp game_loop


    rts

hello_str:
    ascii "Hello, World!"
    byte 0

clear_vram:
   pha
   phx
   php

   mem8
   idx16
   REP #0x30		; mem/A = 8 bit, X/Y = 16 bit
   SEP #0x20

   LDA #0x80
   STA 0x2115         ;Set VRAM port to word access
   LDX #0x1809
   STX 0x4300         ;Set DMA mode to fixed source, WORD to $2118/9
   LDX #0x0000
   STX 0x2116         ;Set VRAM port address to $0000
   STX 0x0000         ;Set $00:0000 to $0000 (assumes scratchpad ram)
   STX 0x4302         ;Set source address to $xx:0000
   LDA #0x00
   STA 0x4304         ;Set source bank to $00
   LDX #0xFFFF
   STX 0x4305         ;Set transfer size to 64k-1 bytes
   LDA #0x01
   sta 0x420b         ;Initiate transfer

   STZ 0x2119         ;clear the last byte of the VRAM

   plp
   plx
   pla
   RTS

include charset.inc

cop_e_entry:
brk_e_entry:
abt_e_entry:
int_e_entry:
    rti

nmi_n_entry:
   rep #0x10        ; X/Y 16-bit
   sep #0x20        ; A 8-bit
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

    org 0xffc0

    ;      012345678901234567890
    ascii 'CP/M-65 SNES         '
    byte 0b00110001     ; fast, HiROM
    byte 0x02           ; ROM + RAM + battery
    byte 9              ; ROM size: 512kB
    byte 5              ; RAM size: 32kB
    byte 0              ; country
    byte 0              ; developer ID
    byte 0              ; version
    word 0              ; checksum complement (filled in later)
    word 0              ; checksum (filled in later)

    ; Native mode vectors

    word 0xffff         ; reserved
    word 0xffff         ; reserved
    word return_int     ; COP
    word return_int     ; BRK
    word return_int     ; ABT
    word nmi_n_entry    ; NMI
    word 0xffff         ; reserved
    word return_int     ; IRQ

    ; Emulation mode vectors

    word 0xffff         ; reserved
    word 0xffff         ; reserved
    word return_int    ; COP
    word brk_e_entry
    word return_int     ; ABT
    word nmi_n_entry    ; NMI
    word start          ; reserved
    word int_e_entry    ; IRQ

    end
