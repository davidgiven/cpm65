; Memory map:
;
; WRAM:
;   $7e0000-$7effff  (the first 8kB is also mapped at $000000)
;      The CP/M userspace. This has to be here because the 65816 stack pointer
;      has to be in bank 0.  This is in the window mapped at $7e0000, so when in
;      6502 mode with the stack pointer between $000100 and $0001ff then the
;      stack appears between $7e0100 and $7e01ff.
;   $7f0000-$7fffff
;      Supervisor workspace and buffers (yet to be determined).
;
; ROM:
;   $400000-$407fff
;      Fonts, the BIOS, and other resources.
;   $408000-$40ffff  (also mapped at $008000)
;      The main supervisor code. When the bank registers get set to zero, this
;      gets mapped in automatically.

.cpu "65816"
.enc "ascii"
.cdef " ~", 32
.include "snes.inc"

SCC_B_CTRL      = $5F00 ; SCC channel B control port
SCC_B_DATA      = $5F01 ; SCC channel B data port
SCC_A_CTRL      = $5F02 ; SCC channel A control port
SCC_A_DATA      = $5F03 ; SCC channel A data port

FD72069_STATUS  = $5f20 ; uPD72069 status register
FD72069_DATA    = $5f21 ; uPD72069 data register
FD72069_TC      = $5f30 ; terminal count

FDC_RESET       = %00110110 ; Software reset
FDC_SET_STDBY   = %00110101 ; Set standby
FDC_RESET_STDBY = %00110100 ; Reset standby
FDC_START_CLOCK = %01000111 ; Start clock
FDC_SNSINT      = %00001000 ; Sense interrupt status
FDC_SNSDEV      = %00000100 ; Sense device status
FDC_SPECIFY     = %00000011 ; Specify
FDC_INTERNAL250 = %00001011 ; Control internal mode (250k bps)
FDC_INTERNAL300 = %11001011 ; Control internal mode (300k bps)
FDC_INTERNAL500 = %01001011 ; Control internal mode (500k bps)
FDC_SELFORMAT   = %01001111 ; Select format
FDC_MOTORS      = %11111110 ; Enable motors
FDC_RECALIBRATE = %00000111 ; Recalibtate
FDC_SEEK        = %00001111 ; Seek
FDC_READ        = %11100110 ; Read
FDC_WRITE       = %11000101 ; Write
FDC_WRITEID     = %01001101 ; Write ID

FDD_TRACK_SIZE  = 18*512

VRAM_MAP1_LOC   =  $0000
VRAM_MAP2_LOC   =  $0800
VRAM_TILES_LOC  =  $2000
VRAM_TILES2_LOC =  $6000

LOADER_ADDRESS  = $7e8000

SCREEN_WIDTH    = 64
SCREEN_HEIGHT   = 28
VSCROLL_POS     = 1024-8

MOD_SHIFT       = %10000000 ; n bit
MOD_CTRL        = %01000000 ; v bit
MOD_CAPS        = %00000100

CURSOR_SHOWN    = %10000000 ; n bit

; From driver.inc (which is the wrong syntax for 64tass to import)
STYLE_REVERSE   = 1

.virtual $7f0000
sector:         .long 0     ; 24 bits!
pending_key:    .byte 0
modifier_state: .byte 0
cursorp:        .word 0     ; character count from top left of screen
screen_flags:   .byte 0
style_word:     .byte 0     ; always zero
style_byte:     .byte 0     ; current screen drawing style
tick_counter:   .byte 0
selected_disk:  .byte 0
current_track:  .byte 0
track_dirty:    .byte 0

vram_mirror_start:
map1_mirror:    .fill 2*32*SCREEN_HEIGHT
                .fill 2*32*(32 - SCREEN_HEIGHT) ; padding to match up with VRAM
map2_mirror:    .fill 2*32*SCREEN_HEIGHT
vram_mirror_end:

track_buffer:   .fill FDD_TRACK_SIZE
fdc_status:     .fill 8

.endvirtual

.virtual 0
dma:            .long 0     ; 24 bits!
ptr:            .long 0     ; 24 bits!
.endvirtual

.dpage ?                ; Reserve $0006-$00ff for user programs

* = $000000
.logical $400000
font_data:
    .binary "4bpp.bin"
font_data_end:
font2_data:
    .binary "2bpp.bin"
font2_data_end:
bios_data:
    .binary "bios"
bios_data_end:
.endlogical

a16 .macro
    rep #$20
.endmacro

a8 .macro
    sep #$20
.endmacro

i16 .macro
    rep #$10
.endmacro

i8 .macro
    sep #$10
.endmacro

a8i8 .macro
    sep #$30
.endmacro

a16i16 .macro
    rep #$30
.endmacro

