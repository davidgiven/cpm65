#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "wait.inc"

job3      = 0x03
TRACK3    = 0x0c
SECTOR3   = 0x0d
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

CMDBUF_LEN = 0x2a
TRACK     = 0x80
SECTOR    = 0x81
DATA      = 0x85
EOIFLAG   = 0xf8
JOBNUM    = 0xf9

CMDBUF    = 0x200
LIMIT     = 0x276
F2CNT     = 0x278
FILTRK    = 0x280
FILSEC    = 0x285

BUFFER0   = 0x0300
BUFFER1   = 0x0400
BUFFER2   = 0x0500
BUFFER3   = 0x0600
SERPORT   = 0x1800
DISKCNT   = 0x1c00
DATA2     = 0x1c01

LEDBIT    = 0x08

LOOKUP    = 0xc44f
GIBYTE    = 0xca35
OPENTYP   = 0xd477
DOREAD    = 0xd586
DOWRIT    = 0xd58a
DOJOB     = 0xd58c

MAXSEC    = 0xf24b ; get number of sectors in track
JOBOK     = 0xf505
WAITSYNC  = 0xf556
DECODE    = 0xf7e8

NUMBER_OF_ZONES           = 0xfed6
SECTORS_PER_TRACK_TABLE   = 0xfed1
FIRST_TRACK_OF_ZONE_TABLE = 0xfed7

zproc _start, .code1
    zloop
    main_done:
        jsr recvbyte            ; get command byte, exit if ATN goes low

        cmp #'R'                ; read a sector
        zif eq
            jmp read_sector
        zendif
        cmp #'W'                ; write a sector
        zif eq
            jmp write_sector
        zendif
        cmp #'F'                ; read a file by track/sector
        zif eq
            jsr recv_xa
            jmp dump_file
        zendif
        cmp #'D'                ; read the directory
        zif eq
            ldx #18
            lda #1
            jmp dump_file
        zendif
        cmp #'T'                ; tests link integrity
        zif eq
            jmp test_link
        zendif

    main_error:
        lda #$ff                ; unknown command
        .byte 0x2c              ; skip next two bytes
    main_success:
        lda #0
        jsr sendbyte
    zendloop
zendproc

zproc recv_xa, .code5
    jsr recvbyte
    tax
    jmp recvbyte
zendproc

zproc recv_lba, .code6
    jsr recvbyte
    sta R0                      ; low byte of LBA
    jsr recvbyte
    sta R1                      ; high byte of LBA

    ldy NUMBER_OF_ZONES
    dey                         ; reverse count of zones
    ldx #1                      ; track number
    zloop
        lda R1
        zif eq                  ; LBA < 0x100
            lda R0
            cmp SECTORS_PER_TRACK_TABLE, y
            zbreakif lt
        zendif

        ; Subtract the number of sectors for this track and bump track counter.

        sec
        lda R0
        sbc SECTORS_PER_TRACK_TABLE, y
        sta R0
        zif cc
            dec R1
        zendif
        inx

        txa
        cmp FIRST_TRACK_OF_ZONE_TABLE, y
        zif eq
            ; Reached the end of this zone.

            dey
            zif mi
                iny
            zendif
        zendif
    zendloop

    ; Track already in Y.
    lda R0
    rts
zendproc

zproc read_sector, .code2
    jsr recv_lba
    jsr read_sector_xa

    lda #0                      ; report success
    jsr sendbyte
    jsr sendbuffer

    jmp main_done
zendproc

zproc write_sector, .code6
    jsr recv_lba
    pha
    txa
    pha
    jsr recvbuffer
    pla
    tax
    pla
    jsr write_sector_xa
    jmp main_success
zendproc

zproc sendbuffer, .code2
    ldx #0
    zrepeat
        lda BUFFER3, x
        jsr sendbyte
        inx
    zuntil eq
    rts
zendproc

zproc recvbuffer, .code6
    ldx #0
    zrepeat
        jsr recvbyte
        sta BUFFER3, x
        inx
    zuntil eq
    rts
zendproc

zproc write_sector_xa, .code6
    ldy #0x90
    .byte 0x2c          ; skip next two bytes
zproc read_sector_xa, .code6
    ldy #0x80
zproc read_write_sector_xa, .code6
    stx TRACK3
    sta SECTOR3
    lda #3              ; operate on buffer 3
    sta JOBNUM
    tya
    cli
    jsr blink
    jsr DOJOB
    jsr blink
    sei
    zif cs
        jmp main_error
    zendif
    rts
