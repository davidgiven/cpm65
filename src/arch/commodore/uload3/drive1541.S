#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

CMDBUF = 0x200
CMDBUF_LEN = 0x2a

DRIVEBUFFER = 0x600
TRACK_LIST = 0x680
SECTOR_LIST = 0x6c0

RETRIES = 5
LEDCTL = 0x1c00
LEDBIT = 0x08

job3      = 0x03
trk3      = 0x0c
sct3      = 0x0d
iddrv0    = 0x12
id        = 0x16
zptmp     = 0x1b
bufptr    = 0x30
track     = 0x7a
sector    = 0x7b
stack     = 0x7c

R0        = 0x86
R1        = 0x87
R2        = 0x88
R3        = 0x89
R4        = 0x8a

SERPORT   = 0x1800

SECPRETRK = 0xf24b ; get number of sectors in track
JOBOK     = 0xf505
WAITSYNC  = 0xf556
DECODE    = 0xf7e8

; Sets up the location of the directory.

zlproc drv_get_dir_ts, .drive
    lda #18
    sta track
    lda #1
    sta sector
    clc
    ; fall through
zlproc drv_flush, .drive
    rts
zendproc

; Sector read/write subroutine (from/to disk into a buffer). Returns !c if
; successful, c if error.

zlproc drv_readsector, .drive
    lda #0x80           ; read sector job code
    .byte 0x2c          ; skip next two bytes
zlproc drv_writesector, .drive
    lda #0x90           ; write sector job code
    sta zptmp
    lda track
    sta trk3
    lda sector
    sta sct3

    ldy #RETRIES
    jsr blink
    zrepeat
        lda zptmp
        sta job3

        cli
        zrepeat
            lda job3
        zuntil pl
        sei

        cmp #2          ; check status
        bcc blink       ; success

        lda id+0        ; check for ID change
        sta iddrv0+0
        lda id+1
        sta iddrv0+1

        dey
    zuntil eq
    sec
    rts
zendproc

zlproc blink, .drive
    lda LEDCTL
    eor #LEDBIT
    sta LEDCTL
    rts
zendproc

zlproc drv_send, .drive
    ldy #0x02           ; set DATA low to signal that we're sending
    sty SERPORT

    sta zptmp
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    lda sendtbl, y      ; get the CLK, DATA pairs for low nybble
    pha
    lda zptmp
    and #0x0f
    tay

    lda #0x04
    zrepeat
        bit SERPORT         ; wait for CLK low
    zuntil ne

    lda #0                  ; release DATA
    sta SERPORT

    lda #0x04
    zrepeat
        bit SERPORT         ; wait for CLK high
    zuntil eq

    ; 1 MHz code

    lda sendtbl, y          ; get the CLK, DATA pairs for high nybble
    sta SERPORT

    asl a
    and #0x0f
    sta SERPORT

    pla
    sta SERPORT

    asl a
    and #0x0f
    sta SERPORT

    nop
    nop
    lda #0x00                ; set CLK and DATA high
    sta SERPORT

    rts

sendtbl:
    .byte 0x0f, 0x07, 0x0d, 0x05
    .byte 0x0b, 0x03, 0x09, 0x01
    .byte 0x0e, 0x06, 0x0c, 0x04
    .byte 0x0a, 0x02, 0x08, 0x00
zendproc

zlproc drv_exit, .drive
    ldx stack
    txs
    rts
zendproc

; Returns the byte in A. Preserves X and Y.

zlproc drv_recv, .drive
    lda #0x08                ; CLK low to signal that we're receiving
    sta SERPORT

    cli                     ; interrupts on while waiting
    lda #0x01
    zrepeat
        bit SERPORT         ; wait for DATA low
        bmi drv_exit        ; if ATN released, stop
    zuntil ne
    sei                     ; interrupts off while thinking

    lda #0                  ; release CLK
    sta SERPORT

    lda #0x01
    zrepeat
        bit SERPORT         ; wait for DATA high
    zuntil eq

    nop
    nop
    lda SERPORT             ; get bits 7 and 5

    asl a
    nop
    nop
    eor SERPORT             ; get bits 6 and 4

    asl a
    asl a
    asl a
    cmp (0x00,x)            ; delay
    eor SERPORT             ; get 3 and 1

    asl a
    nop
    nop
    eor SERPORT             ; finally get 2 and 0

    rts
zendproc

zproc drv_recvstring, .drive
    ldy #0
    zloop
        jsr drv_recv
        sta CMDBUF, y
        zbreakif eq
        iny
    zendloop
    rts
zendproc

; Reads an LBA sector number and converts it to (track, sector).

zproc read_lba, .drive
    jsr drv_recv
    pha
    jsr drv_recv
    tax
    pla

    ldy #0
    zloop
        cpx #0
        zif eq
            cmp track_size_table, y
            zif cc
                iny     ; tracks are one-based.
                sty track
                sta sector
                rts
            zendif
        zendif

        sec
        sbc track_size_table, y
        zif cc
            dex
        zendif
        iny
    zendloop

track_size_table:
    .fill 17, 1, 21
    .fill 7, 1, 19
    .fill 6, 1, 18
    .fill 10, 1, 17
zendproc

zproc drv_start, .drive
    tsx
    stx stack
    ; fall through
zlproc drv_main, .drive
    zloop
    main_done:
        jsr drv_recv            ; get command byte, exit if ATN goes low

        cmp #'R'                ; read a sector
        beq read_sector
        cmp #'F'                ; load a file
        beq load_file

        lda #$ff                ; unknown command
        jsr drv_send
    zendloop

read_sector:
    jsr read_lba
    jsr drv_readsector

    ldx #0
    zrepeat
        lda DRIVEBUFFER, x
        jsr drv_send
        inx
    zuntil eq
    jmp main_done

load_file:
    jsr drv_recvstring

    jsr drv_get_dir_ts          ; locate directory
    zrepeat
        jsr drv_readsector

        ; R0 is the offset of the current dirent.

        lda #2
        sta R0

        zrepeat
            ldx #0
            ldy R0

            zloop
                lda CMDBUF, x
                zif eq
                    lda #0xa0
                zendif
                cmp DRIVEBUFFER+3, y
                zbreakif ne
                inx
                iny
                cmp #0xa0
                beq dirent_found
            zendloop

            clc
            lda R0
            adc #32
            sta R0
            cmp #226
        zuntil eq

        lda DRIVEBUFFER+0
        sta track
        lda DRIVEBUFFER+1
        sta sector
        cmp track
    zuntil eq

    ; Not found.

    lda #0xff
    jsr drv_send
    jmp main_done

dirent_found:
    ldy R0
    iny
    zrepeat
        lda DRIVEBUFFER+0, y
        sta track
        lda DRIVEBUFFER+1, y
        sta sector

        jsr drv_readsector

        lda #254                ; default: a full sector
        ldx DRIVEBUFFER+0
        zif eq
            lda DRIVEBUFFER+1   ; oop, partial sector
        zendif
        sta R0                  ; number of bytes to send
        jsr drv_send            ; ...and tell the client

        ; Send the data itself.

        ldx #0
        zrepeat
            lda DRIVEBUFFER+2, x
            jsr drv_send
            inx
            cpx R0
        zuntil eq

        ; Go on to the next sector.

        ldy #0
        lda DRIVEBUFFER+0
    zuntil eq
    
    label:
    jmp main_done
zendproc
