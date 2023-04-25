
\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.bss pblock, 165
cpm_fcb = pblock
cpm_default_dma = pblock + 0x25

BDOS_WARMBOOT          =  0
BDOS_CONIN             =  1
BDOS_CONOUT            =  2
BDOS_AUXIN             =  3
BDOS_AUXOUT            =  4
BDOS_LSTOUT            =  5
BDOS_CONIO             =  6
BDOS_GET_IOBYTE        =  7
BDOS_SET_IOBYTE        =  8
BDOS_PRINTSTRING       =  9
BDOS_READLINE          = 10
BDOS_CONST             = 11
BDOS_GET_VERSION       = 12
BDOS_RESET_DISK_SYSTEM = 13
BDOS_SELECT_DRIVE      = 14
BDOS_OPEN_FILE         = 15
BDOS_CLOSE_FILE        = 16
BDOS_FINDFIRST         = 17
BDOS_FINDNEXT          = 18
BDOS_DELETE_FILE       = 19
BDOS_READ_SEQUENTIAL   = 20
BDOS_WRITE_SEQUENTIAL  = 21
BDOS_MAKE_FILE         = 22
BDOS_RENAME_FILE       = 23
BDOS_GET_LOGIN_VECTOR  = 24
BDOS_GET_CURRENT_DRIVE = 25
BDOS_SET_DMA           = 26
BDOS_GET_ALLOC_VECTOR  = 27
BDOS_WRITE_PROT_DRIVE  = 28
BDOS_GET_READONLY_VEC  = 29
BDOS_SET_FILE_ATTRS    = 30
BDOS_GET_DPB           = 31
BDOS_GET_SET_USER      = 32
BDOS_READ_RANDOM       = 33
BDOS_WRITE_RANDOM      = 34
BDOS_SEEK_TO_END       = 35
BDOS_SEEK_TO_SEQ_POS   = 36
BDOS_RESET_DRIVES      = 37
BDOS_GET_BIOS          = 38
BDOS_WRITE_RANDOM_FILL = 40

BIOS_CONST             = 0
BIOS_CONIN             = 1
BIOS_CONOUT            = 2
BIOS_SELDSK            = 3
BIOS_SETSEC            = 4
BIOS_SETDMA            = 5
BIOS_READ              = 6
BIOS_WRITE             = 7
BIOS_RELOCATE          = 8
BIOS_GETTPA            = 9
BIOS_SETTPA            = 10
BIOS_GETZP             = 11
BIOS_SETZP             = 12
BIOS_SETBANK           = 13

FCB_DR = 0x00
FCB_F1 = 0x01
FCB_F2 = 0x02
FCB_F3 = 0x03
FCB_F4 = 0x04
FCB_F5 = 0x05
FCB_F6 = 0x06
FCB_F7 = 0x07
FCB_F8 = 0x08
FCB_T1 = 0x09
FCB_T2 = 0x0a
FCB_T3 = 0x0b
FCB_EX = 0x0c
FCB_S1 = 0x0d
FCB_S2 = 0x0e
FCB_RC = 0x0f
FCB_AL = 0x10
FCB_CR = 0x20
FCB_R0 = 0x21
FCB_R1 = 0x22
FCB_R2 = 0x23
FCB_SIZE = 0x24

BDOS = start - 3
start:
.expand 1

.zp ptr1, 2
.zp ptr2, 2
.zp current_line, 2
.zp line_length, 1
.zp line_number, 2
.zp io_ptr, 1
.zp himem, 1
.zp command_ptr, 1
.zp command_len, 1

.label BIOS
.label crlf
.label error
.label exit_program
.label jsr_indirect
.label list_file
.label load_file
.label mainloop
.label new_file
.label print_free
.label printi
.label putchar
.label renumber_file

command_buffer = cpm_default_dma + 2

.bss line_buffer, 128
.bss text_start, 0

.zproc main
    jsr printi
    .byte "Basic Editor (c) 2023 David Given", 13, 10, 0

    lda #<cpm_default_dma
    ldx #>cpm_default_dma
    ldy #BDOS_SET_DMA
    jsr BDOS

    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    ldy #BIOS_GETTPA
    jsr BIOS
    stx himem

    lda cpm_fcb+1
    cmp #' '
    .zif eq
        \ No parameter given.

        jsr new_file
        jsr print_free
        jmp mainloop
    .zendif
    jsr load_file
    jmp mainloop
