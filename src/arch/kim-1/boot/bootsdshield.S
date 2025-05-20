; CP/M-65 boot program for the KIM-1
; Copyright © 2024 Eduardo Casino
; 
; SD Shield interface code by Bob Applegate
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

;----------------------------------------------------
; Bits in the B register
;
DIRECTION = 1<<0    ;%00000001
PSTROBE   = 1<<1    ;%00000010
ACK       = 1<<2    ;%00000100

;----------------------------------------------------
; The KIM has a 6530 with the two I/O ports at $1700.
;
; Addresses of 6530 registers
;
PIABASE = $1700
PIAREGA = PIABASE       ;data reg A
PIADDRA = PIABASE+1     ;data dir reg A
PIAREGB = PIABASE+2     ;data reg B
PIADDRB = PIABASE+3     ;data dir reg B

;=====================================================
; Commands from host to Arduino
;
PC_RD_SECTOR    = $18       ;Read FLEX sector

;=====================================================
; Responses from Arduino to host
;
PR_SECTOR_DATA  = $94       ;Sector data

.section .zp, "zax", @nobits

zp_sds_dpb:
zp_sds_drive:           .fill 1
zp_sds_track:           .fill 1
zp_sds_sector:          .fill 1
zp_sds_spt:             .fill 1     ; Sectors per track
zp_sds_buffer:          .fill 2     ; Pointer to data buffer

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

    ; Init paralel port

    jsr xParInit
    
    ; Load first 8 sectors into $6000 (FIXME: Make this configurable)

    lda #$60
    sta zp_sds_buffer+1
    lda #0
    sta zp_sds_buffer+0
    sta zp_sds_drive
    sta zp_sds_track
    sta zp_sds_sector
    lda #26                         ; Sectors per track
    sta zp_sds_spt

    ldx #8
1:  jsr DiskReadSector
    bcs error
    inc zp_sds_sector
    inc zp_sds_buffer+1
    dex
    bne 1b

    jmp $6000

; Error handling

error:
    ldx #0
1:  lda errmsg, x
    beq 2f
    jsr OUTCH
    inx
    bne 1b
2:  lda zp_sds_sector
    jsr PRTBYT

    brk

; Error message string

errmsg:
    .byte 13, 10
    .ascii "Error reading sector "
    .byte 0

;=====================================================
; This is a low level disk function for a real OS to
; perform a disk sector read.  On entry, zp_sds_dpb
; is a disk parameter block with the following fields:
;
;    drive             DS   1
;    track             DS   1
;    sector            DS   1
;    sectors per track DS   1
;    ptr to data       DS   2   must be 256 bytes long!
;
; The first three fields are zero based.  Sectors per
; track is a one based value.
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
DiskReadSector:
    lda #PC_RD_SECTOR           ;sector read command
	jsr	xParWriteByte	        ;command
	lda	zp_sds_drive	        ;get drive
	jsr	xParWriteByte	        ;drive
	lda	#2	                    ;256 byte sectors
	jsr	xParWriteByte
	lda	zp_sds_track	        ;get track
	jsr	xParWriteByte	        ;track
	lda	zp_sds_sector	        ;get sector
    jsr	xParWriteByte	        ;sector
	lda	zp_sds_spt	            ;get tracks/sector
    jsr	xParWriteByte
;
; Now get the response.  Will be either a NAK followed
; by an error code, or a 97 followed by 256 bytes of
; data.
;
    jsr xParSetRead
    jsr xParReadByte        ;response
    cmp #PR_SECTOR_DATA     ;data?
    bne DiskCerror          ;no

; Read 256 bytes to the address at zp_sd_address

    ldy #0
1:  jsr xParReadByte
    sta (zp_sds_buffer),y
    iny
    bne 1b    
;
; All done
;
    jsr xParSetWrite
    clc
    rts

;
; Common error handler. Set carry, and exit.
;
DiskCerror:
    sec
    rts