zendproc

zproc dump_file, .code6
    zrepeat
        jsr read_sector_xa             ; read sector at T/S in XA

        lda #254                ; default: a full sector
        ldx BUFFER3+0
        zif eq
            lda BUFFER3+1       ; oop, partial sector
            cmp #254
            zif ge
                lda #254
            zendif
        zendif
        sta R0                  ; number of bytes to send
        jsr sendbyte            ; ...and tell the client

        ; Send the data itself.

        ldx #0
        zrepeat
            lda BUFFER3+2, x
            jsr sendbyte
            inx
            cpx R0
        zuntil eq

        ; Go on to the next sector.

        lda BUFFER3+1           ; next sector
        ldx BUFFER3+0           ; next track
    zuntil eq
    
    jmp main_success
zendproc

zproc test_link, .code5
    jsr recvbuffer
    jsr sendbuffer
    jmp main_done
zendproc

; Sends a byte over the link. Preseves X (but not Y).

zlproc sendbyte, .code6
    ldy #0x02               ; assert DATA to signal that we're sending
    sty SERPORT

    sta zptmp
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    lda sendtbl, y          ; get the CLK, DATA pairs for low nybble
    pha
    lda zptmp
    and #0x0f
    tay

    lda #0x04
    zrepeat
        bit SERPORT         ; wait for CLK asserted
    zuntil ne

    lda #0                  ; release DATA
    sta SERPORT

    lda #0x04
    zrepeat
        bit SERPORT         ; wait for CLK released
    zuntil eq

    ; The SERPORT layout is %xxxxCxDx.

/* 2 */  lda sendtbl, y          ; get the CLK, DATA pairs for high nybble
/* 6 */  sta SERPORT
 
/* 10 */ asl a
/* 12 */ and #0x0f
/* 14 */ sta SERPORT
 
/* 18 */ pla
/* 22 */ sta SERPORT
 
/* 26 */ asl a
/* 28 */ and #0x0f
/* 30 */ sta SERPORT
 
/* 34 */ WAIT4
/* 38 */ lda #0x00                ; set CLK and DATA high
         sta SERPORT

    rts
zendproc

zlproc sendtbl, .code6
    ; Bit order:
    ;      0213
    .byte %1111 ; 0
    .byte %0111 ; 1
    .byte %1101 ; 2
    .byte %0101 ; 3
    .byte %1011 ; 4
    .byte %0011 ; 5
    .byte %1001 ; 6
    .byte %0001 ; 7
    .byte %1110 ; 8
    .byte %0110 ; 9
    .byte %1100 ; a
    .byte %0100 ; b
    .byte %1010 ; c
    .byte %0010 ; d
    .byte %1000 ; e
    .byte %0000 ; f
zendproc

zlproc disconnect, .code6
    jmp (0xfffc)
zendproc

; Returns the byte in A. Preserves X and Y.

zlproc recvbyte, .code1
    lda #0x08                ; assert CLK to signal that we're receiving
    sta SERPORT

    cli                     ; interrupts on while waiting
    lda #0x01
    zrepeat
        bit SERPORT         ; wait for DATA asserted
        zif mi
            jmp disconnect  ; if ATN released, stop
        zendif
    zuntil ne
    sei                     ; interrupts off while thinking

    lda #0                  ; release CLK
    sta SERPORT

    lda #0x01
    zrepeat
        bit SERPORT         ; wait for DATA to be released
    zuntil eq

    ; Worst-case delay is six cycles between the computer raising DATA and the
    ; drive noticing.
    ;
    ; SERPORT's layout is %xxxxxCxD

/* 2 */  WAIT4
/* 6 */  lda SERPORT             ; %xxxxx7x5

/* 10 */ asl a                   ; %xxxx7x5x
/* 12 */ WAIT4
/* 16 */ eor SERPORT             ; %xxxx7654

/* 20 */ asl a                   ; %xxx7654x
/* 22 */ asl a                   ; %xx7654xx
/* 24 */ asl a                   ; %x7654xxx
/* 26 */ WAIT6          
/* 32 */ eor SERPORT             ; %x76543x1

/* 36 */ asl a                   ; %76543x1x
/* 38 */ WAIT4
/* 42 */ eor SERPORT             ; %76543210

    rts
zendproc

zlproc blink, .code2
    pha
    lda DISKCNT
    eor #LEDBIT
    sta DISKCNT
    pla
    rts
zendproc