* = $008000
start:
    .autsiz
    sei
    clc
    xce
    a16i16

    ; Wipe memory.

    a8
    ldx #0
    txa
    -
        sta $7e0000, x
        sta $7f0000, x
        dex
        bne -

    ldx #$01ff          ; 6502-compatible
    txs
    pea #0              ; databank to zero for I/O access
    pld

    lda #$7e
    sta dma+2        ; top byte of DMA address

    ; Clear registers
    ldx #$33
    jsr clear_vram
-
    stz INIDISP,x
    stz NMITIMEN,x
    dex
    bpl -

    ; Initialise the screen.

    jsr init_screen

    ; Other hardware.

    jsr init_keyboard
    jsr init_fdd
    jsr screen_clear

    ; Wipe memory and copy the BIOS loader to its final position.

    a16
    lda #(bios_data_end-bios_data)-1
    ldx #<>bios_data
    ldy #<>LOADER_ADDRESS
    mvn #`bios_data, #`LOADER_ADDRESS
    lda #0

    ; Jump into the loader.

    lda #`LOADER_ADDRESS
    pha
    plb                     ; set DB so direct accesses go into user memory
    lda #0
    tad                     ; direct page register to 0

    jml LOADER_ADDRESS      ; ...and go

break:
    rts

init_screen
.block
    php
    phd
    a8
    i16

    ldx #$2100
    phx
    pld
    .dpage $2100

    lda #%10000000          ; force blank
    sta INIDISP

    lda #5 | $00            ; mode 5, 16x8 tiles all layers
    sta BGMODE
    lda #%00001100          ; high res mode, interlacing off
    sta SETINI
    lda #(VRAM_MAP1_LOC >> 9) | %00 ; tilemap 1 address, 32x32
    sta BG1SC
    lda #(VRAM_MAP2_LOC >> 9) | %00 ; tilemap 2 address, 32x32
    sta BG2SC
    lda #((>VRAM_TILES_LOC >> 5) | ((>VRAM_TILES2_LOC >> 1) & $f0))
    sta BG12NBA
    lda #%00000011          ; main screen turn on: BG1 and BG2
    sta TM
    sta TS                  ; ditto subscreen

    lda #<VSCROLL_POS
    sta BG1VOFS
    xba
    lda #>VSCROLL_POS
    sta BG1VOFS
    xba
    sta BG2VOFS
    xba
    sta BG2VOFS

    jsr load_font_data
    jsr load_palette_data

    lda #%10000000          ; enable vsync NMI
    sta NMITIMEN

    lda #%00001111          ; blank off, maximum brightness
    sta INIDISP

    lda #CURSOR_SHOWN
    sta screen_flags
    lda #$20
    sta style_byte

    pld
    plp
    rts
.endblock

wait_for_vblank:
    php
    a8 

-
    lda HVBJOY
    and #%10000000          ; test for v-blank flag
    beq -

    plp
    rts

load_palette_data:
    php
    a8i8

    lda #2
    sta CGADD

    stz CGDATA
    stz CGDATA
    lda #$ff
    sta CGDATA
    sta CGDATA

    ldx #4+2
    stx CGADD

    sta CGDATA
    sta CGDATA
    stz CGDATA
    stz CGDATA

    ldx #16+2
    stx CGADD

    sta CGDATA
    sta CGDATA
    stz CGDATA
    stz CGDATA

    plp
    rts

load_font_data:
    php
    a16i16

    lda #%10000000       ; autoincrement by one word
    sta VMAIN
   
    ldx #VRAM_TILES_LOC>>1 ; set dest VRAM address
    stx VMADDL
    ldx #0               ; source offset
-
    lda @l font_data, x
    sta VMDATAL
    inx
    inx
    cpx #(font_data_end - font_data)
    bne -

    ldx #VRAM_TILES2_LOC>>1 ; set dest VRAM address
    stx VMADDL
    ldx #0
-
    lda @l font2_data, x
    sta VMDATAL
    inx
    inx
    cpx #(font2_data_end - font2_data)
    bne -

    plp
    rts

clear_vram:
    pha
    phx
    php

    a8

    lda #$80
    sta $2115         ;Set VRAM port to.word access
    ldx #$1809
    stx $4300         ;Set DMA mode to fixed source,.word to $2118/9
    ldx #$0000
    stx $2116         ;Set VRAM port address to $0000
    stx $0000         ;Set $00:0000 to $0000 (assumes scratchpad ram)
    stx $4302         ;Set source address to $xx:0000
    lda #$00
    sta $4304         ;Set source bank to $00
    ldx #$FFFF
    stx $4305         ;Set transfer size to 64k-1.bytes
    lda #$01
    sta $420b         ;Initiate transfer

    stz $2119         ;clear the last.byte of the VRAM

    plp
    plx
    pla
    rts

exit_cop_e:


brk_e_entry:
    jml $7eff00     ; run the sec/sce/rti instructions from bank 7e

brk_n_entry:
abt_e_entry:
int_e_entry:
    rti

nmi_n_entry:
    a16i16
    pha
    jsr nmi_handler
    pla
return_int:
    rti

