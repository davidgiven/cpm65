
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

.label BIOS
.label crlf
.label error
.label exit_program
.label jsr_indirect
.label list_file
.label load_file
.label load_file_from_fcb
.label mainloop
.label new_file
.label print_free
.label printi
.label putchar
.label renumber_file
.label save_file

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
    jsr load_file_from_fcb
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

\ Parses a command separator; returns Z if there are no more words.

.zproc read_command_separator
    jsr has_command_word
    .zif ne
        ldx command_ptr
        lda command_buffer, x
        cmp #','
        .zif ne
            jsr error
            .byte "Syntax error; bad separator", 0
        .zendif
        inx
        stx command_ptr ; \ leaves !Z
    .zendif
    rts
.zendproc

\ Converts an ASCII character to uppercase.

.zproc toupper
    cmp #'a'
    .zif cs
        cmp #'z'+1
        .zif cc
            and #0xdf
        .zendif
    .zendif
    rts
.zendproc

\ Parses a command word and copies it to the line buffer.

.zproc read_command_word
    jsr skip_command_spaces
    
    ldy #0
    ldx command_ptr
    .zloop
        lda command_buffer, x
        jsr toupper

        \ Stop on non-command characters.

        cmp #'.'
        .zif ne
            cmp #'A'
            .zbreak cc
            cmp #'Z'+1
            .zbreak cs
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

        cmp #'0'
        .zbreak cc
        cmp #'9'+1
        .zbreak cs

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

    \ If we read no bytes, it's a syntax error.

    cpx command_ptr
    beq syntax_error

    stx command_ptr
    lda ptr1+0
    ldx ptr1+1
    rts

syntax_error:
    jsr error
    .byte "Syntax error; expected number", 0
.zendproc

\ Parses a string from the command buffer. This can be double-quote or
\ space/comma delimited. The result is placed in the line buffer.

.zproc read_command_string
    jsr skip_command_spaces

    ldx command_ptr
    lda command_buffer, x
    beq syntax_error

    cmp #'"'
    beq parse_quoted_string

    \ Parsing a space/comma delimited string.

    ldy #0
    .zloop
        lda command_buffer, x
        .zbreak eq
        cmp #' '
        .zbreak eq
        cmp #','
        .zbreak eq

        sta line_buffer, y
        inx
        iny
    .zendloop
    stx command_ptr
    sty line_length
    rts

parse_quoted_string:
    .label escaped_character_table

    \ Parsing a double quoted string.

    inx             \ skip double quote
    ldy #0
    .zloop
        lda command_buffer, x
        .zbreak eq
        cmp #'"'
        .zbreak eq
        cmp #'\\'
        .zif eq
            \ Backslash-escaped character.

            sty line_length

            inx
            lda command_buffer, x
            .zbreak eq

            ldy #0
            .zloop
                lda escaped_character_table, y
                .zbreak mi
                cmp command_buffer, x
                .zbreak eq
                iny
                iny
            .zendloop
            .zif pl
                iny
                lda escaped_character_table, y
            .zendif

            ldy line_length
        .zendif

        sta line_buffer, y
        inx
        iny
    .zendloop
    lda command_buffer, x
    .zif ne
        \ If we terminated due to a closing ", skip it.

        inx
    .zendif
    stx command_ptr
    sty line_length
    rts

escaped_character_table:
    .byte 'n', 0x0a
    .byte 'r', 0x0d
    .byte 't', 0x09
    .byte '\\', '\\'
    .byte 'f', 0x0c
    .byte 0x80

syntax_error:
    jsr error
    .byte "Syntax error; expected string", 0
.zendproc

