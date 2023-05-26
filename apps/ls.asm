\ ls - list files

\ Copyright © 2023 by Ivo van Poorten and David Given

\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

\   C version: 2051 bytes
\ asm version: 1024 bytes (w/ flags)

.include "cpm65.inc"

MAXFILES = 255

OFFSET_NAME = 0
OFFSET_RECS = 11
OFFSET_LAST = 13
FULL_SIZE   = 14

.bss files, 3570    \ MAXFILES * 14
.bss idx, 510       \ MAXFILES * 2

.zp ptr1, 2 \ clobbered by print
.zp ptr2, 2 \ idem

.zp tmp, 4
.zp nfiles, 1
.zp ret, 1
count=ret
endcondx=tmp+3

.zp pentry, 2

.zp pidx, 2
.zp pidx2, 2
.zp pfile, 2
.zp pfile2, 2

start:
.expand 1

    ldy #BDOS_GET_CURRENT_DRIVE
    jsr BDOS
    sta tmp

    lda cpm_fcb
    beq keepcur

    sta tmp
    dec tmp        \ fcb.dr - 1

keepcur:
    lda tmp
    ldy #BDOS_SELECT_DRIVE
    jsr BDOS

    ldy #BDOS_GET_CURRENT_DRIVE
    jsr BDOS

    cmp tmp
    beq success

    lda #<error
    ldx #>error
    jmp print_string    \ exits

success:
    lda cpm_fcb+1
    cmp #' '
    bne no_fill_wildcards

    ldy #10
    lda #'?'
fill:
    sta cpm_fcb+1,y
    dey
    bpl fill

no_fill_wildcards:
    lda #0
    sta nfiles

    ldy #BDOS_SET_DMA
    lda #<cpm_default_dma
    ldx #>cpm_default_dma
    jsr BDOS

\ collect_files

    lda #'?'
    sta cpm_fcb+12          \ EX, find all extents, not just the first

    ldy #BDOS_FINDFIRST
    lda #<cpm_fcb
    ldx #>cpm_fcb
    jsr BDOS

    jmp test_ff

    .label too_many_files

    .zrepeat
        asl A
        asl A
        asl A
        asl A
        asl A        \ * 32
        clc
        adc #<cpm_default_dma
        sta pentry
        lda #0
        adc #>cpm_default_dma
        sta pentry+1
    
    \ find file in list
    
        lda #<files-1   \ minus 1 so we can use the same Y index [1-11]
        sta pfile
        lda #>files-1
        sta pfile+1
    
        ldx nfiles
        jmp test_nfiles
    
        .label found_name
        .label inc_pfile
    
        .zrepeat
    
            ldy #11
    
            .zrepeat
                lda (pfile),y
                cmp (pentry),y
                bne inc_pfile       \ decide it is not equal
                dey
            .zuntil eq
            beq found_name          \ bra
    
        inc_pfile:
            lda pfile
            clc
            adc #14
            sta pfile
            .zif cs
                inc pfile+1
            .zendif
    
            dex
    
    test_nfiles:
    
        .zuntil eq
    
    \ not found, add to end of list.
    \ note that pfile still points to list entry - 1
    
        ldy #11
        .zrepeat
            lda (pentry),y
            sta (pfile),y
            dey
        .zuntil eq
    
        ldy #12
        lda #0          \ init to zero
        sta (pfile),y
        iny
        sta (pfile),y
        iny
        sta (pfile),y
    
        inc nfiles
        lda nfiles
        cmp #MAXFILES
        bne found_name
    
        lda #<too_many_files
        ldx #>too_many_files
        jmp print_string        \ exits
    
    found_name:
    
    \ update records and last record
    
        ldy #15         \ RC
        lda (pentry),y
        clc
        ldy #12
        adc (pfile),y
        sta (pfile),y
        iny
        lda (pfile),y   \ there's no inc (pfile),y
        adc #0
        sta (pfile),y
    
    \   ldy #13         \ S1   Y is already 13
        lda (pentry),y
        iny             \      and happens to need to be 14 here
        sta (pfile),y
    
        ldy #BDOS_FINDNEXT
        lda #<cpm_fcb
        ldx #>cpm_fcb
        jsr BDOS
    
    test_ff:
        cmp #$ff
    .zuntil eq

\ sorting with simple bubble sort which fast enough

    jsr sort

\ print to screen

    lda #<idx-2      \ minus trick again, adds 2 before first use
    sta pidx
    lda #>idx-2
    sta pidx+1

    jmp check_nfiles    \ start at end of loop in case it's an empty disk

print_next:
    lda pidx
    clc
    adc #2
    sta pidx
    .zif cs
        inc pidx+1
    .zendif

    ldy #0
    lda (pidx),y
    sta pfile
    iny
    lda (pidx),y
    sta pfile+1

\ print flags

    ldx #'-'
    lda #'w'
    sta flags+3

    ldy #8
    lda (pfile),y
    bpl no_rofile

    stx flags+3

no_rofile:
    stx flags+1

    iny
    lda (pfile),y
    bpl no_sysfile

    lda #'s'
    sta flags+1