nmi_e_entry:
    clc
    xce             ; out of emulation mode

    a16i16
    pha
    jsr nmi_handler
    pla

    jml $7eff00     ; run the sec/sce/rti instructions from bank 7e

; --- Keyboard handling -----------------------------------------------------

init_keyboard:
    php
    a8

    lda #0
    sta pending_key
    sta modifier_state

    ldx #keyboard_init_data1
    jsr write_keyboard_init_data
    jsr wait
    ldx #keyboard_init_data2
    jsr write_keyboard_init_data
    jsr wait

    plp
    rts

get_current_key:
.block
    phb
    php
    a8i8

    .databank $7f
    lda #$7f
    pha
    plb

    lda pending_key
    bne exit

    ; Block and wait for a scancode from the keyboard.

    lda SCC_A_CTRL      ; shortcut to reading register 0
    lsr a               ; Rx bit into carry
    bcc exit_nokey

    lda SCC_A_DATA      ; shortcut to reading data register

    cmp #$70
    beq shift_mod_down
    cmp #$70 | $80
    beq shift_mod_up
    cmp #$74
    beq ctrl_mod_down
    cmp #$74 | $80
    beq ctrl_mod_up
    bit #$80            ; keyup?
    bne exit_nokey      ; ignore.

    ; Got one.

    tax
    lda keymap_normal, x
    bit modifier_state
    bpl +
    lda keymap_shift, x
+
    bit modifier_state
    bvc +
    and #$1f
+
    sta pending_key
exit:
    plp
    plb
    rts

shift_mod_down:
    lda #MOD_SHIFT
    bra set_mod
ctrl_mod_down:
    lda #MOD_CTRL
set_mod:
    tsb modifier_state
    bra exit_nokey

shift_mod_up:
    lda #MOD_SHIFT
    bra clr_mod
ctrl_mod_up:
    lda #MOD_CTRL
clr_mod:
    trb modifier_state
exit_nokey:
    lda #0
    bra exit

keymap_normal:
    .byte $1B, $31, $32, $33, $34, $35, $36, $37 ; $00
    .byte $38, $39, $30, $2D, $5E, $5C, $08, $09
    .byte $71, $77, $65, $72, $74, $79, $75, $69 ; $10
    .byte $6F, $70, $40, $5B, $0D, $61, $73, $64
    .byte $66, $67, $68, $6A, $6B, $6C, $3B, $3A ; $20
    .byte $5D, $7A, $78, $63, $76, $62, $6E, $6D
    .byte $2C, $2E, $2F, $00, $20, $0E, $13, $14 ; $30
    .byte $12, $7F, $8b, $88, $89, $8a, $0C, $01
    .byte $2D, $2F, $37, $38, $39, $2A, $34, $35 ; $40
    .byte $36, $2B, $31, $32, $33, $3D, $30, $2C
    .byte $2E, $0F, $00, $00, $00, $00, $00, $00 ; $50
    .byte $00, $00, $00, $00, $00, $00, $00, $00
    .byte $03, $02, $00, $00, $00, $00, $00, $00 ; $60
    .byte $00, $00, $00, $00, $00, $00, $00, $00
keymap_shift:
    .byte $1B, $21, $22, $23, $24, $25, $26, $27 ; $00
    .byte $28, $29, $00, $3D, $60, $7C, $08, $09
    .byte $51, $57, $45, $52, $54, $59, $55, $49 ; $10
    .byte $4F, $50, $7E, $7B, $0D, $41, $53, $44
    .byte $46, $47, $48, $4A, $4B, $4C, $2B, $2A ; $20
    .byte $7D, $5A, $58, $43, $56, $42, $4E, $4D
    .byte $3C, $3E, $3F, $5F, $20, $0E, $13, $14 ; $30
    .byte $12, $7F, $8b, $88, $89, $8a, $0B, $01
    .byte $2D, $2F, $37, $38, $39, $2A, $34, $35 ; $40
    .byte $36, $2B, $31, $32, $33, $3D, $30, $2C
    .byte $2E, $0F, $00, $00, $00, $00, $00, $00 ; $50
    .byte $00, $00, $00, $00, $00, $00, $00, $00
    .byte $18, $02, $00, $00, $00, $00, $00, $00 ; $60
    .byte $00, $00, $00, $00, $00, $00, $00, $00

    .databank ?
.endblock

write_keyboard_init_data:
-
    lda 0, x
    bmi +
    sta SCC_A_CTRL
    inx
    lda 0, x
    sta SCC_A_CTRL
    inx
    bra -
+
    rts

wait:
    php
    a16
    lda #$9000
-
    dec a
    bne -
    plp
    rts

keyboard_init_data1:
    .byte $09, %10000000 ; Reset SCC channel A
    .byte $0e, %00000000 ; Stop baudrate generator
    .byte $01, %00000000 ; Disable interrupt
    .byte $03, %11000000 ; Disable serial input
    .byte $05, %01100010 ; Disable serial output
    .byte $0f, %00000000 ; Disable all status interrupts
    .byte $00, %00010000 ; Reset status interrupt
    .byte $00, %00010000 ; Reset status interrupt
    .byte $04, %01000101 ; Set StopBit-1,NonParity
    .byte $0b, %11010100 ; Set clock mode
    .byte $ff