.zproc mainloop
    ldx #0xff
    txs

    .label command_tab

    .zloop
        lda #'>'
        jsr putchar

        \ Read command line.

        lda #0x7d
        sta cpm_default_dma
        lda #<cpm_default_dma+0
        ldx #>cpm_default_dma+1
        ldy #BDOS_READLINE
        jsr BDOS
        jsr crlf

        \ Zero-terminate it and prepare for command parsing.

        ldx cpm_default_dma+1
        lda #0
        sta command_buffer, x
        sta command_ptr

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
                ldy #0          \ reset line buffer offset
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
    .byte "NE", 'W'+0x80
    .word new_file
    .byte "FRE", 'E'+0x80
    .word print_free
    .byte "RENUMBE", 'R'+0x80
    .word renumber_file
    .byte "LOA", 'D'+0x80
    .word load_file
    .byte "SAV", 'E'+0x80
    .word save_file
    .byte "QUI", 'T'+0x80
    .word exit_program
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
    iny
    .zif eq
        inx
    .zendif
    tya

    ldy #BDOS_PRINTSTRING
    jsr BDOS
    jsr crlf

    jmp mainloop
.zendproc

\ Does a simple syntax error.

.zproc syntax_error
    jsr error
    .byte "Syntax error", 0
.zendproc

\ Parses a filename from the line buffer into cpm_fcb.
\ Returns with C set if the filename is invalid.

.zproc parse_fcb
    .label exit

    \ Basic sanity test.

    lda line_length
    .zif eq
        sec
        rts
    .zendif

    \ Wipe FCB.

    lda #0
    sta cpm_fcb+0               \ drive
    lda #' '
    ldy #FCB_F1
    .zrepeat                    \ 11 bytes of filename
        sta cpm_fcb, y
        iny
        cpy #FCB_T3+1
    .zuntil eq
    lda #0
    .zrepeat                    \ 4 bytes of metadata
        sta cpm_fcb, y
        iny
        cpy #FCB_RC+1
    .zuntil eq

    \ Check for drive.

    ldx #0                      \ offset into filename
    lda line_length
    cmp #1
    .zif ne
        ldy line_buffer+1
        cpy #':'                    \ colon?
        .zif eq
            lda line_buffer+0
            jsr toupper                 \ must be upper case
            sec
            sbc #'A'-1              \ to 1-based drive
            cmp #16
            .zif cs                 \ out of range drive
                rts
            .zendif
            sta cpm_fcb+0           \ store

            ldx #2                  \ skip drive letter
        .zendif
    .zendif

    \ Read the filename.

    \ x = offset
    ldy #FCB_F1
    .zloop
        cpx line_length
        beq exit                \ end of filename
        cpy #FCB_F8+1
        .zbreak eq              \ maximum number of characters
        lda line_buffer, x
        cmp #'.'
        .zbreak eq

        jsr toupper             \ must be upper case
        sta cpm_fcb, y
        iny
        inx
    .zendloop
    \ A is the character just read
    \ X is cmdoffset

    \ Skip non-dot filename characters.

    .zloop
        cpx line_length
        beq exit                \ end of filename
        lda line_buffer, x
        cmp #'.'
        .zbreak eq

        inx
        lda line_buffer, x
    .zendloop
    \ A is the character just read
    \ X is cmdoffset

    \ Read the extension

    inx                         \ skip dot
    ldy #FCB_T1
    .zloop
        cpx line_length
        .zbreak eq              \ end of filename
        cpy #FCB_T3+1
        .zbreak eq
        lda line_buffer, x      \ get a character
        cmp #'.'
        .zbreak eq

        jsr toupper             \ must be upper case
        sta cpm_fcb, y
        iny
        inx
    .zendloop
        
    \ Any remaining filename characters are simply ignored.

exit:
    clc
    rts
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

\ Compares the current line number to line_number.
\ Returns:
\   !C if current_line >= line_number
\    C if current_line < line_number
\    Z if current_line == line_number line
\   !Z if current_line != line_number

.zproc test_line_number
    ldy #1
    lda (current_line), y
    cmp line_number+0
    .zif eq
        iny
        lda (current_line), y
        cmp line_number+1
        .zif eq
            clc \ return !C
            rts 
        .zendif
    .zendif

    \ Not equal, so do magnitude comparison.

    ldy #1
    lda line_number+0
    cmp (current_line), y
    iny
    lda line_number+1
    sbc (current_line), y
    tya \ force !Z
    rts
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

\ Sets current_ptr to the first line with an equal or great number than
\ line_number.

