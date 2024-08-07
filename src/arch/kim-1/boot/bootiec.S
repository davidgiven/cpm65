; CP/M-65 boot program for the KIM-1
; Copyright © 2024 Eduardo Casino
; 
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; IEC functions and definitions

FPRNMSG = %10000000     ; Display info messages
FPRNERR = %01000000     ; Display error messages

#ifdef PAL_1
SEINIT  = $da00
SETVRCK = $da0c
SETSA   = $da15
SETMSGF = $da1b
FREAD   = $da27
TALK    = $dcfe
LISTN   = $dd01
SECND   = $ddaa
TKSA    = $ddb9
CIOUT   = $ddce
UNTLK   = $dde3
UNLSN   = $ddf2
ACPTR   = $de07
#else
SEINIT  = $f000
SETVRCK = $f00c
SETSA   = $f015
SETMSGF = $f01b
FREAD   = $f027
TALK    = $f2fe
LISTN   = $f301
SECND   = $f3aa
TKSA    = $f3b9
CIOUT   = $f3ce
UNTLK   = $f3e3
UNLSN   = $f3f2
ACPTR   = $f407
#endif

; KIM-1 ZP

SPUSER = $F2            ; Current stack pointer

; KIM-1 Variables

CNTH30 = $17f3
CNTL30 = $17f2

; KIM-1 vectors

NMIV = $17fa            ; Stop vector (STOP=1C00)
IRQV = $17fe            ; IRQ vector  (BRK=1C00)

; KIM-1 functions

INITS  = $1e88          ; Initialization for sigma
PRTBYT = $1e3b          ; print A as two hex digits
OUTCH  = $1ea0          ; print A to TTY
CRLF   = $1e2f          ; print CR/LF

.text

.global _start
_start:
    jmp do_start

    ; Reset entry point
rst:
    ldx #0xff
    txs
    stx SPUSER
    jsr INITS

    ; Source: KIM-1/650X USER NOTES, ISSUE #6, July 77
    ;
    ; BAUD      110     150     300     600     1200    1800    2400    4800    9600
    ; CNTH30    $02     $01     $00     $00      $00     $00     $00     $00     $00
    ; CNTL30    $85     $d8     $eb     $74      $38     $24     $1a     $06     $03

    ; Values for 9600 baud

    lda #$00
    sta CNTH30
    lda #$03
    sta CNTL30

do_start:
    cld

    ; Set interrupt vectors so we can return to the monitor

    lda #$1c
    sta NMIV+1
    sta IRQV+1

    lda #0
    sta NMIV+0
    sta IRQV+0

init:
    jsr SEINIT

    lda #0                  ; Not verifying
    jsr SETVRCK

    lda #FPRNMSG|FPRNERR    ; Print IEC messages and errors
    jsr SETMSGF

    lda #1                  ; Load starting from addr
    jsr SETSA               ; specified by the PRG header
    
    lda #3                  ; File length
    ldx #<filename
    ldy #>filename
    jsr FREAD

    bcs exit

    jmp $6000

exit:
    brk

filename:
    .ascii "CPM"