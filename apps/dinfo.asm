\ dinfo - info about current drive

\ Copyright © 2023 by David Given and Ivo van Poorten

\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

\ C version: 727 bytes
\ asm version: 512 bytes

.bss pblock, 165
cpm_fcb = pblock

BDOS = start-3

BDOS_CONIO             =  6
BDOS_PRINTSTRING       =  9
BDOS_SELECT_DRIVE      = 14
BDOS_GET_CURRENT_DRIVE = 25
BDOS_GET_DPB           = 31

DPB_BSH     = 2
DPB_EXM     = 4
DPB_DSM     = 5
DPB_DRM     = 7
DPB_CKS     = 11
DPB_OFF     = 13

FCB_DR      = 0

.zp dpb, 2

.zp ptr1, 2 \ clobbered by print
.zp ptr2, 2 \ idem

val1 = ptr1
val2 = ptr2
.zp val3, 2

start:
    ldy #BDOS_GET_CURRENT_DRIVE
    jsr BDOS
    sta val1

    lda cpm_fcb
    beq keepcur

    sta val1
    dec val1        \ fcb.dr - 1

keepcur:
    lda val1
    ldy #BDOS_SELECT_DRIVE
    jsr BDOS

    ldy #BDOS_GET_CURRENT_DRIVE
    jsr BDOS

    cmp val1
    beq success

    lda #<error
    ldx #>error
    ldy #BDOS_PRINTSTRING
    jsr BDOS
    rts

success:
    ldy #BDOS_GET_DPB
    jsr BDOS
    sta dpb
    stx dpb+1

\ drive capacity in sectors

    lda #1
    sta val1
    lda #0
    sta val1+1
    sta val3
    sta val3+1

    ldy #DPB_DSM
    lda (dpb),y
    clc
    adc #1
    sta val2
    iny
    lda (dpb),y
    adc #0
    sta val2+1

    \ crude mul by multiple addition
    \ val3 = val1 * val2

muladd:
    lda val3
    clc
    adc val1
    sta val3
    lda val3+1
    adc val1+1
    sta val3+1

    lda val2
    bne dec16
    dec val2+1
dec16:
    dec val2

    lda val2
    clc
    adc val2+1
    bne muladd

    \ shift after muladd, saves 2^bsh adds

    ldy #DPB_BSH
    lda (dpb),y
    tax

    clc
shift16:
    rol val3
    rol val3+1
    dex
    bne shift16

    lda val3
    ldx val3+1
    jsr print16padded
 
    lda #<capacity
    ldx #>capacity
    jsr printstring

\ directory entries

    ldy #DPB_DRM
    lda (dpb),y
    clc
    adc #1
    ldx #0
    jsr print16padded

    lda #<direntries
    ldx #>direntries
    jsr printstring

\ checked entries

    ldy #DPB_CKS
    lda (dpb),y
    ldx #0
    jsr print16padded

    lda #<chkentries
    ldx #>chkentries
    jsr printstring

\ records per entry
\ instead of (dpb->exm+1)*128, we do (dpb->exm+1)*256/2

    ldy #DPB_EXM
    lda (dpb),y
    clc
    adc #1
    ror A
    tax         \ no intermediate store
    lda #0
    ror A
    jsr print16padded

    lda #<recperentry
    ldx #>recperentry
    jsr printstring

\ reserved sectors

    ldy #DPB_OFF
    lda (dpb),y
    ldx #0
    jsr print16padded

    lda #<ressect
    ldx #>ressect
    jsr printstring

    rts

.zproc printstring
    ldy #BDOS_PRINTSTRING
    jmp BDOS
.zendproc

\ Prints XA in decimal. Y is the padding char or 0 for no padding.

.zproc print16padded
    ldy #' '            \ always pad with ' '
    sta ptr1+0
    stx ptr1+1
    sty ptr2+0

    .label dec_table
    .label skip
    .label justprint

    ldy #8
    .zrepeat
        ldx #0xff
        sec
        .zrepeat
            lda ptr1+0
            sbc dec_table+0, y
            sta ptr1+0

            lda ptr1+1
            sbc dec_table+1, y
            sta ptr1+1

            inx
        .zuntil cc

        lda ptr1+0
        adc dec_table+0, y
        sta ptr1+0

        lda ptr1+1
        adc dec_table+1, y
        sta ptr1+1

        tya
        pha
        txa
        pha

        .zif eq                     \ if digit is zero, check padding
            lda ptr2+0              \ get the padding character
            beq skip                \ if zero, no padding
            bne justprint           \ otherwise, use it
        .zendif

        ldx #'0'                    \ printing a digit, so reset padding
        stx ptr2+0
        ora #'0'                    \ convert to ASCII
    justprint:
        ldy #BDOS_CONIO
        jsr BDOS
    skip:
        pla
        tax
        pla
        tay

        dey
        dey
    .zuntil mi
    rts

dec_table:
   .word 1, 10, 100, 1000, 10000
.zendproc

error:
    .byte "drive error\r\n$"
capacity:
    .byte " : Sectors Capacity\r\n$"
direntries:
    .byte " : Directory Entries\r\n$"
chkentries:
    .byte " : Checked Entries\r\n$"
recperentry:
    .byte " : Records Per Entry\r\n$"
ressect:
    .byte " : Reserved Sectors\r\n$"


