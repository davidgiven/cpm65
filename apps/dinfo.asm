\ dinfo - info about current drive

\ Copyright © 2023 by David Given and Ivo van Poorten

\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

\ C version: 727 bytes
\ asm version: 512 bytes

.include "cpm65.inc"

.zp dpb, 2

.zp ptr1, 2 \ clobbered by print
.zp pad, 2  \ idem
.zp val1, 2
.zp dsm, 2  \ actually dsm+1 which is needed in calculations two times
            \ and as an endpoint during free space calculations
.zp bsh, 1
.zp count, 2

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

\ store dsm+1 as we need it again later

    ldy #DPB_DSM
    lda (dpb),y
    clc
    adc #1
    sta val1
    sta dsm
    iny
    lda (dpb),y
    adc #0
    sta val1+1
    sta dsm+1

    lda val1
    ldx val1+1
    jsr print16padded

    lda #<blocks
    ldx #>blocks
    jsr printstring

\ shift by BSH

    ldy #DPB_BSH
    lda (dpb),y
    sta bsh
    tax

    jsr shift_val1_left_by_x

    lda val1
    ldx val1+1
    jsr print16padded
 
    lda #<capacity
    ldx #>capacity
    jsr printstring

\ directory entries

    ldy #DPB_DRM
    iny
    lda (dpb),y
    tax
    dey
    lda (dpb),y
    clc
    adc #1
    .zif cs
        inx
    .zendif
    jsr print16padded

    lda #<direntries
    ldx #>direntries
    jsr printstring

\ checked entries

    ldy #DPB_CKS
    iny
    lda (dpb),y
    tax
    dey
    lda (dpb),y
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
    iny
    lda (dpb),y
    tax
    dey
    lda (dpb),y
    jsr print16padded

    lda #<ressect
    ldx #>ressect
    jsr printstring

\ free space

    lda #<free
    ldx #>free
    jsr printstring

\ count unused blocks in val1

    ldy #BDOS_GET_ALLOC_VECTOR
    jsr BDOS
    sta ptr1
    stx ptr1+1

    lda #0
    sta count
    sta count+1
    sta val1
    sta val1+1
    tay

.label stop

    .zrepeat
        lda (ptr1),y
        ldx #7
        .zrepeat
            lsr A
            .zif cc
                inc val1
                .zif eq
                    inc val1+1
                .zendif
            .zendif
            inc count
            .zif eq
                inc count+1
            .zendif
            pha
            lda count+1
            cmp dsm+1
            .zif eq
                lda count
                cmp dsm
                beq stop    \ stop condition
            .zendif
            pla
            dex
        .zuntil mi

        inc ptr1
        .zif eq
            inc ptr1+1
        .zendif
    .zuntil eq          \ which is never

stop:
    pla                 \ leftover byte

    ldx bsh
    dex
    dex
    dex
    stx count           \ save bsh-3 for later
    .zif ne
        jsr shift_val1_left_by_x
    .zendif

    lda val1
    ldx val1+1
    ldy #0
    jsr print16paddedY

    lda #<kilobyte
    ldx #>kilobyte
    jsr printstring

    lda #'/'
    ldy #BDOS_CONOUT
    jsr BDOS

    lda dsm
    sta val1
    lda dsm+1
    sta val1+1
    ldx count
    .zif ne
        jsr shift_val1_left_by_x
    .zendif

    lda val1
    ldx val1+1
    ldy #0
    jsr print16paddedY

    lda #<kilobyte
    ldx #>kilobyte
    jsr printstring

    lda #<crlf
    ldx #>crlf
    jmp printstring     \ finished

.zproc shift_val1_left_by_x
    clc
    .zrepeat
        rol val1
        rol val1+1
        dex
    .zuntil eq
    rts
.zendproc

.zproc printstring
    ldy #BDOS_PRINTSTRING
    jmp BDOS
.zendproc

\ Prints XA in decimal. Y is the padding char or 0 for no padding.

.zproc print16padded
    ldy #' '            \ always pad with ' '
.zendproc

.zproc print16paddedY
    sta ptr1+0
    stx ptr1+1
    sty pad

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
            lda pad                 \ get the padding character
            beq skip                \ if zero, no padding
            bne justprint           \ otherwise, use it
        .zendif

        ldx #'0'                    \ printing a digit, so reset padding
        stx pad
        ora #'0'                    \ convert to ASCII
    justprint:
        ldy #BDOS_CONOUT
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
    .byte "drive error"
crlf:
    .byte "\r\n$"
blocks:
    .byte " : Number of blocks\r\n$"
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
free:
    .byte "Free space: $"
kilobyte:
    .byte "kB$"