.zproc find_line
    lda #<text_start
    sta current_line+0
    lda #>text_start
    sta current_line+1

    .zloop
        ldy #0
        lda (current_line), y
        .zbreak eq

        jsr test_line_number
        .zbreak cc
        jsr goto_next_line
    .zendloop
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
    lda current_line+0
    pha
    lda current_line+1
    pha

    \ Default start: beginning of the file.

    lda #<text_start
    sta current_line+0
    lda #>text_start
    sta current_line+1

    \ Default end: end of the file.

    lda #0xff
    sta line_number+0
    sta line_number+1

    \ Parameter parsing.

    jsr has_command_word
    .zif ne
        jsr read_command_number
        sta line_number+0
        stx line_number+1

        jsr find_line

        \ If there's a parameter, default to just one line.

        ldy #1
        lda (current_line), y
        sta line_number+0
        iny
        lda (current_line), y
        sta line_number+1

        \ current_line, which is the start line, is set. 

        jsr read_command_separator
        .zif ne
            \ Default to listing to the end of the file again.

            lda #0xff
            sta line_number+0
            sta line_number+1

            jsr has_command_word
            .zif ne
                jsr read_command_number
                sta line_number+0
                stx line_number+1

                jsr has_command_word
                bne syntax_error
            .zendif
        .zendif
    .zendif

    .zloop
        ldy #0
        lda (current_line), y
        .zbreak eq

        jsr test_line_number
        .zif ne
            .zbreak cc
        .zendif

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

\ Reads a file.

.zproc load_file
    jsr read_command_string

    jsr has_command_word
    bne syntax_error

    jsr parse_fcb
.zendproc
    \ falls through

\ Reads the file pointed at by the FCB into memory.

.zproc load_file_from_fcb
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
    
\ Writes a byte to the already opened cpm_fcb. Returns C
\ on an I/O error.

.zproc write_byte_to_file
    ldx io_ptr
    sta cpm_default_dma, x

    inc io_ptr
    clc
    .zif eq
        lda #<cpm_fcb
        ldx #>cpm_fcb
        ldy #BDOS_WRITE_SEQUENTIAL
        jsr BDOS
    .zendif 
    rts
.zendproc 

\ Writes a file.

.zproc save_file
    jsr read_command_string

    jsr has_command_word
    bne syntax_error

    jsr parse_fcb
.zendproc
    \ falls through

\ Saves memory into the file pointed at by the FCB.

.zproc save_file_to_fcb
    lda #0
    sta cpm_fcb+0x20

    lda #<cpm_fcb
    ldx #>cpm_fcb
    ldy #BDOS_DELETE_FILE
    jsr BDOS

    lda #<cpm_fcb
    ldx #>cpm_fcb
    ldy #BDOS_MAKE_FILE
    jsr BDOS
    .zif cs
        jsr error
        .byte "Failed to create file", 0
    .zendif

    lda #0
    sta io_ptr
    lda #3
    sta line_length

    lda #<text_start
    sta current_line+0
    lda #>text_start
    sta current_line+1

    .label write_char
    .label io_error

    .zloop
        ldy #0
        lda (current_line), y
        .zbreak eq

        cmp line_length
        .zif eq
            jsr goto_next_line
            lda #3
            sta line_length

            lda #'\r'
            jsr write_byte_to_file
            lda #'\n'
            jmp write_char
        .zendif

        ldy line_length
        lda (current_line), y
        inc line_length

    write_char:
        jsr write_byte_to_file
        bcs io_error
    .zendloop

    lda #0x1a
    jsr write_byte_to_file

    lda io_ptr
    .zif ne
        lda #<cpm_fcb
        ldx #>cpm_fcb
        ldy #BDOS_WRITE_SEQUENTIAL
        jsr BDOS
        bcs io_error
    .zendif

    lda #<cpm_fcb
    ldx #>cpm_fcb
    ldy #BDOS_CLOSE_FILE
    jsr BDOS
    .zif cs
io_error:
        jsr error
        .byte "I/O error on write; save failed", 0
    .zendif

    rts
.zendproc
    
BIOS:
    jmp 0

\ vim: sw=4 ts=4 et


