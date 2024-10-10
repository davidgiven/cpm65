; Ohio Scientific Instruments floppy routines.
; Copyright © 2024 by Ivo van Poorten
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

DATA_DIRECTION_ACCESS = $04     ; bit 2, 0 active (!)

ORA   = $c000       ; output register A
DDRA  = $c000       ; data directrion A
CRA   = $c001       ; control register A

ORB  = $c002        ; output register B
DDRB = $c002        ; data direction B
CRB  = $c003        ; control register B

PORTA = $c000       ; alias for ORA
PORTB = $c002       ; alias for ORB

; ----------------------------------------------------------------------------

; PORTA

DRIVE0_NOT_READY_MASK = 0x01        ; 0 = drive0 reads, 1 = not ready
HEAD_NOT_TRACK0_MASK  = 0x02        ; 0 = above, 1 = not above
DRIVE1_NOT_READY_MASK = 0x10        ; 0 = drive1 reads, 1 = not ready
DISK_R_W_MASK         = 0x20        ; 0 = protected, 1 = r/w
DRIVE0_SELECT_MASK    = 0x40        ; 0 = drive1, 1 = drive0
NOT_INDEX_HOLE_MASK   = 0x80        ; 0 = above hole, 1 = not above

; PORTB

READ_FROM_DISK_MASK   = 0x01        ; nWRITE: 0 = write, 1 = read
ERASE_ENABLE_MASK     = 0x02        ; nERASE: 0 = enabled, 1 = disabled
DIRECTION_MASK        = 0x04        ; nSTEPDIR: 0 = to trk 39, 1 = to trk 0
MOVE_HEAD_MASK        = 0x08        ; nSTEP: 1->0 move, 1 = steady
FAULT_RESET_MASK      = 0x10        ; nRESET: 0 = reset, 1 = normal
DRIVE_01_23_MASK      = 0x20        ; 0 = drive 2/3, 1 = drive 0/1
LOW_CURRENT_MASK      = 0x40        ; mostly 1, 0 on 8" trk >= 44
HEAD_NOT_ON_DISK_MASK = 0x80        ; nHEADLOAD 0 = on disk, 1 = lifted

; ----------------------------------------------------------------------------

ACIA_CONTROL = $c010    ; control register
ACIA_STATUS  = $c010    ; status register
ACIA_TDR     = $c011    ; transmit data register
ACIA_RDR     = $c011    ; receive data register

CONTROL_DIV_MASK = 0x03             ; divider 1,16,64,master reset
CONTROL_RESET    = 0x03
CONTROL_WS_MASK  = 0x1c             ; word select, see below
CONTROL_TX_CTRL  = 0x60             ; transmit control bits, see below
CONTROL_RX_IRQE  = 0x80             ; receive interrupt enable

STATUS_RDRF_MASK = 0x01             ; Rx data register full
STATUS_TDRE_MASK = 0x02             ; Tx data register empty
STATUS_nDCD_MASK = 0x04             ; /DCD Data Carrier Detect
STATUS_nCTS_MASK = 0x08             ; /CTS Clear To Send
STATUS_FE_MASK   = 0x10             ; Rx Frame Error
STATUS_OVRN_MASK = 0x20             ; Rx Overrun
STATUS_PE_MASK   = 0x40             ; Rx Parity Error
STATUS_IRQ_MASK  = 0x80             ; /IRQ, if pin output is low, bit is 1
                                    ; clear by read of RDR

CONTROL_DIV_1  = 0
CONTROL_DIV_16 = 1
CONTROL_DIV_64 = 2

WS_SHIFT = 2

WS_7E2 = 0x00
WS_7O2 = 0x01
WS_7E1 = 0x02
WS_7O1 = 0x03
WS_8N2 = 0x04
WS_8N1 = 0x05
WS_8E1 = 0x06
WS_8O1 = 0x07

TCB_SHIFT = 5

TCB_nRTS_LOW_IRQ_DIS           = 0x00
TCB_nRTS_LOW_IRQ_ENA           = 0x01
TCB_nRTS_HIGH_IRQ_DIS          = 0x02
TCB_nRTS_LOW_BREAK_LVL_IRQ_DIS = 0x03