.zendproc

.zproc jsr_indirect
    jmp (ptr1)
.zendproc

\ Multiplies ptr1 by 10.

.zproc mul10
    asl ptr1+0
    rol ptr1+1      \ x2

    lda ptr1+1
    pha
    lda ptr1+0
    pha             \ store for later

    asl ptr1+0
    rol ptr1+1      \ x4

    asl ptr1+0
    rol ptr1+1      \ x8

    clc             \ add on the stored x2 value
    pla
    adc ptr1+0
    sta ptr1+0
    pla
    adc ptr1+1
    sta ptr1+1
    rts         
.zendproc

.zproc skip_command_spaces
    ldx command_ptr
    .zloop
        lda command_buffer, x
        .zbreak eq
        cmp #' '
        .zbreak ne
        inx
    .zendloop
    stx command_ptr
    rts
.zendproc

\ Returns Z if there are no more words in the command line.

.zproc has_command_word
    jsr skip_command_spaces
    ldx command_ptr
    lda command_buffer, x
    rts
.zendproc

\ Parses a command word and copies it to the line buffer.

.zproc read_command_word
    jsr skip_command_spaces
    
    ldy #0
    ldx command_ptr
    .zloop
        lda command_buffer, x
        .zbreak eq
        cmp #' '
        .zbreak eq

        \ Convert to upper case.

        cmp #'a'
        .zif cs
            cmp #'z'+1
            .zif cc
                and #0xdf
            .zendif
        .zendif

        sta line_buffer, y
        inx
        iny
    .zendloop
    stx command_ptr
    sty line_length
    rts
.zendproc

\ Parses a number from the command buffer. Returns it in XA and ptr1.

.zproc read_command_number
    jsr skip_command_spaces

    lda #0
    sta ptr1+0
    sta ptr1+1

    ldx command_ptr
    lda command_buffer, x
    beq syntax_error

    .zloop
        lda command_buffer, x
        .zbreak eq
        cmp #' '
        .zbreak eq

        cmp #'0'
        bcc syntax_error
        cmp #'9'+1
        bcs syntax_error

        pha
        txa
        pha
        jsr mul10
        pla
        tax
        pla

        sec
        sbc #'0'
        clc
        adc ptr1+0
        sta ptr1+0
        .zif cs
            inc ptr1+1
        .zendif

        inx
    .zendloop

    sta command_buffer, x
    lda ptr1+0
    ldx ptr1+1
    rts

syntax_error:
    jsr error
    .byte "Syntax error; expected number", 0
.zendproc

.zproc mainloop
    ldx #0xff
    txs

    .label command_tab

    .zloop
        lda #'>'
        jsr putchar

        \ Read command line.

        lda #0x7f
        sta cpm_default_dma
        lda #<cpm_default_dma+0
        ldx #>cpm_default_dma+1
        ldy #BDOS_READLINE
        jsr BDOS

        \ Zero-terminate it and prepare for command parsing.

        ldx cpm_default_dma+1
        lda #0
        sta command_ptr
        sta command_buffer, x
        sta command_len

        \ Parse the command.

        jsr read_command_word
        label:
        lda line_length
        .zif ne
            ldx #0          \ offset into command table
            ldy #0          \ offset into line buffer
            .zrepeat
                lda line_buffer, y
                cmp #'.'    \ abbreviation?
                .zbreak eq  \ if yes, then we've found the command

                lda command_tab, x
                .zif eq
                    \ No more commands.
                    jsr error
                    .byte "Bad command", 0
                .zendif
                and #0x7f
                cmp line_buffer, y
                .zif eq
                    lda command_tab, x
                    .zbreak mi \ last matching character of word

                    \ If we got here, the character matched, but it's not
                    \ the last one, so go again.

                    inx
                    iny
                    .zcontinue
                .zendif
                
                \ If we get here, the character didn't match, so skip to
                \ the end of the command and go again.

                .zrepeat
                    inx
                    lda command_tab-1, x
                .zuntil mi
                inx
                inx
            .zendloop

            \ Found. Skip to the end of the word.

            .zrepeat
                inx
                lda command_tab-1, x
            .zuntil mi

            lda command_tab+0, x
            sta ptr1+0
            lda command_tab+1, x
            sta ptr1+1
            jsr jsr_indirect
        .zendif

    .zendloop

