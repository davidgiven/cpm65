\ recv - recv files

\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

\   C version: 2051 bytes
\ asm version: 1024 bytes (w/ flags)

.include "cpm65.inc"
.include "drivers.inc"

MAXFILES = 255

OFFSET_NAME = 0
OFFSET_RECS = 11
OFFSET_LAST = 13
FULL_SIZE   = 14

.bss files, 3570    \ MAXFILES * 14
.bss idx, 510       \ MAXFILES * 2

.bss buffer, 128
.bss offset, 1
.bss blkcnt, 1

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
.zp drvaux, 4 


SOH = 1         \     H001          Start Of Header
EOT = 4         \     H004          End Of Transmission
ACK = 6         \     H006          Acknowledge (positive)
DLE = 16        \     H010          Data Link Escape
XON =  17       \     H011          Transmit On
XOFF = 19       \     H013          Transmit Off
NAK =   21      \     H015          Negative Acknowledge
SYN =   22      \     H016          Synchronous idle
CAN =   24      \     H018          Cancel5



start:
.expand 1



    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    lda #<DRVID_AUX
	ldx #>DRVID_AUX
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta drvaux+0
    stx drvaux+1
    lda #$09
    ldx #$ff
    sta drvaux+2
    stx drvaux+3

    

    bcc found_aux 
    .label aux_not_found
    lda #<aux_not_found
    ldx #>aux_not_found
    jmp print_string    \ exits

found_aux:
    .label aux_found
    lda #<aux_found
    ldx #>aux_found
    jsr print_string    

    lda drvaux+1
    jsr print_hex_number
    lda drvaux+0
    jsr print_hex_number

    lda #'\r'
    jsr putchar    
    lda #'\n'
    jsr putchar  

    lda cpm_fcb+1
    cmp #' '
    .label filename_not_given
    .zif eq
        \ No parameter given.
        lda #<filename_not_given
        ldx #>filename_not_given
       \ jmp print_string    \ exits

    .zendif
    jsr create_file_from_fcb
    .label cant_open_file
    .zif cs
        lda #<cant_open_file
        ldx #>cant_open_file
        jmp print_string    \ exits
    .zendif

    .label start_transmission
    lda #<start_transmission
    ldx #>start_transmission
    jsr print_string    
mainloop: 
  

    jsr receive_file
    bcs mainloop
    lda #<cpm_fcb
    ldx #>cpm_fcb
    ldy #BDOS_CLOSE_FILE
    jsr BDOS

    .label done_transmission
    lda #<done_transmission
    ldx #>done_transmission
    jmp print_string     \ exit



blkwaiter: .byte 0
debug: .byte 0,0,0
checksum: .byte 0

receive_file:
    lda #200   
    sta blkwaiter
    lda #0
    sta blkcnt
    sta debug
    sta debug+2
    lda #$ff
    sta debug+1

getblock:      
    lda #NAK        \ start transmission
    \ lda #'D'
getblock2:    
    jsr putaux
    lda #0
    sta offset
    jsr getblockchar
    bcs sdasd
    sta debug+1
    inc debug+2
    cmp #SOH
    beq got_header 
    cmp #EOT
    beq end_of_tranmission
    cmp #CAN
    beq abort_transmission
sdasd:
    dec blkwaiter
    lda blkwaiter
    beq abort_transmission
    jmp getblock    

end_of_tranmission:
    lda #ACK
    jsr putaux
    .label transmission_done
    lda #<transmission_done
    ldx #>transmission_done
    jsr print_string  
    clc
    rts

abort_transmission:
    .label transmission_stopped
    lda #<transmission_stopped
    ldx #>transmission_stopped
    jsr print_string   
    lda blkcnt
    jsr print_hex_number
    lda #' '
    jsr putchar
    lda offset
    jsr print_hex_number
    lda #' '
    jsr putchar
    lda debug
    jsr print_hex_number
    lda #' '
    jsr putchar
    lda debug+1
    jsr print_hex_number
    lda #' '
    jsr putchar
    lda debug+2
    jsr print_hex_number
    lda #' '
    jsr putchar

stop:    
    jsr getblockchar
    jsr print_hex_number
    jmp abort_transmission  


got_header:
    inc blkcnt  
    lda #$00
    sta checksum
    lda #2
    sta debug
    jsr getblockchar
    sta debug+1
    sta blkcnt

