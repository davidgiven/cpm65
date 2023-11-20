; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

CHROUT = $ff00
GETIN  = $ff03

SECTOR_LBA_L = $DF70
SECTOR_LBA_M = $DF71

SECTOR_CMD_READ = $DF74
SECTOR_CMD_WRITE = $DF75
SECTOR_DATA = $DF76

MEMBASE = $c000   ; Location of the BDOS

ZEROPAGE

.global ptr
.global ptr1
ptr:        .word 0
ptr1:       .word 0
dma:        .word 0    ; current DMA

1:
    .word 0
zproc _start
    ldx #$ff
    txs
    cld

    jsr init_system
  
    ; Relocate the BDOS.

    lda #>MEMBASE
    ldx zp_base
    jsr entry_RELOCATE

    ; Compute the entry address and jump.

    lda #>MEMBASE
    pha
    lda #COMHDR_ENTRY-1 ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump

zendproc

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

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
    zif_eq
        zrepeat
            jsr GETIN
            tax
        zuntil_ne
    zendif
    ldx #0
    stx pending_key

    cmp #20         ; DEL
    zif_eq
        lda #8
    zendif

    clc
    rts
zendproc

zproc tty_conout
    jsr CHROUT
    clc
    rts
zendproc

zproc tty_const
    lda pending_key
    zif_eq
        jsr GETIN
        sta pending_key
        zif_eq
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

zproc entry_SETDMA
    sta dma+0    
    stx dma+1
  ;  pha
  ;  txa
  ;  jsr print_hex_number
  ;  pla
  ;  jsr print_hex_number
  ;  lda #' '
  ;  jsr CHROUT
    clc
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc entry_SELDSK
    cmp #0
    zif_ne
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

zproc entry_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil_mi
    clc
    rts
zendproc

zproc entry_GETTPA
    ;lda mem_base
    ;ldx mem_end
    ;jsr print_hex_number
    ;txa 
    ;jsr print_hex_number
    ;lda #'G'
    ;jsr CHROUT
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc entry_SETTPA
  ;TODO make use of this 
    sta mem_base
    stx mem_end
   ; jsr print_hex_number
   ; txa 
   ; jsr print_hex_number
   ; lda #'S'
   ; jsr CHROUT
    clc
    rts
zendproc

zproc entry_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc
 
zproc entry_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc entry_SETBANK
    cmp #BANK_EXTRA  ; This is for BIOS and CCP
    zif_eq  
        ;lda mem_base    ; its from $e000 to $f000    
        lda #$e8
        sta mem_base
        ;lda mem_end    ; its from $e000 to $f000    
        lda #$f0
        sta mem_end
        clc
        rts
    zendif
    cmp #BANK_MAIN  ; This is executing COMs
    zif_eq  
        ;lda mem_base    ; its from $0200 to $c000    
        lda #$02
        sta mem_base
        ;lda mem_end    ; its from $0200 to $c000    
        lda #$c0
        sta mem_end
        clc
        rts
    zendif
      
    sec  ; unknown bank
    rts
zendproc

zproc entry_READ
    jsr change_sectors
    ldx #$00
    ldy #0
    zrepeat
        lda disk_buffer, x
        sta (dma), y
        iny
        inx
        cpy #$80
    zuntil_eq

    clc
    rts
zendproc

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc entry_WRITE
    pha
    jsr change_sectors

    ldx #$0 
    ldy #0
    zrepeat
        lda (dma), y
        sta disk_buffer, x
        iny
        inx
        cpy #$80
    zuntil_eq

    lda #$80
    sta buffer_dirty

    pla
    zif_ne
        jsr flush_buffered_sector
    zendif

    clc
    rts
zendproc

zproc change_sectors
    ; If the buffered sector is the one we want, just return.
    ;lda sector_num+1    
    ;jsr print_hex_number
    ;lda sector_num+0
    ;jsr print_hex_number

    lda sector_num+0
    cmp buffered_sector+0
    zif_eq
        lda sector_num+1
        cmp buffered_sector+1
        zif_eq
            lda sector_num+2
            cmp buffered_sector+2
            zif_eq
                rts
            zendif
        zendif
    zendif

    ; We need to change sectors. Flush the current one?

    jsr flush_buffered_sector

    ; Now read the new one.

    lda sector_num+0
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
   ; lda buffered_sector+1    
   ; jsr print_hex_number
   ; lda buffered_sector+0
   ; jsr print_hex_number

    ldx buffered_sector+1    
    lda buffered_sector+0
    rts
zendproc

; Flush the current buffer to disk, if necessary.

zproc flush_buffered_sector
    lda buffer_dirty
    zif_mi
        jsr buffered_sector_to_lba
        jsr write_sector

        lda #0
        sta buffer_dirty
    zendif
    rts
zendproc

; Reads a 256-byte sector whose LBA index is in XA.

zproc read_sector
    sta SECTOR_LBA_L
    stx SECTOR_LBA_M

    lda #$aa        // iniate read
    sta SECTOR_CMD_READ

    ldy #$00
    zrepeat
        lda SECTOR_DATA
        sta disk_buffer, y
        iny
        cpy #$80
    zuntil_eq

    rts
zendproc

; Writes a 256-byte sector whose LBA index is in XA.

zproc write_sector
   ; pha
   ; jsr print_hex_number
   ; pla
    sta SECTOR_LBA_L
    stx SECTOR_LBA_M
    lda #$55        // iniate write
    sta SECTOR_CMD_WRITE

    ldy #$00
    zrepeat
        lda disk_buffer, y
        sta SECTOR_DATA
        iny
        cpy #$80
    zuntil_eq


    rts


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
	zif_cs
		adc #6
	zendif
   	pha
	jsr CHROUT
	pla
	rts
zendproc



; Prints the string at XA with the kernel.

zproc print
    sta ptr+0
    stx ptr+1

    ldy #0
    zloop
        lda (ptr), y
        zbreakif_eq

        
        jsr CHROUT
        
        iny
    zendloop
    rts
zendproc

zproc init_system

    ; Clear memory here ?

    ; Print the startup banner (directly with CHROUT).

    ldy #0
    zloop
        lda loading_msg, y
        zbreakif_eq
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

    rts

zendproc

loading_msg:
    .byte 147, 14, 5
    .ascii "CP/M 65 for the Sorbus Computer"
    .byte 13, 10 , 0

.data

zp_base:    .byte __USERZEROPAGE_START__
zp_end:     .byte __USERZEROPAGE_END__

mem_base:   .byte $02
mem_end:    .byte $c0

; DPH for drive 0 (our only drive)

;define_drive dph, 136*10, 1024, 64, 0
define_drive dph,128*64, 2048, 128, 0

NOINIT

pending_key:     .byte 0 ; pending keypress from system
sector_num:      .fill 3 ; current absolute sector number
buffered_sector: .fill 3 ; sector currently in disk buffer
buffer_dirty:    .fill 1 ; non-zero if sector needs flushing

.global directory_buffer
directory_buffer: .fill 128
disk_buffer: .fill 256

; vim: sw=4 ts=4 et ft=asm

