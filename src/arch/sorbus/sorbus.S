; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"


; IO Register for Console Access

UART_CONFIG  = $DF0B; uart configuration register
UART_READ    = $DF0C; read from uart input
UART_RBUFSIZ = $DF0D; can be $00-$ef in normal operation
UART_WRITE   = $DF0E; write to uart output
UART_WBUFSIZ = $DF0F; can be $00-$7f in normal operation


; IO Register for Disk-Access.
; Write Sector LBA ( 128 Byte sectors ), Address of the DMA-buffer
; then trigger the read  ( write 0x55 to SECTOR_CMD_READ )
; or the           write ( write 0x44 to SECTOR_CMD_WRITE )
; DMA-adress and LBA will be auto-incremented, be aware to set them properly before trigger !

SECTOR_LBA_L = $DF70
SECTOR_LBA_H = $DF71

SECTOR_DMA_L = $DF72
SECTOR_DMA_H = $DF73

SECTOR_CMD_READ = $DF74
SECTOR_CMD_WRITE = $DF75

MEMBASE = $e800   ; Location of the BDOS

ZEROPAGE

.global ptr
.global ptr1
ptr:        .word 0
ptr1:       .word 0
dma:        .word 0    ; current DMA

1:
    .word 0
zproc _start
    jmp cold_start
signature:
    .byte 'S','B','C','2','3'   ; mark this as valid rom for sorbus

cold_start:
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

defdriver TTY, DRVID_TTY, drvstrat_TTY, drv_AUX
defdriver "AUX", DRVID_AUX, drvstrat_AUX, 0


; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    pha
    lda tty_jmptable_lo, y
    sta ptr+0
    lda tty_jmptable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

tty_jmptable_lo:
    .byte tty_const@mos16lo
    .byte tty_conin@mos16lo
    .byte tty_conout@mos16lo
tty_jmptable_hi:
    .byte tty_const@mos16hi
    .byte tty_conin@mos16hi
    .byte tty_conout@mos16hi
zendproc


; AUX driver strategy routine.
; Y=AUX opcode.
zproc drvstrat_AUX
    pha
    lda aux_jmptable_lo, y
    sta ptr+0
    lda aux_jmptable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

aux_jmptable_lo:
    .byte aux_in@mos16lo
    .byte aux_out@mos16lo
    .byte aux_open@mos16lo
    .byte aux_close@mos16lo
aux_jmptable_hi:
    .byte aux_in@mos16hi
    .byte aux_out@mos16hi
    .byte aux_open@mos16hi
    .byte aux_close@mos16hi
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

    cmp #$7f         ; Backspace
    zif_eq
        lda #8
    zendif

    clc
    rts
zendproc

zproc tty_conout
    cmp #$7f         ; Backspace
    zif_eq
        lda #8
        jsr CHROUT
        lda #32
        jsr CHROUT
        lda #8
    zendif
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

; Reads and writes the AUX channel
zproc aux_open    ; switch off cr/lf translation
    lda #$00
    sta UART_CONFIG
    rts
zendproc
zproc aux_close   ; switch on cr/lf translation
    lda #$01
    sta UART_CONFIG
    rts
zendproc

zproc aux_in   ; returns with carry set on timeout
    jmp GETIN
zendproc

zproc aux_out
    jsr CHROUT
    clc
    rts
zendproc

; Sets the current DMA address.

zproc entry_SETDMA
    sta dma+0
    stx dma+1
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
  ;  lda mem_base
  ;  ldx mem_end
  ;  jsr print_hex_number
  ;  txa
  ;  jsr print_hex_number
  ;  lda #'G'
  ;  jsr CHROUT
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc entry_SETTPA
    sta mem_base
    stx mem_end
  ;  jsr print_hex_number
  ;  txa
  ;  jsr print_hex_number
  ;  lda #'S'
  ;  jsr CHROUT
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
    sec  ; ignoring the bank
    rts
zendproc

zproc entry_READ
    ;lda sector_num+1
    ;jsr print_hex_number
    ;lda sector_num+0
    ;jsr print_hex_number

    lda sector_num+0
    sta SECTOR_LBA_L
    lda sector_num+1
    sta SECTOR_LBA_H
    lda dma
    sta SECTOR_DMA_L
    lda dma+1
    sta SECTOR_DMA_H

    lda #$88        // iniate read with DMA
    sta SECTOR_CMD_READ
    clc
    rts
zendproc

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc entry_WRITE

    lda dma
    sta SECTOR_DMA_L
    lda dma+1
    sta SECTOR_DMA_H
    lda sector_num+0
    ldx sector_num+1
    stx SECTOR_LBA_H
    sta SECTOR_LBA_L
   ; pha
   ; txa
   ; jsr print_hex_number
   ; pla
   ; jsr print_hex_number
    lda #$44        // iniate write with DMA
    sta SECTOR_CMD_WRITE

    clc
    rts

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
    jsr initdrivers

    rts

loading_msg:
    .byte 13, 10
    .ascii "CP/M 65 for the Sorbus Computer V1.0"
    .byte 13, 10
    .ascii "ported by Benson and SvOlli of TRSI"
    .byte 10
    .ascii "original code by David Given"
    .byte 13, 10 , 0

zendproc


;-------------------------------------------------------------------------
;  Subroutine to print a character to the terminal
;-------------------------------------------------------------------------

zproc CHROUT
   bit   UART_WBUFSIZ
   bmi   CHROUT
   sta   UART_WRITE
   rts

zendproc

;-------------------------------------------------------------------------
;  Subroutine to fetch a character from the terminal
;-------------------------------------------------------------------------


zproc GETIN
    lda   UART_RBUFSIZ ; check input
    bne   read_key ; no input -> return 0
    sec
    rts

read_key:
    lda   UART_READ      ; get key
    clc
    rts

zendproc



.data

zp_base:    .byte __USERZEROPAGE_START__
zp_end:     .byte __USERZEROPAGE_END__


; Bank_Extra is from $e800 to $f000
; Bank_Main is from $0200 to $d000
; subtract $0f00 bytes, that bdos wants to map
; BDOS is already fixed at $e800
mem_base:   .byte  $02-$0f
mem_end:    .byte  $c0

; DPH for drive 0 (our only drive)

; drive parameters: total sectors, bytes per block, dir entries, boot sectors
define_drive dph, 32768, 2048, 1024, 256

NOINIT

pending_key:     .byte 0 ; pending keypress from system
sector_num:      .fill 3 ; current absolute sector number

.global directory_buffer
directory_buffer: .fill 128


; vim: sw=4 ts=4 et ft=asm

