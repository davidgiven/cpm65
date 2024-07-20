; CP/M-65 boot program for the KIM-1
; Copyright © 2024 Eduardo Casino
; 
; SD code by Ryan E. Roth
;
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 ZP

SPUSER = $f2            ; Current stack pointer

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

; KIM-1 I/O

PORTA = $1700
DDRA  = $1701

SD_CS   = %00010000
SD_SCK  = %00001000
SD_MOSI = %00000100
SD_MISO = %00000010

PORTA_OUTPUTPINS = SD_CS | SD_SCK | SD_MOSI

CMD0IDX  = 0
CMD8IDX  = sd_cmd8_bytes-sd_cmd0_bytes
CMD55IDX = sd_cmd55_bytes-sd_cmd0_bytes
CMD41IDX = sd_cmd41_bytes-sd_cmd0_bytes


.section .zp, "zax", @nobits

; We can reuse zp_sd_currentsector+3 as errorc cause sector count is never gonna be as big

zp_sd_currentsector:    .fill 3
errorc:                 .fill 1
zp_sd_address:          .fill 2
zp_sd_sectorcount:      .fill 1
count:                  .fill 1

.text

.global _start
_start:

#ifdef KIM_ROM

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

ram_start:

#endif
    cld

    ; Set interrupt vectors so we can return to the monitor

    lda #$1c
    sta NMIV+1
    sta IRQV+1

    lda #0
    sta NMIV+0
    sta IRQV+0

    ; Init zp_current_sector (and errorc)

    ldx #3
1:  sta zp_sd_currentsector,x
    dex
    bpl 1b

    lda #PORTA_OUTPUTPINS     ; Set various pins on port A to output
    sta DDRA

    jsr sd_init

    bcs e1

    ; Load first 4 sectors into $6000 (FIXME: Make this configurable)

    lda #0
    sta zp_sd_address+0
    lda #$60
    sta zp_sd_address+1

    lda #4
    sta zp_sd_sectorcount
1:  jsr sd_readsector
    bcs e2
    inc zp_sd_currentsector+0
    inc zp_sd_address+1
    inc zp_sd_address+1
    dec zp_sd_sectorcount
    bne 1b

    jmp $6000

; Error handling

#ifdef KIM_ROM

e2: inc errorc      ; 01 Read error
e1: jsr CRLF        ; 00 Initialization error
    lda errorc
    jsr PRTBYT
    
    brk

#else

e2: inc errorc          ; 01 Read error
e1: ldx #0              ; 00 Initialization error
1:  lda errmsg, x
    beq 2f
    jsr OUTCH
    inx
    bne 1b
2:  lda errorc
    jsr PRTBYT

    brk

; Error message string

errmsg:
    .byte 13, 10
    .ascii "Abnormal termination. Error Code: "
    .byte 0

#endif

sd_init:
    ; Let the SD card boot up, by pumping the clock with SD CS disabled

    ; We need to apply around 80 clock pulses with CS and MOSI high.
    ; Normally MOSI doesn't matter when CS is high, but the card is
    ; not yet is SPI mode, and in this non-SPI state it does care.

_initretry:
    lda #SD_CS | SD_MOSI
    ldx #160               ; toggle the clock 160 times, so 80 low-high transitions
_preinitloop:
    eor #SD_SCK
    sta PORTA
    dex
    bne _preinitloop

_cmd0: ; GO_IDLE_STATE - resets card to idle state, and SPI mode
    ldx #CMD0IDX

    jsr sd_sendcommand

    ; Expect status response $01 (not initialized)
    cmp #$01
    bne _libsdfail

_cmd8: ; SEND_IF_COND - tell the card how we want it to operate (3.3V, etc)
    ldx #CMD8IDX

    jsr sd_sendcommand

    ; Expect status response $01 (not initialized)
    cmp #$01
    bne _libsdfail

    ; Read 32-bit return value, but ignore it
    ldy #4
1:  jsr sd_readbyte
    dey
    bne 1b

_cmd55: ; APP_CMD - required prefix for ACMD commands
    ldx #CMD55IDX

    jsr sd_sendcommand

    ; Expect status response $01 (not initialized)
    cmp #$01
    bne _libsdfail

_cmd41: ; APP_SEND_OP_COND - send operating conditions, initialize card
    ldx #CMD41IDX

    jsr sd_sendcommand

    ; Status response $00 means initialised
    cmp #$00
    beq _retok

    ; Otherwise expect status response $01 (not initialized)
    cmp #$01
    bne _libsdfail

    ; Not initialized yet, so wait a while then try again.
    ; This retry is important, to give the card time to initialize.

    ldx #0
    ldy #0