got_blkcnt:
    lda #3
    sta debug
    jsr getblockchar    
    eor #$ff
    cmp blkcnt
    beq got_invblkcnt    
    jmp getblock     \ retry transmission

got_invblkcnt:
    lda #4
    sta debug
    jsr getblockchar    
    ldy offset
    sta buffer,y
    clc
    adc checksum
    sta checksum
    iny
    sty offset
    cpy #$80
    bne got_invblkcnt

got_block:
    lda #5
    sta debug
    jsr getblockchar    
    cmp checksum
    bne getblock    \ retransmit block
    jsr write_buffer
    lda #ACK        \ confirm block 
    jmp getblock2


chrwait: .byte 0,0

getblockchar:       
    lda #0
    sta chrwait
    sta chrwait+1
getblockchar2:    
    jsr getaux
    .zif cs
       inc chrwait
       lda chrwait
       bne getblockchar2                   
       inc chrwait+1
       lda chrwait+1
       cmp #$07
       bne getblockchar2                   
       lda #0
       sec 
       rts
    .zendif    
   
 
    \jsr print_hex_number
    \ Abort : 18181818080808
    \ get#98,a$:a=asc(a$+chr$(0)):ifa<>1anda<>4anda<>24then540

    rts

write_buffer:

    ldy #BDOS_SET_DMA
    lda #<buffer
    ldx #>buffer
    jsr BDOS

    ldy #BDOS_WRITE_SEQUENTIAL
    lda #<cpm_fcb
    ldx #>cpm_fcb
    jmp BDOS



create_file_from_fcb:
    
    .label writing_to
    lda #<writing_to
    ldx #>writing_to
    jsr print_string    

    jsr print_fcb

    lda #0
    sta cpm_fcb+0x20

    lda #<cpm_fcb
    ldx #>cpm_fcb
    ldy #BDOS_MAKE_FILE
    jsr BDOS
      
    rts


getaux:
    ldy #AUX_IN
    jmp (drvaux+2)

putaux:
    ldy #AUX_OUT
    jmp (drvaux)

\ Prints the name of the file in cpm_fcb.

print_fcb:
    \ Drive letter.

    lda cpm_fcb+0
    .zif ne
        clc
        adc #'@'
        jsr putchar

        lda #':'
        jsr putchar
    .zendif

    \ Main filename.

    ldy #FCB_F1
    .zrepeat
        tya
        pha

        lda cpm_fcb, y
        and #0x7f
        cmp #' '
        .zif ne
            jsr putchar
        .zendif

        pla
        tay
        iny
        cpy #FCB_T1
    .zuntil eq

    lda cpm_fcb+9
    and #0x7f
    cmp #' '
    .zif ne
        lda #'.'
        jsr putchar

        ldy #FCB_T1
        .zrepeat
            tya
            pha

            lda cpm_fcb, y
            and #0x7f
            cmp #' '
            .zif ne
                jsr putchar
            .zendif

            pla
            tay
            iny
            cpy #FCB_T3+1
        .zuntil eq
    .zendif

    lda #'\r'
    jsr putchar    
    lda #'\n'
    jsr putchar  
    rts













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
    lda #' '
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

\ Prints an 8-bit hex number in A.
.zproc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr h4
    pla
h4:
    and #0x0f 
    ora #'0'
    cmp #'9'+1
	.zif cs
		adc #6
	.zendif
   	pha
    jsr putchar
	pla
	rts
.zendproc

.zproc putchar

	ldy #BDOS_CONOUT
    jmp BDOS

.zendproc

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
        jsr putchar
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

BIOS:
    jmp 0

aux_not_found:
    .byte "error : cannot find auxilary devices\r\n$"

filename_not_given:
    .byte "error : please add filename to save as parameter\r\n$"

transmission_stopped:
    .byte "error : transmission stopped\r\n$"


cant_open_file:
    .byte "cannot open file\r\n$"


aux_found:
    .byte "info : found auxilary device at :$"

writing_to:
    .byte "info : writing to file : $"

start_transmission:
    .byte "info : Start transmission now \r\n$"

done_transmission:
    .byte "info : Everything finished. Bye \r\n$"


transmission_done:
    .byte "info : reception complete\r\n$"

error:
    .byte "drive error\r\n$"
too_many_files:
    .byte "too many files\r\n$"
flags:
    .byte "--r-- $"       \ s=system, a=archived, r=read, w=write, x=execute