keyboard_init_data2:
    .byte $0c, %00000110 ; Set baurate status low
    .byte $0d, %00000000 ; Set baurate status high
    .byte $0e, %00000001 ; start Baudrate generator
    .byte $05, %11101000 ; Enable serial output DTR=L,RTS=H
    .byte $03, %11000001 ; Enable serial input
    .byte $ff
    
; ===========================================================================
;                                FLOPPY DISK I/O
; ===========================================================================

init_fdd:
    php
    a8i8
    phb

    phk                 ; databank to 0
    plb

    lda #FDC_RESET
    jsr fd_aux_tx

    jsr fd_recalibrate_twice
    lda #$ff
    sta current_track
    lda #0
    sta track_dirty

    plb
    plp
    rts

.databank 0

; Writes A to the FDC data register.

.as
.xs
fd_tx:
    -
        bit FD72069_STATUS
    bpl -               ; wait until RQM (the top bit) is high
    sta FD72069_DATA
    rts

; Writes A to the FDC aux register.

.as
.xs
fd_aux_tx:
    -
        bit FD72069_STATUS
    bpl -               ; wait until RQM (the top bit) is high
    sta FD72069_STATUS
    rts

; Reads status from the FDC data register, into the fdc_status buffer.

.as
.xs
fd_read_status:
.block
    ldx #0
loop:
    -
        bit FD72069_STATUS
    bpl -               ; wait until RQM (the top bit) is high
    bvc exit            ; if DIO is low, there is no more data
    lda FD72069_DATA
    sta fdc_status, x
    inx
    bra loop

exit:
    rts
.endblock

; Turns the motor on.

.as
.xs
fd_motor_on:
    lda #FDC_START_CLOCK
    jsr fd_aux_tx
    lda #FDC_RESET_STDBY
    jsr fd_aux_tx
    jsr fd_read_status
    rts

; Turns the motor off again.

.as
.xs
fd_motor_off:
    lda #FDC_SET_STDBY
    jmp fd_aux_tx

; Performs the SENSE DRIVE STATE command, returning S3 in A.

fd_sense_drive_state:
    lda #FDC_SNSDEV
    jsr fd_tx
    lda #$00            ; head 0, drive 0
    jsr fd_tx
    jsr fd_read_status
    lda fdc_status+0
    rts

; Waits for the drive to become ready. Returns C on error. Preserves A.

.as
.xs
fd_wait_until_drive_ready:
.block
    pha
    jsr fd_motor_on
    -
        jsr fd_sense_drive_state
        bit #%00100000
        bne exit

        x16             ; short pause
        ldx #0
        -
            dex
        bne -
        x8
    bra -
exit:
    pla
    clc
    rts
.endblock

; Performs the RECALIBRATE command.

.as
.xs
fd_recalibrate:
    jsr fd_wait_until_drive_ready
    lda #FDC_RECALIBRATE
    jsr fd_tx
    lda #0              ; head 0, drive 0
    jsr fd_tx
    ; falls through
fd_wait_for_seek_ending:
    lda #FDC_SNSINT
    jsr fd_tx
    jsr fd_read_status

    lda fdc_status+0
    bit #%00100000      ; SE, seek end
    beq fd_wait_for_seek_ending
    clc
    rts

; Recalibrates twice (to get the entire 80 track range).

.as
.xs
fd_recalibrate_twice:
    jsr fd_recalibrate
    bcs +
        jsr fd_recalibrate
    +
    rts

; Seeks to physical track A (i.e. 0..79).

.as
.xs
fd_seek:
.block
    pha
    jsr fd_wait_until_drive_ready
    bcs exit

    pha
    lda #FDC_SEEK
    jsr fd_tx
    lda #0              ; head 0, drive 0
    jsr fd_tx
    pla                 ; track number
    jsr fd_tx
    jsr fd_wait_for_seek_ending
exit:
    pla
    rts
.endblock

; Reads logical track A (0..159) into the track buffer.

.as
.xs
fd_read_logical_track:
.block
    tay
    lda #$66            ; READ SECTORS
    jsr fd_setup_read_or_write

    php
    i16

    ldx #0
    ldy #FDD_TRACK_SIZE
    -
        lda FD72069_STATUS
        bpl -           ; RQM low? keep waiting
        asl a           ; DIO now top bit
        asl a           ; EXM now top bit
        bpl +           ; if low, transfer complete

        lda FD72069_DATA
        sta track_buffer, x
        inx
        dey
    bne -
    +

    plp
    ; Fall through