; ----------------------------------------------------------------------------

zproc init_pia
    ldy #0
    ldx #DATA_DIRECTION_ACCESS

    sty CRA         ; select DDRA
    lda #$40
    sta DDRA        ; set all pins to input, except bit 6
    stx CRA         ; select ORA
    sta PORTA       ; select drive 0

    sty CRB         ; select DDRB
    dey             ; Y=$ff
    sty DDRB        ; set all pins to output
    stx CRB         ; select ORB
    sty PORTB       ; set all outputs high

    rts
zendproc

; ----------------------------------------------------------------------------

zproc init_acia
    lda #CONTROL_RESET
    sta ACIA_CONTROL
    lda #(TCB_nRTS_HIGH_IRQ_DIS << TCB_SHIFT) | (WS_8E1 << WS_SHIFT)
    sta ACIA_CONTROL

    rts
zendproc

; ----------------------------------------------------------------------------

zproc wait_past_index_hole
    zloop                   ; not above hole, might be a no-op if index is
        lda PORTA           ; already triggered
    zuntil_pl
    zloop                   ; above hole
        lda PORTA
    zuntil_mi
    rts                     ; not above hole
zendproc

; ----------------------------------------------------------------------------

; Head Movement, step in and step out

zproc step_out                  ; to edge, track--
    lda PORTB
    ora #DIRECTION_MASK
    bne step
zendproc

zproc step_in                   ; to center hole, track++
    lda PORTB
    and #DIRECTION_MASK^0xff
    ; [[fallthrough]]
zendproc

zproc step
    sta PORTB

    jsr short_delay

    and #MOVE_HEAD_MASK^0xff
    sta PORTB                   ; 1->0 transition, move

    jsr short_delay

    ora #MOVE_HEAD_MASK
    sta PORTB                   ; back to 1, ready for next transition

    ldx #$18
    bne long_delay_X            ; branch always
zendproc

; SEEK TO TRACK 0 ENTRY POINT

zproc seek_to_track0
    jsr step_in

    jsr long_delay              ; always returns with X=Y=0, and Z=1

    sty curtrk                  ; set curtrk to zero

;keep_moving:
    zloop
        lda #HEAD_NOT_TRACK0_MASK
        bit PORTA               ; bit 1 is 0, means track 0 sensor is triggered
        zbreakif_eq             ; fallthrough to long delay

        jsr step_out            ; step_out ends with long_delay_X, hence Z=1
    zuntil_ne                   ; so this is a branch always

    ; [[fallthrough]]
zendproc

; Long delays always return with X=Y=0 and Z=1

zproc long_delay
    ldx #$18

    ; [[fallthrough]]
zendproc

zproc long_delay_X
    zloop
        ldy #$f8

_short_delay_X_Y:                ; enter here with Y set, and X=1
        zloop
            dey                 ; 2 cycles
        zuntil_eq               ; 3 cycles if looped, $f8*5-1 = 1239 cycles

        dex                     ; 2 cycles
     zuntil_eq                  ; 3 cycles if looped, $18*1244-1 = 29855 cycles

    ; [[fallthrough]]
zendproc

zproc short_delay
    rts
zendproc

; ----------------------------------------------------------------------------

zproc put_head_on_disk
    lda PORTB
    and #HEAD_NOT_ON_DISK_MASK^0xff

    ; [[fallthrough]]
zendproc

zproc move_head
    sta PORTB
    ldx #$28
    jmp long_delay_X
zendproc

zproc lift_head_from_disk
    lda PORTB
    ora #HEAD_NOT_ON_DISK_MASK
    bne move_head
zendproc

; ----------------------------------------------------------------------------

zproc enable_write_and_erase
    lda PORTB
    and #(READ_FROM_DISK_MASK | ERASE_ENABLE_MASK)^0xff
    ; [[fallthrough]]
zendproc

zproc common_write_and_erase
    sta PORTB
    rts
zendproc

zproc disable_write_and_erase
    lda PORTB
    ora #(READ_FROM_DISK_MASK | ERASE_ENABLE_MASK)
    bne common_write_and_erase
zendproc