command_tab:
    .byte "LIS", 'T'+0x80
    .word list_file
    .byte "EXI", 'T'+0x80
    .word exit_program
    .byte "NE", 'W'+0x80
    .word new_file
    .byte "FRE", 'E'+0x80
    .word print_free
    .byte "RENUMBE", 'R'+0x80
    .word renumber_file
    .byte 0
.zendproc

.zproc putchar
    ldy #BDOS_CONOUT
    jmp BDOS
.zendproc

.zproc crlf
    lda #0x0d
    jsr putchar

    lda #0x0a
    jmp putchar
.zendproc

\ Processes a simple error. The text string must immediately follow the
\ subroutine call.

.zproc error
    pla
    tay
    pla
    tax
    tya

    ldy #BDOS_PRINTSTRING
    jsr BDOS
    jsr crlf

    jmp mainloop
.zendproc

\ Prints an inline string. The text string must immediately follow the
\ subroutine call.

.zproc printi
    pla
    sta ptr1+0
    pla
    sta ptr1+1

    .zloop
        ldy #1
        lda (ptr1), y
        .zbreak eq
        jsr putchar

        inc ptr1+0
        .zif eq
            inc ptr1+1
        .zendif
    .zendloop

    inc ptr1+0
    .zif eq
        inc ptr1+1
    .zendif
    inc ptr1+0
    .zif eq
        inc ptr1+1
    .zendif

    jmp (ptr1)
.zendproc

\ Prints XA in decimal. Y is the padding char or 0 for no padding.

.zproc print16
    ldy #0
.zendproc
\ falls through
.zproc print16padded
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

\ Advances current_line to point at the next line. Sets Z
\ if there isn't one.

.zproc goto_next_line
    ldy #0
    lda (current_line), y
    .zif ne
        clc
        adc current_line+0
        sta current_line+0
        .zif cs
            inc current_line+1
        .zendif
        \ !Z must be set at this point.
    .zendif
    rts
.zendproc

\ Sets ptr1 to point at the terminating 0 at the end of the document.

.zproc find_end_of_document
    lda current_line+0
    sta ptr1+0
    lda current_line+1
    sta ptr1+1

    ldy #0
    .zloop
        lda (ptr1), y
        .zif eq
            rts
        .zendif

        clc
        adc ptr1+0
        sta ptr1+0
        .zif cs
            inc ptr1+1
        .zendif
    .zendloop
.zendproc

\ Exits.

.zproc exit_program
    ldy #BDOS_WARMBOOT
    jmp BDOS
.zendproc

\ Computes and prints the amount of free space.

.zproc print_free
    jsr find_end_of_document \ sets ptr1

    \ Subtract this from himem.

    sec
    lda #0
    sbc ptr1+0
    sta ptr1+0
    lda himem
    sbc ptr1+1
    tax

    jsr print16
    jsr printi
    .byte " bytes free", 13, 10, 0

    rts
.zendproc

\ Sets up a new, empty document.

.zproc new_file
    lda #<text_start
    sta current_line+0
    lda #>text_start
    sta current_line+1

    lda #0
    sta text_start
    rts
.zendproc

\ Prints the current line.

.zproc print_current_line
    ldy #1
    lda (current_line), y
    pha
    iny
    lda (current_line), y
    tax
    pla

    ldy #' '
    jsr print16padded
    lda #' '
    jsr putchar

    ldy #0
    lda (current_line), y
    tax

    cmp #3
    .zif ne
        ldy #3
        .zrepeat
            pha
            txa
            pha
            tya
            pha

            lda (current_line), y
            jsr putchar

            pla
            tay
            pla
            tax
            pla

            iny
            dex
            cpx #3
        .zuntil eq
    .zendif
    jmp crlf
.zendproc

\ Lists part of the file.

.zproc list_file
    jsr has_command_word
    .zif ne
        jsr error
        .byte "Syntax error", 0
    .zendif

    lda current_line+0
    pha
    lda current_line+1
    pha

    lda #<text_start
    sta current_line+0
    lda #>text_start
    sta current_line+1

    .zloop
        ldy #0
        lda (current_line), y
        .zbreak eq

        jsr print_current_line
        jsr goto_next_line
    .zendloop

    pla
    sta current_line+1
    pla
    sta current_line+0
    rts