.endblock
fd_complete_transfer:
    lda FD72069_TC      ; reading this nudges the TC bit
    jsr fd_read_status

    ; Parsing the status code is fiddly, because we're allowed a readfail if EN
    ; is set.

    lda fdc_status+1
    asl a               ; EN->C
    lda fdc_status+0
    rol a               ; IC6->b7, IC7->C, EN->b0
    rol a               ; IC6->C, IC7->b0, EN->b1
    rol a               ; IC6->b0, IC7->b1, EN->b2
    and #7              ; clip off stray bits

    ; This gives us a number from 0..7 which is our error. We use this
    ; bitmap to determine whether it's fatal or not.
    ; EN, IC7, IC6
    ; 0    ; OK
    ; 1    ; readfail
    ; 1    ; unknown command
    ; 1    ; disk removed
    ; 0    ; OK
    ; 0    ; reached end of track
    ; 1    ; unknown command
    ; 1    ; disk removed

    inc a
    tax
    lda #%10001100
    -
        asl a
        dex
    bne -

    ; The appropriate bit from the bitmap is now in C.
    rts

; Writes logical track A (0..159) from the track buffer.

.as
.xs
fd_write_logical_track:
.block
    tay
    lda #$65            ; WRITE SECTORS
    jsr fd_setup_read_or_write

    php
    i16

    ldx #0
    ldy #FDD_TRACK_SIZE
    -
        lda FD72069_STATUS
        bpl -           ; RQM low? keep waiting
        asl a           ; DIO now top bit
        asl a           ; EXM now top bit
        bpl +           ; if low, transfer complete

        lda track_buffer, x
        sta FD72069_DATA
        inx
        dey
    bne -
    +

    plp
    bra fd_complete_transfer
.endblock

; Sends the commands to do a read or write. Main opcode in A, logical track
; number in Y.