; ----------------------------------------------------------------------------

zproc tobcd
    ldx #0
    zloop
        cmp #10
        zbreakif_cc

        inx

        ; carry is always set
        sbc #10
    zuntil_cc

    sta trkbcd

    txa
    asl
    asl
    asl
    asl

; carry is always clear
    adc trkbcd
    sta trkbcd

    rts
zendproc

; ----------------------------------------------------------------------------

zproc read_byte                 ; Returns result from disk in A
    zloop
        lda ACIA_STATUS         ; wait for STATUS_RDRF_MASK (0x01), RDR full
        lsr
    zuntil_cs

    lda ACIA_RDR
    rts
zendproc

zproc write_byte                ; Write byte in X to disk
    zloop
        lda ACIA_STATUS         ; wait for STATUS_TDRE_MASK (0x02), TDR empty
        lsr
        lsr
    zuntil_cs

    stx ACIA_TDR
    rts
zendproc

; ----------------------------------------------------------------------------

; Common code for reading and writing a track. Exit code in Z(!)
; The following code initializes the "controller", reads the
; track marker and verifies the track number.

zproc read_write_track_common_intro
    lda curtrk
    jsr tobcd

    lda #0
    sta ptr
    lda ptrkbuf
    sta ptr+1

    jsr put_head_on_disk
    jsr wait_past_index_hole
    jsr init_acia

    jsr read_byte
    cmp #$43
    bne common_error_out

    jsr read_byte
    cmp #$57
    bne common_error_out

    jsr read_byte
    cmp trkbcd
    bne common_error_out

    jsr read_byte
    cmp #$58

common_error_out:
    rts
zendproc

zproc read_track
    jsr read_write_track_common_intro
    bne read_error_out

    jsr read_byte
    cmp #$76
    bne read_error_out

    jsr read_byte
    cmp #$01
    bne read_error_out

    jsr read_byte
    cmp #PAGES_PER_TRACK
    bne read_error_out

    tax                 ; X=8 or X=12, read X pages

    ldy #0
    zloop
        zloop
            jsr read_byte
            sta (ptr),y
            iny
        zuntil_eq

        inc ptr+1
        dex
    zuntil_eq

read_ok_out:
write_ok_out:
    jsr lift_head_from_disk
    clc
    rts

read_error_out:
write_error_out:
    jsr lift_head_from_disk
    sec
    rts
zendproc

zproc write_track
    jsr read_write_track_common_intro
    bne write_error_out

    ldx #1
    ldy #$10
    jsr _short_delay_X_Y

#ifdef FLOPPY8
    lda curtrk
    cmp #44
    zif_cs
        lda PORTB
        and #LOW_CURRENT_MASK^0xff
        sta PORTB
    zendif
#endif

    jsr enable_write_and_erase

    ldx #1
    ldy #$f0
    jsr _short_delay_X_Y

    ldx #$76
    jsr write_byte

    ldx #$01
    jsr write_byte

    ldx #PAGES_PER_TRACK
    stx save_x              ; X pages counter for later
    jsr write_byte

    ldy #0
    zloop
        zloop
            lda (ptr),y
            tax
            jsr write_byte
            iny
        zuntil_eq

        inc ptr+1
        dec save_x
    zuntil_eq

    ldx #$47
    jsr write_byte

    ldx #$53
    jsr write_byte

    zloop                   ; wait until index hole
        lda PORTA
    zuntil_pl

    jsr disable_write_and_erase

#ifdef FLOPPY8
    lda PORTB
    ora #LOW_CURRENT_MASK
    sta PORTB
#endif

    jmp write_ok_out
zendproc

; Pass drive number in A (0-3)

zproc select_drive_number
    lda drive_number
    and #1
    zif_eq
        lda #DRIVE0_SELECT_MASK
    zelse
        lda #0
    zendif
    sta PORTA

    lda drive_number
    and #2
    zif_eq
        lda PORTB
        ora #DRIVE_01_23_MASK
    zelse
        lda PORTB
        and #DRIVE_01_23_MASK^$ff
    zendif
    sta PORTB

    rts
zendproc

; vim: filetype=asm sw=4 ts=4 et
