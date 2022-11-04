; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

EOL = $9B                       ; ATASCII EOL character

;   VECTOR TABLE
EDITRV = $E400                  ; Editor Vector
SCRENV = $E410                  ; Screen Vector
KEYBDV = $E420                  ; Keyboard Vector
CIOV   = $E456                  ; CIO Vector

RAMTOP = $026A
RAMSIZ = $02E4
MEMTOP = $02E5                  ; Top of available memory
MEMLO  = $02E7                  ; Bottom of available memory
COLOR1 = $2C5                   ; Foreground color (luminance)
COLOR2 = $2C6                   ; Foreground color (hue)
COLOR4 = $2C8                   ; Background color

PORTB  = $0301
BASICF = $03F8

ICHID  = $0340                  ; Hander identifier
ICDNO  = ICHID + 1              ; Device number
ICCOM  = ICHID + 2              ; Command
ICSTA  = ICHID + 3              ; Status
ICBAL  = ICHID + 4              ; Buffer address (low byte)
ICBAH  = ICHID + 5              ; Buffer address (high byte)
ICPTL  = ICHID + 6              ; Put address (low byte)
ICPTH  = ICHID + 7              ; Put address (high byte)
ICBLL  = ICHID + 8              ; Buffer length (low byte)
ICBLH  = ICHID + 9              ; Buffer length (high byte)
ICAX1  = ICHID + 10             ; Auxiliary information
ICAX2  = ICHID + 11             ; Auxiliary information

; IOCB Offsets
IOCB0  = $00
IOCB1  = $10
IOCB2  = $20
IOCB3  = $30
IOCB4  = $40
IOCB5  = $50
IOCB6  = $60
IOCB7  = $70


; CIO Commands
CIO_OPEN   = $03
CIO_CLOSE  = $0C
CIO_GET    = $07
CIO_PUT    = $09
CIO_INPUT  = $05
CIO_PRINT  = $09
CIO_STATUS = $0D

; CIO Directions
CIO_READ      = $04
CIO_WRITE     = $08
CIO_READWRITE = $0C

ZEROPAGE

.global ptr
ptr:    .word 0

zproc _start
    ldx #$ff
    txs

    ; Set screen color to white on black
    lda #0
    sta COLOR4                  ; Black background
    sta COLOR2                  ; Grey hue
    lda #$0F                    ; Highest luminance
    sta COLOR1

    ; Get an IOCB for the screen editor device
    ldx #0
    jsr get_free_iocb
    stx editor_iocb

    ; Load "E:" as the device name
    lda #<editor_device
    sta ICBAL,x
    lda #>editor_device
    sta ICBAH,x

    lda #CIO_OPEN
    sta ICCOM,x

    lda #CIO_WRITE
    sta ICAX1,x

    lda #0
    sta ICAX2,x

    sta ICBLH,x
    sta ICBLL,x

    jsr CIOV

    lda #>editor_device
    ldy #<editor_device

    jsr print


loop:
    jmp loop
zendproc

zproc init_system

zendproc


; Finds a free IOCB and returns it in X. Returns $ff if there are no fre IOCBs.
zproc get_free_iocb
    ldy #0

    zloop
        tya                     ; Calculate IOCB offset
        asl                     ; (y * 16)
        asl
        asl
        asl
        tax
        lda ICHID,x             ; Load the IOCB handler

        cmp #$ff                ;If the ID is $ff, it's available
        zif_eq
            rts
        zendif

        iny
        cmp #$07
        zif_eq
            ldx #$ff            ; All channels are taken.
            rts
        zendif
    zendloop
zendproc

zproc print
    ldx editor_iocb

    sta ICBAH,x
    tya
    sta ICBAL,x

    lda #CIO_PRINT
    sta ICCOM,x

    lda #0
    sta ICBLL,x
    lda #$ff
    sta ICBLH,x

    jsr CIOV
    rts
zendproc

zproc disable_basic
    lda #$c0
    cmp RAMTOP
    zif_ne
        sta RAMTOP              ; Set RAMTOP to the end of BASIC
        sta RAMSIZ

        lda PORTB               ; Disable BASIC bit
        ora #$02
        sta PORTB

        lda #$01

    
    zendif

zendproc

    .data
zp_base:    .byte __USERZEROPAGE_START__
zp_end:     .byte __USERZEROPAGE_END__

editor_device:
    .byte $45, $3A, EOL         ; ATASCII for 'E:\n'

NOINIT

editor_iocb:    .byte 0         ; IOCB for screen editor