;*****************************************************
; This is the initialization function.  Call before
; doing anything else with the parallel port.
;

;
; Set up the data direction register for port B so that
; the DIRECTION and PSTROBE bits are output.  Only touch
; the bits we're using; leave the rest as-is.
;
xParInit:
    lda PIADDRB        ;get current value
    and #~ACK & 0xff
    ora #DIRECTION | PSTROBE
    sta PIADDRB
;
    lda #$ff
    sta PIADDRA        ;set data for write
;
; Now that the data is set, set the direction
; registers.  This prevents weird problems like
; driving lines to the wrong state.
;
    lda PIAREGB
    and #~(PSTROBE | ACK) & 0xff
    ora #DIRECTION
    sta PIAREGB
    rts

;*****************************************************
; This sets up for writing to the Arduino.  Sets up
; direction registers, drives the direction bit, etc.
;
xParSetWrite:
    lda #$ff            ;set bits for output
    sta PIADDRA
;
; Set direction flag to output, clear ACK bit
;
    lda PIAREGB
    and #~(PSTROBE | ACK) & 0xff
    ora #DIRECTION
    sta PIAREGB
    rts

;*****************************************************
; This sets up for reading from the Arduino.  Sets up
; direction registers, clears the direction bit, etc.
;
xParSetRead:
    lda #$00            ;set bits for input
    sta PIADDRA
;
; Set direction flag to input, clear ACK bit
;
    lda PIAREGB
    and #~(DIRECTION | PSTROBE | ACK) & 0xff
    sta PIAREGB
    rts
        
;*****************************************************
; This writes a single byte to the Arduino.  On entry,
; the byte to write is in A.  This assumes ParSetWrite
; was already called.
;
; Destroys A, all other registers preserved.
;
; Write cycle:
;
;    1. Wait for other side to lower ACK.
;    2. Put data onto the bus.
;    3. Set DIRECTION and PSTROBE to indicate data
;       is valid and ready to read.
;    4. Wait for ACK line to go high, indicating the
;       other side has read the data.
;    5. Lower PSTROBE.
;    6. Wait for ACK to go low, indicating end of
;       transfer.
;
xParWriteByte:
    pha                 ;save data
1:  lda PIAREGB         ;check status
    and #ACK
    bne 1b              ;wait for ACK to go low

;
; Now put the data onto the bus
;
    pla
    sta PIAREGA
;
; Raise the strobe so the Arduino knows there is
; new data.
;
    lda PIAREGB
    ora #PSTROBE
    sta PIAREGB
;
; Wait for ACK to go high, indicating the Arduino has
; pulled the data and is ready for more.
;
2:  lda PIAREGB
    and #ACK
    beq 2b

;
; Now lower the strobe, then wait for the Arduino to
; lower ACK.
;
    lda PIAREGB
    and #~PSTROBE & 0xff
    sta PIAREGB
3:  lda PIAREGB
    and #ACK
    bne 3b
    rts

;*****************************************************
; This reads a byte from the Arduino and returns it in
; A.  Assumes ParSetRead was called before.
;
; This does not have a time-out.
;
; Preserves all other registers.
;
; Read cycle:
;
;    1. Wait for other side to raise ACK, indicating
;       data is ready.
;    2. Read data.
;    3. Raise PSTROBE indicating data was read.
;    4. Wait for ACK to go low.
;    5. Lower PSTROBE.
;
xParReadByte:
    lda PIAREGB
    and #ACK            ;is their strobe high?
    beq xParReadByte    ;nope, no data
;
; Data is available, so grab and save it.
;
    lda PIAREGA
    pha
;
; Now raise our strobe (their ACK), then wait for
; them to lower their strobe.
;
    lda PIAREGB
    ora #PSTROBE
    sta PIAREGB
1:  lda PIAREGB
    and #ACK
    bne 1b              ;still active 
;
; Lower our ack, then we're done.
;
    lda PIAREGB
    and #~PSTROBE & 0xff
    sta PIAREGB
    pla
    rts