_delayloop:
    dey
    bne _delayloop
    dex
    bne _delayloop
    beq _cmd55

_libsdfail:
    sec
    rts

; Command sequences

sd_cmd0_bytes:
    .byte $40, $00, $00, $00, $00, $95
sd_cmd8_bytes:
    .byte $48, $00, $00, $01, $aa, $87
sd_cmd55_bytes:
    .byte $77, $00, $00, $00, $00, $01
sd_cmd41_bytes:
    .byte $69, $40, $00, $00, $00, $01


sd_readsector:
    ; Read a sector from the SD card.  A sector is 512 bytes.
    ;
    ; Parameters:
    ;    zp_sd_currentsector      32-bit sector number
    ;    zp_sd_address            address of buffer to receive data

    lda #SD_MOSI
    sta PORTA

    ; Command 17, arg is sector number, crc not checked

    lda #$51                    ; CMD17 - READ_SINGLE_BLOCK
    jsr sd_writebyte

    ldx #3
1:  lda zp_sd_currentsector,x
    jsr sd_writebyte
    dex
    bpl 1b

    lda #$01                    ; crc (not checked)
    jsr sd_writebyte

    jsr sd_waitresult
    cmp #$00
    bne _libsdfail

    ; wait for data

    jsr sd_waitresult
    cmp #$fe
    bne _libsdfail

    ; Need to read 512 bytes - two pages of 256 bytes each

    jsr _readpage
    inc zp_sd_address+1
    jsr _readpage
    dec zp_sd_address+1

    ; End command
    lda #SD_CS | SD_MOSI
    sta PORTA

_retok:
    clc
    rts

_readpage:
    ; Read 256 bytes to the address at zp_sd_address
    ldy #0
1:  jsr sd_readbyte
    sta (zp_sd_address),y
    iny
    bne 1b
    rts

; Command address in AX

sd_sendcommand:
    ; Debug print which command is being executed
    ; lda #'c'
    ; jsr print_char
    ; ldx #0
    ; lda (zp_sd_address,x)
    ; jsr print_hex

    lda #SD_MOSI                ; pull CS low to begin command
    sta PORTA

    lda #6
    sta count
1:  lda sd_cmd0_bytes,x       ; command byte
    jsr sd_writebyte
    inx
    dec count
    bne 1b

    jsr sd_waitresult

    ; Debug print the result code
    ; jsr print_hex

    ; End command

    ldx #SD_CS | SD_MOSI        ; set CS high again
    stx PORTA

    rts

sd_writebyte:
    ; Tick the clock 8 times with descending bits on MOSI
    ; SD communication is mostly half-duplex so we ignore anything it sends back here

    ldy #8                      ; send 8 bits

_wbloop:
    asl                         ; shift next bit into carry
    pha                         ; save remaining bits for later

    lda #0
    bcc 1f                      ; if carry clear, don't set MOSI for this bit
    ora #SD_MOSI

1:  sta PORTA                   ; set MOSI (or not) first with SCK low
    eor #SD_SCK
    sta PORTA                   ; raise SCK keeping MOSI the same, to send the bit

    pla                         ; restore remaining bits to send

    dey
    bne _wbloop

    rts

sd_readbyte:
    ; Enable the card and tick the clock 8 times with MOSI high, 
    ; capturing bits from MISO and returning them
    ldx #$fe    ; Preloaded with seven ones and a zero, so we stop after eight bits

_rbloop:

    lda #SD_MOSI                ; enable card (CS low), set MOSI (resting state), SCK low
    sta PORTA

    lda #SD_MOSI | SD_SCK       ; toggle the clock high
    sta PORTA

    lda PORTA                   ; read next bit
    and #SD_MISO

    clc                         ; default to clearing the bottom bit
    beq _bitnotset              ; unless MISO was set
    sec                         ; in which case get ready to set the bottom bit
_bitnotset:

    txa                         ; transfer partial result from X
    rol                         ; rotate carry bit into read result, and loop bit into carry
    tax                         ; save partial result back to X

    bcs _rbloop                 ; loop if we need to read more bits

    rts

sd_waitresult:
    ; Wait for the SD card to return something other than $ff
1:  jsr sd_readbyte
    cmp #$ff
    beq 1b
    rts