no_sysfile:
    stx flags

    iny
    lda (pfile),y
    bpl no_archived

    lda #'a'
    sta flags

no_archived:
    stx flags+4

    lda (pfile),y
    and #$7f
    cmp #'M'
    bne no_executable
    dey
    lda (pfile),y
    and #$7f
    cmp #'O'
    bne no_executable
    dey
    lda (pfile),y
    and #$7f
    cmp #'C'
    bne no_executable

    lda #'x'
    sta flags+4

no_executable:
    lda #<flags
    ldx #>flags
    jsr print_string

\ print file size

    ldy #11
    lda (pfile),y
    sta tmp
    iny
    lda (pfile),y
    sta tmp+1
    iny
    lda #0
    sta tmp+2

    ldx #7
mul128:             \ 24-bit mul, files can be larger than 65535
    clc
    rol tmp
    rol tmp+1
    rol tmp+2
    dex
    bne mul128

    lda (pfile),y
    tax             \ save in x
    beq no_adjust

    lda tmp
    sec
    sbc #128
    sta tmp 
    lda tmp+1
    sbc #0
    sta tmp+1
    lda tmp+2
    sbc #0
    sta tmp+2

    txa             \ get back from x
    clc
    adc tmp
    sta tmp
    .zif cs
        inc tmp+1
        .zif eq
            inc tmp+2
        .zendif
    .zendif

no_adjust:
    lda tmp+2               \ we cannot print a value larger than 65535
    beq no_adjust2

test:
    lda #$ff
    sta tmp
    lda #$ff
    sta tmp+1

no_adjust2:
    lda tmp
    ldx tmp+1
    jsr print16padded

    ldy #BDOS_CONOUT
    lda #' "
    jsr BDOS

\ we cannot use BDOS_PRINTSTRING because filenames can contain '$'

    ldy #0

    .zrepeat
        lda (pfile),y
        and #$7f            \ 7-bit ASCII
        sty tmp

        ldy #BDOS_CONOUT
        jsr BDOS

        ldy tmp
        iny
        cpy #11
    .zuntil eq

    ldy #BDOS_CONOUT
    lda #13
    jsr BDOS
    ldy #BDOS_CONOUT
    lda #10
    jsr BDOS

check_nfiles:
    lda nfiles
    beq done
    dec nfiles
    jmp print_next

done:
    rts

\ ----------------------------------------------

.zproc sort

\ init index

    lda #<files
    sta pfile
    lda #>files
    sta pfile+1

    lda #<idx
    sta pidx
    lda #>idx
    sta pidx+1

    ldy #0
    ldx nfiles
    .zrepeat
        lda pfile
        sta (pidx),y
        iny
        lda pfile+1
        sta (pidx),y
        dey
        lda pidx
        clc
        adc #2
        sta pidx
        .zif cs
            inc pidx+1
        .zendif
        lda pfile
        clc
        adc #14
        sta pfile
        .zif cs
            inc pfile+1
        .zendif
        dex
    .zuntil eq

\ sort index

    ldx nfiles
    beq no_files
    dex                 \ repeat nfiles - 1
    beq just_one_file
    stx endcondx

    ldx #0
    .zrepeat
        stx count

        lda endcondx
        sec
        sbc #1
        sbc count
        sta count

        lda #<idx
        sta pidx
        lda #>idx
        sta pidx+1
        lda #<idx+2
        sta pidx2
        lda #>idx+2
        sta pidx2+1

        \ compare

    jloop:

        ldy #0
        lda (pidx),y
        sta pfile
        lda (pidx2),y
        sta pfile2
        iny
        lda (pidx),y
        sta pfile+1
        lda (pidx2),y
        sta pfile2+1
        dey

        php             \ instead of unrolling 11 compares
        .label further_checks
        .zrepeat
            plp
            lda (pfile),y
            cmp (pfile2),y
            bne further_checks
            php
            iny
            cpy #11
        .zuntil eq

        plp

    further_checks:
        bcc lower
        beq same
    higher:

        \ SWAP

        ldy #0
        lda (pidx),y
        sta tmp
        lda (pidx2),y
        sta (pidx),y
        lda tmp
        sta (pidx2),y

        iny
        lda (pidx),y
        sta tmp
        lda (pidx2),y
        sta (pidx),y
        lda tmp
        sta (pidx2),y

    same:
    lower:
        lda pidx
        clc
        adc #2
        sta pidx
        .zif cs
            inc pidx+1
        .zendif
        lda pidx2
        clc
        adc #2
        sta pidx2
        .zif cs
            inc pidx2+1
        .zendif

        lda count
        beq ready
        dec count
        jmp jloop

    ready:
        inx
        cpx endcondx
    .zuntil eq

no_files:
just_one_file:
    rts
.zendproc

\ Print string wrapper

.zproc print_string
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
    .byte "drive error\r\n$"
too_many_files:
    .byte "too many files\r\n$"
flags:
    .byte "--r-- $"       \ s=system, a=archived, r=read, w=write, x=execute

