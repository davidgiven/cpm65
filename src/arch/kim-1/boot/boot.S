; CP/M-65 boot program for the KIM-1
; Copyright © 2024 Eduardo Casino
; 
; K-1013 code heavily based on MTU's documentation and actual code
;
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 vectors

NMIV = $17fa            ; Stop vector (STOP=1C00)
IRQV = $17fe            ; IRQ vector  (BRK=1C00)

; KIM-1 functions

PRTBYT = $1e3b          ; print A as two hex digits
OUTCH  = $1ea0          ; print A to TTY
CRLF   = $1e2f          ; print CR/LF


; K-1013 FDC registers

HSRC = $ffe8            ; R/W   - K-1003 Hardware Status Register
ADMA = $ffea            ; Write - K-1013 Set DMA Address Register
MSTR = $ffee            ; Read  - uPD765 Main Status Register 
DATR = $ffef            ; R/W   - uPD765 Data Register

; uPD765 command index

SPECIFY =   0
RECAL   =   recastr - specstr
SENSE   =   sensstr - specstr
READ    =   readstr - specstr

.section .zp, "zax", @nobits

scrtch: .fill 9         ; Scratch RAM, Result phase readouts from NEC-765
errorc: .fill 1

.text

.global _start
_start:
    cld

    ; Set interrupt vectors so we can return to the monitor

    lda #$1c
    sta NMIV+1
    sta IRQV+1

    lda #0
    sta NMIV+0
    sta IRQV+0

    ; Init the error code variable

    sta errorc

    lda HSRC            ; Read Hardware Status Register
    bmi init            ; Jump if no interrupt is pending
    jsr srvint          ; Serve interrupt

init:
    ; Set the drive in known status

    ldx #SPECIFY        ; Establish disk operating parameters
    jsr cmdexec
    ldx #RECAL          ; Retract head of drive 0 to track 0
    jsr cmdexec
    jsr wsrvint         ; Wait for and service interrupt
    lda scrtch          ; Load result into accumulator
    and #$D8            ; 11 0 1 1000
                        ; ||   | |
                        ; ||   | +-> Not Ready
                        ; ||   +---> Track 0 signal fails
                        ; ++-------> Abnormal termination
    bne e1              ; Return to monitor with error if anything goes wrong

    ; Read 8 sectors from drive 0, track 0, starting at 0 into location $c000
    
    lda #$00            ; Dest address is $C000 (See section 2.1.4 of the K-1013 manual)
    sta ADMA            ; Set destination address to the DMA access register

    ldx #$01            ; Set DMA direction bit to write
    stx HSRC          

    ldx #READ           ; Execute read
    jsr cmdexec
1:  lda HSRC            ; Wait for command completion
    bmi 1b
    jsr readres         ; And read result
                        ; Check ST1 directly, as EOC will give an abnormal termination
    lda scrtch+1        ; Get status register 1
    and #$B7            ; 1 0 11 0 111
                        ; |   ||   |||
                        ; |   ||   ||+-> Missing address
                        ; |   ||   |+--> Not writable
                        ; |   ||   +---> Read deleted data
                        ; |   |+-------> Overrun
                        ; |   +--------> CRC error
                        ; +------------> End of cylinder
    cmp #$80            ; If status is "End of cylinder", all good 
    bne e2              ; Otherwise, return error

    jmp $c000


; Execute uPD765 command string

cmdexec:
    ldy cmdstrs, x      ; Command length to register Y

1:  inx
    lda cmdstrs, x      ; Load command byte
    jsr waitrdy         ; Wait for controller ready
    sta DATR            ; Send command byte
    dey                 ; Loop until last command byte
    bne 1b
    rts

waitrdy:
    bit MSTR            ; Check if bit os the status register is 1 (Data ready)
    bpl waitrdy         ; Loop if not
    rts

; Wait until interrupt and... 

wsrvint:
    lda HSRC            ; Loop until interrupt
    bmi wsrvint

; ...Service interrupt

srvint:
    ldx #SENSE          ; Sense interrupt status
    jsr cmdexec         ; Execute command

; Read command result

readres:    
    ldx #$00
    jsr waitrdy         ; Wait until ready

readdatr:
    lda DATR            ; Read status register
    sta scrtch, x       ; Store to memory
    nop                 ; Wait a few cycles
    nop
    inx                 ; Next byte
    lda #$10
    and MSTR            ; More data available from the data register?
    bne readdatr        ; Yes, continue reading
    rts                 ; No, return

; Error handling

e2: inc errorc          ; 02 READ ERROR CODE
e1: inc errorc          ; 01 RECALIBRATE ERROR CODE
    ldx #0
1:  lda errmsg, x
    beq 2f
    jsr OUTCH
    inx
    bne 1b
2:  lda errorc
    jsr PRTBYT
    jsr CRLF

    brk

; Command strings used by the bootloader

cmdstrs:
specstr:    .byte   $03, $03, $6F, $20      ; SPECIFY:
                                            ;   Step Rate Time   = 10ms
                                            ;   Head Unload Time = 240ms
                                            ;   Head Load Time   = 32ms
                                            ;   DMA mode

recastr:    .byte   $02, $07, $00           ; RECALIBRATE drive 0

sensstr:    .byte   $01, $08                ; SENSE INTERRUPT STATUS

readstr:    .byte   $09, $46, $00, $00, $00 ; READ: MFM, Drive 0, Head 0, Cyl 0
            .byte   $00                     ; Start sector
            .byte   $01                     ; 256 bytes/sect
            .byte   $7                      ; End sector (FIXME: Do this part of the building process)
            .byte   $0E, $FF                ; Gap length $0E

; Error message string

errmsg:
    .byte 13, 10
    .ascii "Abnormal termination. Error Code: "
    .byte 0
