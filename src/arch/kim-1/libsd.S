; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

; This file is a direct adaptation of Ryan E. Roth's sdcard6502 for the PAL-1
; (https://github.com/ryaneroth/sdcard6502), which in turn is based on Gerge Foot's
; sdcard6502 for Ben Eater's 6502 computer (https://github.com/gfoot/sdcard6502)
; and originaly in the Public Domain.

; SD card interface module
;
; Requires zero-page variable storage:
;   zp_sd_address       - 2 bytes
;   zp_sd_currentsector - 4 bytes

#include "zif.inc"
#include "kim-1.inc"

SD_CS   = %00010000
SD_SCK  = %00001000
SD_MOSI = %00000100
SD_MISO = %00000010

.section .zp, "zax", @nobits

.global zp_sd_address           ; Address of buffer to send/receive data
.global zp_sd_currentsector     ; 32-bit sector number

zp_sd_address:          .fill 2
zp_sd_currentsector:    .fill 4

zproc sd_init, .init.sd_init:
    ; Let the SD card boot up, by pumping the clock with SD CS disabled

    ; We need to apply around 80 clock pulses with CS and MOSI high.
    ; Normally MOSI doesn't matter when CS is high, but the card is
    ; not yet is SPI mode, and in this non-SPI state it does care.

    ldy #0
    zrepeat
        lda #SD_CS | SD_MOSI
        ldx #160                    ; toggle the clock 160 times, so 80 low-high transitions
        zrepeat
            eor #SD_SCK
            sta PORTA
            dex
        zuntil_eq

        ; GO_IDLE_STATE - resets card to idle state, and SPI mode

        lda #<sd_cmd0_bytes
        sta zp_sd_address
        lda #>sd_cmd0_bytes
        sta zp_sd_address+1

        jsr sd_sendcommand

        ; Expect status response $01 (not initialized)

        cmp #$01
        bne 1f

        ; SEND_IF_COND - tell the card how we want it to operate (3.3V, etc)

        lda #<sd_cmd8_bytes
        sta zp_sd_address
        lda #>sd_cmd8_bytes
        sta zp_sd_address+1

        jsr sd_sendcommand

        ; Expect status response $01 (not initialized)

        cmp #$01
        bne 1f

        ; Read 32-bit return value, but ignore it

        jsr sd_readbyte
        jsr sd_readbyte
        jsr sd_readbyte
        jsr sd_readbyte

        ; APP_CMD - required prefix for ACMD commands

        zloop
            lda #<sd_cmd55_bytes
            sta zp_sd_address
            lda #>sd_cmd55_bytes
            sta zp_sd_address+1

            jsr sd_sendcommand

            ; Expect status response $01 (not initialized)

            cmp #$01
            bne 1f

            ; APP_SEND_OP_COND - send operating conditions, initialize card

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
            bne 1f

            ; Not initialized yet, so wait a while then try again.
            ; This retry is important, to give the card time to initialize.

            ldx #0
            ldy #0
            zrepeat
                dey
                zcontinueif_ne
                dex
            zuntil_eq

        zendloop

1:
        iny
        cpy #2
    zuntil_eq
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

zendproc

zproc _initialized, .init._initialized, local
    ;lda #'Y'
    ;jsr print_char
    clc
    rts
zendproc

zproc sd_readbyte, .text.sd_readbyte, local
    ; Enable the card and tick the clock 8 times with MOSI high,
    ; capturing bits from MISO and returning them

    ldx #$fe    ; Preloaded with seven ones and a zero, so we stop after eight bits

    zrepeat
        lda #SD_MOSI            ; enable card (CS low), set MOSI (resting state), SCK low
        sta PORTA

        lda #SD_MOSI | SD_SCK   ; toggle the clock high
        sta PORTA

        lda PORTA               ; read next bit
        and #SD_MISO

        clc                     ; default to clearing the bottom bit
        zif_ne
            sec                 ; unless MISO was set, in which case get ready to set the bottom bit
        zendif

        txa                     ; transfer partial result from X
        rol                     ; rotate carry bit into read result, and loop bit into carry
        tax                     ; save partial result back to X
    zuntil_cc

    rts
zendproc

zproc sd_writebyte, .text.sd_writebyte, local
    ; Tick the clock 8 times with descending bits on MOSI
    ; SD communication is mostly half-duplex so we ignore anything it sends back here

    ldx #8                      ; send 8 bits

    zrepeat
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
    zuntil_eq

    rts
zendproc

zproc sd_waitresult, .text.sd_waitresult, local
    ; Wait for the SD card to return something other than $ff

    zrepeat
        jsr sd_readbyte
        cmp #$ff
    zuntil_ne
    rts

zproc sd_sendcommand, .text.sd_sendcommand, local
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
zendproc

zproc sd_readsector, .text.sd_readsector
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
zendproc

zproc _readpage, .text._readpage, local
    ; Read 256 bytes to the address at zp_sd_address

    ldy #0
    zrepeat
        jsr sd_readbyte
        sta (zp_sd_address),y
        iny
    zuntil_eq
    rts
zendproc

zproc _libsdfail, .text._libsdfail, local
    sec
    rts
zendproc

zproc sd_writesector, .text.sd_writesector
    ; Write a sector to the SD card.  A sector is 512 bytes.
    ;
    ; Parameters:
    ;    zp_sd_currentsector    32-bit sector number
    ;    zp_sd_address          address of buffer to take data from

    lda #SD_MOSI
    sta PORTA

    ; Command 24, arg is sector number, crc not checked

    lda #$58                    ; CMD24 - WRITE_BLOCK
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

    ; Send start token

    lda #$fe
    jsr sd_writebyte

    ; Need to write 512 bytes - two pages of 256 bytes each

    jsr _writepage
    inc zp_sd_address+1
    jsr _writepage
    dec zp_sd_address+1

    ; wait for data response

    jsr sd_waitresult
    and #$1f
    cmp #$05
    bne _libsdfail

    ; wait idle

    zrepeat
        jsr sd_readbyte
        cmp #$ff
    zuntil_eq

    ; End command

    lda #SD_CS | SD_MOSI        ; set cs and mosi high (disconnected)
    sta PORTA

    clc
    rts
zendproc

zproc _writepage, .text._writepage, local
  ; Write 256 bytes fom zp_sd_address

    ldy #0
    zrepeat
        tya                     ; transfer counter to a register
        pha                     ; push counter to stack
        lda (zp_sd_address),y
        jsr sd_writebyte
        pla                     ; pull counter from stack
        tay                     ; transfer back
        iny
    zuntil_eq
    rts
zendproc