.zendproc



\ Inserts the contents of line_buffer into the current document before the
\ current line. The line number is unset.

.zproc insert_line
    jsr find_end_of_document \ sets ptr1

    \ Calculate the new end-of-document based on the changed line length.

    lda line_length
    clc
    adc #3              \ cannot overflow
    adc ptr1+0
    sta ptr2+0
    lda ptr1+1
    adc #0
    sta ptr2+1

    \ Open up space.

    ldy #0
    .zloop
        lda (ptr1), y
        sta (ptr2), y

        lda ptr1+0
        cmp current_line+0
        .zif eq
            lda ptr1+1
            cmp current_line+1
            .zbreak eq
        .zendif

        lda ptr1+0
        .zif eq
            dec ptr2+1
        .zendif
        dec ptr1+0

        lda ptr2+0
        .zif eq
            dec ptr2+1
        .zendif
        dec ptr2+0
    .zendloop

    \ We now have space for the new line, plus the header. Populate said header.

    lda line_length
    clc
    adc #3
    sta (current_line), y

    \ Copy the data in from the line buffer.

    ldx #0
    ldy #3
    .zloop
        cpx line_length
        .zbreak eq

        lda line_buffer, x
        sta (current_line), y
        iny
        inx
    .zendloop

    \ Advance the current line.

label:
    ldy #0
    lda (current_line), y
    clc
    adc current_line+0
    sta current_line+0
    .zif cs
        inc current_line+1
    .zendif

    \ Done. Reset the line buffer.
    \ (y is zero)

    sty line_length

    rts
.zendproc

\ Renumbers the document.

.zproc renumber_file
    lda #<text_start
    sta ptr1+0
    lda #>text_start
    sta ptr1+1

    lda #10
    sta line_number+0
    lda #0
    sta line_number+1

    .zloop
        ldy #0
        lda (ptr1), y       \ length of this line
        .zbreak eq          \ zero? end of file
        tax

        \ Update the line number in the text field.

        iny
        lda line_number+0
        sta (ptr1), y
        iny
        lda line_number+1
        sta (ptr1), y

        \ Increment the line number.

        clc
        lda line_number+0
        adc #10
        sta line_number+0
        .zif cs
            inc line_number+1
        .zendif

        \ Advance to the next line.

        clc
        txa
        adc ptr1+0
        sta ptr1+0
        .zif cs
            inc ptr1+1
        .zendif
    .zendloop

    rts
.zendproc

\ Reads the file pointed at by the FCB into memory.

.zproc load_file
    lda #0
    sta cpm_fcb+0x20

    lda #<cpm_fcb
    ldx #>cpm_fcb
    ldy #BDOS_OPEN_FILE
    jsr BDOS
    .zif cs
        jsr error
        .byte "Failed to load file", 0
    .zendif

    jsr new_file

    lda #10             \ start line number
    sta line_number+0
    lda #0
    sta line_number+1

    sta line_length
    sta io_ptr

    .zloop
        ldx io_ptr
        .zif eq
            lda #<cpm_fcb
            ldx #>cpm_fcb
            ldy #BDOS_READ_SEQUENTIAL
            jsr BDOS
            .zbreak cs
            ldx io_ptr
        .zendif

        lda cpm_default_dma, x

        cmp #0x1a
        .zbreak eq

        cmp #0x0d
        beq skip

        cmp #0x0a
        .zif eq
            \ insert line
            jsr insert_line
            jmp skip
        .zendif

        \ Insert character into line buffer.

        ldy line_length
        cpy #252
        .zif eq
            \ This line is already at the maximum length.
            jsr insert_line
            ldy #0
        .zendif

        sta line_buffer, y
        iny
        sty line_length

    skip:
        ldx io_ptr
        inx
        cpx #128
        .zif eq
            ldx #0
        .zendif
        stx io_ptr
    .zendloop

    jsr renumber_file
    jsr print_free
    rts
.zendproc
    
BIOS:
    jmp 0

\ vim: sw=4 ts=4 et