.as
.xs
fd_setup_read_or_write:
    pha
    tya
    lsr a               ; logical track to physical track
    jsr fd_seek
    pla

    jsr fd_tx           ; 0: opcode

    tya
    and #1
    asl a
    asl a
    jsr fd_tx           ; 1: head in bit 2, drive 0

    tya
    lsr a
    jsr fd_tx           ; 2: track, again

    tya
    and #1
    jsr fd_tx           ; 3: logical head, again

    lda #1
    jsr fd_tx           ; 4: start sector, always 1

    lda #2
    jsr fd_tx           ; 5: bytes per sector, always 512

    lda #FDD_TRACK_SIZE/512
    jsr fd_tx           ; 6: last sector (*inclusive*)

    lda #27
    jsr fd_tx           ; 7: gap 3 length (27 is standard for 3.5" drives)

    lda #0
    jsr fd_tx           ; 8: sector length (unused)

    rts

.databank ?

; ===========================================================================
;                                    DRIVERS
; ===========================================================================

driver_handler .macro jt, ld=tya
    phb
    phd
    a8i8

    xba             ; assemble XA into a 16-bit A parameter
    txa
    xba

    pha
    \ld
    asl a
    tax

    lda #$7f        ; databank to $7f0000 so we can read supervisor RAM
    pha
    plb
    pea #$2100      ; direct page to $2100 so we can write to video registers
    pld

    pla
    jsr (\jt, x)

    pld
    plb
    rtl
.endmacro

; --- SCREEN driver ---------------------------------------------------------

.databank $7f
.dpage $2100

screen_handler:
    driver_handler screen_driver_table

screen_driver_table:
    .word screen_version
    .word screen_getsize
    .word screen_clear
    .word screen_setcursor
    .word screen_getcursor
    .word screen_putchar
    .word screen_putstring
    .word screen_getchar
    .word screen_showcursor
    .word screen_scrollup
    .word screen_scrolldown
    .word screen_cleartoeol
    .word screen_setstyle

fail:
    sec
    rts

.as
.xs
screen_version:
    lda #0
    clc
    rts

.as
.xs
screen_getsize:
    lda #SCREEN_WIDTH-1
    ldx #SCREEN_HEIGHT-1
    clc
    rts

screen_clear:
    php

    a16i16
    lda #0
    sta cursorp

    lda style_word
    sta map1_mirror
    sta map2_mirror

    lda #SCREEN_WIDTH*SCREEN_HEIGHT*2/2 - 3
    ldx #<>map1_mirror
    ldy #<>map1_mirror + 2
    mvn #`map1_mirror, #`map1_mirror

    lda #SCREEN_WIDTH*SCREEN_HEIGHT*2/2 - 3
    ldx #<>map2_mirror
    ldy #<>map2_mirror + 2
    mvn #`map2_mirror, #`map2_mirror

    plp
    rts

.as
.xs
screen_setcursor:
    sta ptr
    a16
    and #$ff00
    lsr a
    lsr a
    a8
    ora ptr
    a16
    sta cursorp
    rts

.as
.xs
screen_getcursor:
    lda cursorp
    and #SCREEN_WIDTH-1
    pha

    a16
    lda cursorp
    asl a
    asl a
    a8

    xba
    tax
    pla
    rts

.as
.xs
screen_getchar:
    jsr get_current_key
    tax                 ; set flags
    bne +
        sec
        rts
    +

    stz pending_key

    clc
    rts

.as
.xs
screen_showcursor:
    pha
    lda #CURSOR_SHOWN
    trb screen_flags
    plx                 ; sets Z flag
    beq +
    tsb screen_flags
+
    rts

; Calculates the address relative to map1_mirror.

calculate_screen_address:
.block
    php
    a16

    lda @l cursorp      ; long address to make independent of databank
    lsr a
    bcs +
        ; clc ; carry clear from previous instruction
        adc #(map2_mirror - map1_mirror) >> 1
    +
    asl a

    plp
    rts
.endblock

.as
.xs
screen_putchar:
    php
    a16i16
    pha

    jsr calculate_screen_address
    tax

    pla
    sec
    sbc #$0020              ; convert to tile number
    asl a                   ; tiles come in pairs
    and #$00ff
    ora style_word          ; priority bit and palette
    sta map1_mirror, x

    inc cursorp

    plp
    rts

.as
.xs
screen_putstring:
    php
    a16i16
    tax

    lda cursorp
    pha

    -
        jsr calculate_screen_address
        inc cursorp
        tay

        a8
        lda $7e0000, x
        a16
        beq +
        sec
        sbc #$0020              ; convert to tile number
        asl a                   ; tiles come in pairs
        and #$00ff
        ora style_word          ; priority bit and palette
        sta map1_mirror, y
        inx
        bra -
    +

    pla
    sta cursorp

    plp
    rts

.as
.xs
screen_scrollup:
    php
    a16i16
    phb

    ; Actually do the scroll.

    lda #(SCREEN_HEIGHT-1)*32*2 - 1
    ldx #<>(map1_mirror + 1*32*2)
    ldy #<>(map1_mirror + 0*32*2)
    mvn #`map1_mirror, #`map1_mirror

    lda #(SCREEN_HEIGHT-1)*32*2 - 1
    ldx #<>(map2_mirror + 1*32*2)
    ldy #<>(map2_mirror + 0*32*2)
    mvn #`map2_mirror, #`map2_mirror

    ; Blank the bottom line.

    lda style_word
    sta map1_mirror + (SCREEN_HEIGHT-1)*32*2
    sta map2_mirror + (SCREEN_HEIGHT-1)*32*2

    lda #(32*2) - 3
    ldx #<>(map1_mirror + (SCREEN_HEIGHT-1)*32*2)
    ldy #<>(map1_mirror + (SCREEN_HEIGHT-1)*32*2 + 2)
    mvn #`map1_mirror, #`map1_mirror

    lda #(32*2) - 3
    ldx #<>(map2_mirror + (SCREEN_HEIGHT-1)*32*2)
    ldy #<>(map2_mirror + (SCREEN_HEIGHT-1)*32*2 + 2)
    mvn #`map2_mirror, #`map2_mirror

    plb
    plp
    rts

.as
.xs
screen_scrolldown:
    php
    a16i16
    phb

    ; Actually do the scroll.

    lda #(SCREEN_HEIGHT-1)*32*2 - 1
    ldx #<>(map1_mirror + (SCREEN_HEIGHT-2)*32*2)
    ldy #<>(map1_mirror + (SCREEN_HEIGHT-1)*32*2)
    mvp #`map1_mirror, #`map1_mirror

    lda #(SCREEN_HEIGHT-1)*32*2 - 1
    ldx #<>(map2_mirror + (SCREEN_HEIGHT-2)*32*2)
    ldy #<>(map2_mirror + (SCREEN_HEIGHT-1)*32*2)
    mvp #`map2_mirror, #`map2_mirror

    ; Blank the top line.

    lda style_word
    sta map1_mirror
    sta map2_mirror

    lda #(32*2/2) - 3
    ldx #<>map1_mirror
    ldy #<>(map1_mirror + 2)
    mvn #`map1_mirror, #`map1_mirror

    lda #(32*2/2) - 3
    ldx #<>map2_mirror
    ldy #<>(map2_mirror + 2)
    mvn #`map2_mirror, #`map2_mirror

    plb
    plp
    rts

.as
.xs
screen_cleartoeol:
    php
    a16i16

    lda cursorp
    pha

    -
        jsr calculate_screen_address
        tax

        lda style_word
        sta map1_mirror, x

        inc cursorp
        lda cursorp
        and #63
        bne -
    
    pla
    sta cursorp
    plp
    rts

.as
.xs
screen_setstyle:
    ldx #$20
    and #STYLE_REVERSE
    beq +
        ldx #$24
    +
    stx style_byte
    rts

nmi_handler:
.block
    phx
    phy
    phd
    phb

    a16i16
    phk
    plb             ; databank to 0 so we can read/write registers
    pea #$4300      ; direct page to $4300 for fast access to DMA registers
    pld
    .databank 0
    .dpage $4300

    a8
    lda RDNMI       ; reset NMI flag

    lda #%10000000       ; force blank
    sta INIDISP

    lda #%10000000       ; autoincrement by one word
    sta VMAIN
   
    ; DMA the tilemaps.

    lda #%00000001      ; CPU->PPU, no HDMA, two registers write once,
    sta DMAPx + $70
    lda #<VMDATAL       ; destination address
    sta BBADx + $70
    lda #`map1_mirror   ; source bank
    ldx #<>map1_mirror  ; source address
    sta A1Bx + $70
    stx A1TxL + $70
    ldx #vram_mirror_end - vram_mirror_start
    stx DASxL + $70     ; number of bytes to transfer
    ldx #VRAM_MAP1_LOC>>1 ; word address
    stx VMADDL          ; destination VRAM address
    lda #%10000000      ; DMA enable
    sta MDMAEN

    lda tick_counter
    inc a
    sta tick_counter
    and #64
    beq +
    lda screen_flags
    bpl +
        a16
        jsr calculate_screen_address
        lsr a
        sta VMADDL
        asl a
        tax
        lda map1_mirror, x
        eor #$0400
        sta VMDATAL
    +

    a8
    lda #%00001111      ; screen on, maximum brightness
    sta INIDISP

    a16i16
    plb
    pld
    ply
    plx
    rts
.endblock

.databank ?
.dpage ?

; --- TTY driver ------------------------------------------------------------

.databank $7f
.dpage $2100

tty_handler:
    driver_handler tty_driver_table

tty_driver_table:
    .word tty_const
    .word tty_conin
    .word tty_conout

; Returns 0xff if no key is pending, 0 if one is.

tty_const:
    jsr get_current_key
    ldx #0
    cmp #0
    beq +
    dex
+
    txa
    
    clc
    rts

; Blocks and waits for a keypress.

.as
.xs
tty_conin:
    -
        jsr screen_getchar
        bcs -
    rts

tty_conout:
.block
    php
    i8
    a16

    tax
    cpx #13
    bne +
        lda #63
        trb cursorp
        bra exit
    +
    cpx #127
    bne +
        dec cursorp

        a16i16
        jsr calculate_screen_address
        tax
        stz map1_mirror, x
        i8

        bra exit
    +
    cpx #10
    bne +
        lda cursorp
        and #$ffc0
        clc
        adc #64
        sta cursorp
        bra maybescroll
    +

    i16
    jsr screen_putchar

    lda cursorp
maybescroll:
    cmp #SCREEN_WIDTH * SCREEN_HEIGHT
    bne +
        jsr screen_scrollup
        lda #SCREEN_WIDTH * (SCREEN_HEIGHT-1)
        sta cursorp
    +

exit:
    plp
    clc
    rts
.endblock

.databank ?
.dpage ?

; --- I/O handling ----------------------------------------------------------

bios_seldsk:
    sta selected_disk
    rtl

bios_setdma:
    phx
    pha
    a16i16

    pla             ; pop address as a 16-bit value
    sta dma

    rtl

bios_setsec:
    phx
    pha
    rep #$30        ; A/X/Y 16-bit

    plx             ; pop address as a 16-bit value
    lda 0,b,x       ; get bottom two bytes of sector number
    sta sector+0
    a8
    lda 2,b,x       ; get top byte of sector number
    sta sector+2

    rtl

bios_read:
    driver_handler bios_read_table, lda selected_disk
bios_read_table:
    .word bios_read_romdisk
    .word bios_read_ramdisk
    .word bios_read_fdddisk

bios_read_romdisk:
    a16i16

    pea #0          ; direct page to $0000 for pointer access
    pld

    ; Compute the address in the romdisk.

    lda sector+0    ; bottom two bytes of sector number
    lsr a
    clc
    adc #$4100      ; patch in address of ROMdisk
    sta ptr+1, d    ; top two bytes of address
    a8
    lda sector+0
    ror a
    lda #0
    ror a
    sta ptr+0, d    ; bottom byte of address

read_sector_from_ptr:
    a8i8
    ldy #$7f
-
    lda [ptr, d], y
    sta [dma, d], y
    dey
    bpl -

    clc
    rts

calculate_ramdisk_address:
    php
    a16i16

    ; Compute the address in the romdisk. As this is 256kB maximum,
    ; it can only fit 2048 sectors, so (luckily) the entire value is
    ; in the bottom two bytes.

    lda sector+0    ; bottom two bytes of sector number
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a           ; divide by 64
    a8
    clc
    adc #$30        ; first bank where SRAM is found
    cmp #$40        ; bounds check
    bcs +
    sta ptr+2, d

    a16
    lda sector+0
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a           ; multiply by 128
    and #$1fff      ; 8kB chunks
    ora #$6000      ; address in each bank
    sta ptr+0, d
    
    clc
    plp
    rts
+
    sec
    plp
    rts

bios_read_ramdisk:
    pea #0          ; direct page to $0000 for pointer access
    pld

    jsr calculate_ramdisk_address
    bcs +
    bra read_sector_from_ptr
+
    rts


; Switches the track in the buffer to logical track A (i.e. 0..159).

.as
.xs
change_fdd_track:
.block
    cmp current_track
    clc
    beq exit

    pha
    lda track_dirty
    bpl +
        lda current_track
        jsr fd_write_logical_track
        lda #0
        sta track_dirty
    +
    pla
    sta current_track
    jsr fd_read_logical_track
exit:
    rts
.endblock
    
; Sets ptr to the pointer to the current sector in the track buffer; returns the
; track number in A.

.as
.xs
calculate_fdd_address:
.block
    .dpage 0

    ; There are 18*512=0x1200 bytes per track; that's 72 CP/M sectors. We therefore
    ; need to divide the sector number by 72 to get the track number, the remainder
    ; being the sector offset.
    ;
    ; A full division routine sucks so we're just going to repeatedly subtract by 72.

    lda sector+0
    sta ptr+0
    lda sector+1
    sta ptr+1
    lda sector+2
    sta ptr+2

    ldx #0          ; track number
    -
        lda ptr+2
        ora ptr+1
        bne +       ; check for non-zero high bytes
        lda ptr+0
        cmp #FDD_TRACK_SIZE/128
        bcc done    ; we're done

    +
        inx         ; increase track count

        sec         ; subtract the number of sectors
        lda ptr+0
        sbc #FDD_TRACK_SIZE/128
        sta ptr+0
        lda ptr+1
        sbc #0
        sta ptr+1
        lda ptr+2
        sbc #0
        sta ptr+2
    bra -
done:
    ; Shift the sector number left by seven bits to get the offset.

    lda ptr+0
    lsr a
    sta ptr+1
    lda #0
    ror a
    sta ptr+0

    ; Add the address of the track buffer.

    lda #`track_buffer
    sta ptr+2
    lda ptr+0
    clc
    adc #<track_buffer
    sta ptr+0
    lda ptr+1
    adc #>track_buffer
    sta ptr+1

    txa             ; track number into A
    rts
.endblock

bios_read_fdddisk:
    pea #0          ; direct page to $0000 for pointer access
    pld

    phk             ; databank to zero for I/O access
    plb

    jsr calculate_fdd_address
    jsr change_fdd_track
    jmp read_sector_from_ptr

bios_write:
    driver_handler bios_write_table, lda selected_disk
bios_write_table:
    .word fail
    .word bios_write_ramdisk
    .word bios_write_fdddisk

.as
.xs
bios_write_ramdisk:
    pea #0          ; direct page to $0000 for pointer access
    pld

    jsr calculate_ramdisk_address
    bcs +

write_sector_to_ptr:
    ldy #$7f
-
    lda [dma, d], y
    sta [ptr, d], y
    dey
    bpl -

    clc
+
    rts

bios_write_fdddisk:
.block
    pea #0          ; direct page to $0000 for pointer access
    pld
    .dpage $0000

    phk             ; databank to zero for I/O access
    plb
    .databank 0

    pha
    jsr calculate_fdd_address
    jsr change_fdd_track
    jsr write_sector_to_ptr

    lda #$80
    sta track_dirty
    pla

    php
    tax             ; set flags
    beq +
        lda current_track
        jsr fd_write_logical_track
        lda #0
        sta track_dirty
    +
    plp
    rts
.endblock

; --- Jump table ------------------------------------------------------------

; This must be kept in sync with the values in globals.inc.

    * = $ff00
    jmp bios_seldsk
    jmp bios_setdma
    jmp bios_setsec
    jmp bios_read
    jmp bios_write
    jmp tty_handler
    jmp screen_handler

; --- ROM header ------------------------------------------------------------

    * = $ffc0

    ;      012345678901234567890
    .text 'CP/M-65 SNES         '
    .byte %00110001     ; fast, HiROM
    .byte $02           ; ROM + RAM + battery
    .byte 11            ; ROM size: 2024kB
    .byte 7             ; RAM size: 128kB
    .byte 0             ; country
    .byte 0             ; developer ID
    .byte 0             ; version
    .word 0             ; checksum complement (filled in later)
    .word 0             ; checksum (filled in later)

    ; Native mode vectors

    .word $ffff         ; reserved
    .word $ffff         ; reserved
    .word return_int     ; COP
    .word brk_n_entry    ; BRK
    .word return_int     ; ABT
    .word nmi_n_entry    ; NMI
    .word $ffff         ; reserved
    .word return_int     ; IRQ

     ; Emulation mode vectors

    .word $ffff         ; reserved
    .word $ffff         ; reserved
    .word return_int    ; COP
    .word $ffff         ; unused
    .word return_int    ; ABT
    .word nmi_e_entry   ; NMI
    .word start         ; reserved
    .word brk_e_entry   ; IRQ

* = $010000
.binary "+diskimage.img"

; vim: sw=4 ts=4 et
