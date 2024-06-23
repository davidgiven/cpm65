; CP/M-65 boot program for the KIM-1
; Copyright © 2024 Eduardo Casino
; 
; SD code by Ryan E. Roth
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

; KIM-1 I/O

PORTA = $1700

SD_CS   = %00010000
SD_SCK  = %00001000
SD_MOSI = %00000100
SD_MISO = %00000010

.section .zp, "zax", @nobits

zp_sd_address:          .fill 2
zp_sd_currentsector:    .fill 4
errorc:                 .fill 1

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

    ; Init current sector

    sta zp_sd_currentsector+0
    sta zp_sd_currentsector+1
    sta zp_sd_currentsector+2
    sta zp_sd_currentsector+3
    
    ; Init destination address

    sta zp_sd_address+0
    lda #$c0
    sta zp_sd_address+1
    
    jsr sd_init

    bcs e1

    ; Load first 4 sectors into $c000 (FIXME: Make this configurable)

    ldy #4
1:  jsr sd_readsector
    bcs e2
    inc zp_sd_currentsector+0
    inc zp_sd_address+1
    inc zp_sd_address+1
    dey
    bne 1b

    jmp $c000

; Error handling

e2: inc errorc          ; 02 Read error
e1: inc errorc          ; 01 Initialization error
    ldy #0
1:  lda errmsg, y
    beq 2f
    sty savey
    jsr OUTCH
    ldy savey
    iny
    bne 1b
2:  lda errorc
    jsr PRTBYT
    jsr CRLF

    brk

savey: .byte 1

; Error message string

errmsg:
    .byte 13, 10
    .ascii "Abnormal termination. Error Code: "
    .byte 0

sd_init:
  ; Let the SD card boot up, by pumping the clock with SD CS disabled

  ; We need to apply around 80 clock pulses with CS and MOSI high.
  ; Normally MOSI doesn't matter when CS is high, but the card is
  ; not yet is SPI mode, and in this non-SPI state it does care.
  ldy #0
_initretry:
  lda #SD_CS | SD_MOSI
  ldx #160               ; toggle the clock 160 times, so 80 low-high transitions
_preinitloop:
  eor #SD_SCK
  sta PORTA
  dex
  bne _preinitloop
  

_cmd0: ; GO_IDLE_STATE - resets card to idle state, and SPI mode
  lda #<sd_cmd0_bytes
  sta zp_sd_address
  lda #>sd_cmd0_bytes
  sta zp_sd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne _initfailed

_cmd8: ; SEND_IF_COND - tell the card how we want it to operate (3.3V, etc)
  lda #<sd_cmd8_bytes
  sta zp_sd_address
  lda #>sd_cmd8_bytes
  sta zp_sd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne _initfailed

  ; Read 32-bit return value, but ignore it
  jsr sd_readbyte
  jsr sd_readbyte
  jsr sd_readbyte
  jsr sd_readbyte

_cmd55: ; APP_CMD - required prefix for ACMD commands
  lda #<sd_cmd55_bytes
  sta zp_sd_address
  lda #>sd_cmd55_bytes
  sta zp_sd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne _initfailed

_cmd41: ; APP_SEND_OP_COND - send operating conditions, initialize card
  lda #<sd_cmd41_bytes
  sta zp_sd_address
  lda #>sd_cmd41_bytes
  sta zp_sd_address+1

  jsr sd_sendcommand

  ; Status response $00 means initialised
  cmp #$00
  beq _initialized

  ; Otherwise expect status response $01 (not initialized)
  cmp #$01
  bne _initfailed

  ; Not initialized yet, so wait a while then try again.
  ; This retry is important, to give the card time to initialize.

  ldx #0
  ldy #0
_delayloop:
  dey
  bne _delayloop
  dex
  bne _delayloop

  jmp _cmd55

_initialized:
  ;lda #'Y'
  ;jsr print_char
  clc
  rts

_initfailed:
  iny
  cpy #2
  bne _initretry
_libsdfail:
  sec
  rts

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
    lda zp_sd_currentsector+3   ; sector 24:31
    jsr sd_writebyte
    lda zp_sd_currentsector+2   ; sector 16:23
    jsr sd_writebyte
    lda zp_sd_currentsector+1   ; sector 8:15
    jsr sd_writebyte
    lda zp_sd_currentsector     ; sector 0:7
    jsr sd_writebyte
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

sd_sendcommand:
    ; Debug print which command is being executed
    ; lda #'c'
    ; jsr print_char
    ; ldx #0
    ; lda (zp_sd_address,x)
    ; jsr print_hex

    lda #SD_MOSI                ; pull CS low to begin command
    sta PORTA

    ldy #0
    lda (zp_sd_address),y       ; command byte
    jsr sd_writebyte
    ldy #1
    lda (zp_sd_address),y       ; data 1
    jsr sd_writebyte
    ldy #2
    lda (zp_sd_address),y       ; data 2
    jsr sd_writebyte
    ldy #3
    lda (zp_sd_address),y       ; data 3
    jsr sd_writebyte
    ldy #4
    lda (zp_sd_address),y       ; data 4
    jsr sd_writebyte
    ldy #5
    lda (zp_sd_address),y       ; crc
    jsr sd_writebyte

    jsr sd_waitresult
    pha

    ; Debug print the result code
    ; jsr print_hex

    ; End command

    lda #SD_CS | SD_MOSI        ; set CS high again
    sta PORTA

    pla   ; restore result code
    rts

sd_writebyte:
    ; Tick the clock 8 times with descending bits on MOSI
    ; SD communication is mostly half-duplex so we ignore anything it sends back here

    ldx #8                      ; send 8 bits

_wbloop:
        asl                     ; shift next bit into carry
        tay                     ; save remaining bits for later

        lda #0
        bcc 1f                  ; if carry clear, don't set MOSI for this bit
        ora #SD_MOSI

1:
        sta PORTA               ; set MOSI (or not) first with SCK low
        eor #SD_SCK
        sta PORTA               ; raise SCK keeping MOSI the same, to send the bit

        tya                     ; restore remaining bits to send

        dex
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
  
  bcs _rbloop                   ; loop if we need to read more bits

  rts

sd_waitresult:
    ; Wait for the SD card to return something other than $ff
1:
    jsr sd_readbyte
    cmp #$ff
    beq 1b
    rts

