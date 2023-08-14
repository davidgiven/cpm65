; Altirra BASIC - READ/INPUT data module
; Copyright (C) 2023 David Given, All Rights Reserved.
;
; Copying and distribution of this file, with or without modification,
; are permitted in any medium without royalty provided the copyright
; notice and this notice are preserved.  This file is offered as-is,
; without any warranty.

FCB_DIRTY = FCB__SIZE + 0
FCB_BUFFER = FCB__SIZE + 1
FCB_EXTRA__SIZE = FCB_BUFFER + 0x80

_t0 = ztemp1
_t1 = ztemp4
_t2 = ztemp3
_t3 = flptr

_fcb = _t0

; icax1:   direction
; icax3/4: record number
; icax5:   byte offset into record
; icax6/7: ptr to FCB/buffer

; ichid values:
; 0xff      not open
; 0         console
; 1         file

.proc initcio
    ldy #0xff
    sty brkkey
    iny
    sty ichid
    
    lda #0x10
?loop:
    tax
    lda #0xff
    sta ichid, x
    lda #0
    sta icax6, x
    sta icax7, x
    txa
    add #0x10
    bpl ?loop
    
    rts
.endp

.proc ciov
    lda ichid, x
    jeq ciov_console

    lda iccmd, x
    cmp #CIOCmdPutChars
    jeq file_putchars
    cmp #CIOCmdGetChars
    jeq file_getchars
    cmp #CIOCmdGetRecord
    jeq file_getrecord
    cmp #CIOCmdOpen
    jeq file_open
    cmp #CIOCmdClose
    jeq file_close
    jmp errorIO
.endp

; Ensures that an FCB structure is in icax6 and icax7. Copy it to _fcb. Also
; copies X to a2+0.

.proc claim_fcb
    stx a2+0
    lda icax6, x
    sta _fcb+0
    lda icax7, x
    sta _fcb+1
    ora _fcb+0
    bne ?exit

    ; We need to allocate some memory.

    sbw memtop #FCB_EXTRA__SIZE
    lda memtop+0
    sta _fcb+0
    sta icax6, x
    lda memtop+1
    sta _fcb+1
    sta icax7, x

?exit:
    rts
.endp

; On entry:
;   icba points at the filename, terminated with 0x9b

.proc file_open
_filename = _t1
    jsr claim_fcb

    ; Zero-terminate the string.

    mwa icbal,x _filename
    ldy #0xff
?terminate_loop:
    iny
    lda (_filename), y
    cmp #0x9b
    bne ?terminate_loop
    lda #0
    sta (_filename), y

    ; Populate and initialise the FCB.

    lda _fcb+0
    ldx _fcb+1
    ldy #BDOS_SET_DMA_ADDRESS
    jsr BDOS

    lda _filename+0
    ldx _filename+1
    ldy #BDOS_PARSEFILENAME
    jsr bdose

    ; Restore the 9b terminator.

    ldy #0xff
?unterminate_loop:
    iny
    lda (_filename), y
    bne ?unterminate_loop
    lda #0x9b
    sta (_filename), y

    ; Clear the flags.

    lda #0
    ldy #FCB_DIRTY
?fcb_clear_loop
    sta (_fcb), y
    iny
    cpy #FCB_EXTRA__SIZE
    bne ?fcb_clear_loop

    ; Initialise special fields in the IOCB.

    lda #1
    sta ichid, x
    lda #0
    sta icax3, x
    sta icax4, x
    sta icax5, x

    ; The buffer is unpopulated.

    lda #0xff
    ldy #FCB_R0+0
    sta (_fcb), y
    iny
    sta (_fcb), y

    ; icax1 contains the direction: 0x04 for read, 0x08 for write, 0x0c for
    ; bidirectional. The only option we care about is writing, which creates a
    ; new file.

    ldx a2+0
    lda icax1, x
    #if .byte @ == #0x08
        ; Open for output. First, delete the old file.

        lda _fcb+0
        ldx _fcb+1
        ldy #BDOS_DELETE_FILE
        jsr BDOS

        ; Then try to create a new one.

        ldy #BDOS_CREATE_FILE
    #else
        ; Otherwise, just open it.

        ldy #BDOS_OPEN_FILE
    #end
    lda _fcb+0
    ldx _fcb+1
    jsr bdose
    
    ldy #1
    rts
.endp

.proc file_putchars
    jsr claim_fcb
        
    mwa icbal,x _t1
    ?loop:
        lda icbll, x
        ora icblh, x
        beq ?endloop
        
        ldy #0
        lda (_t1), y
        jsr file_putchar

        inw _t1

        dew icbll,x
        jmp ?loop
    ?endloop:
    ldy #1
    rts
.endp

.proc file_getchars
    jsr claim_fcb
        
    mwa icbal,x _t1
    ?loop:
        lda icbll,x
        ora icblh, x
        beq ?endloop
        
        jsr file_getchar
        bcs ?exit
        ldy #0
        sta (_t1), y

        inw _t1

        dew icbll,x
        jmp ?loop
?endloop:
    ldy #1
?exit:
    rts
.endp

; Don't use _t1 here.
.proc file_putchar
    pha
    jsr claim_fcb
    jsr change_buffers

    ; Do the write.
    
    lda #FCB_BUFFER
    clc
    adc icax5, x
    tay
    pla
    sta (_fcb), y

    ; The buffer is now dirty.

    lda #0x80
    ldy #FCB_DIRTY
    sta (_fcb), y
.endp
; fall through
.proc inc_cio_pointers
    ; Increment pointers.

    inc icax5, x
    lda icax5, x
    #if .byte @ == #0x80
        ; We've reached the end of this record; change the seek position to the next one.

        lda #0
        sta icax5, x

        inw icax3,x
    #end

    ldy #1
    clc
    rts
.endp

; Don't use _t1 here.
.proc file_getchar
    jsr claim_fcb
    jsr change_buffers
    bcs ?error

    ; Do the read.
    
    lda #FCB_BUFFER
    clc
    adc icax5, x
    tay
    lda (_fcb), y
    pha

    jsr inc_cio_pointers
    pla
    ldy #1
    rts

?error:
    tya
    pha

    lda #0xff
    ldy #FCB_R0
    sta (_fcb), y
    iny
    sta (_fcb), y

    pla
    tay
    rts
.endp

; Reads ASCII characters until an EOL is met.

.proc file_getrecord
    _buffer = _t3
    _maxlength = _t1+0
    _count = _t1+1
    _tempb = _t2+1
    _x = a2+0

    jsr claim_fcb
    mwa icbal,x _buffer
    
    ldy #0
    sty _count
    dey
    lda icblh, x
    sne:ldy icbll, x
    sty _maxlength
    
    ?loop:
        ldx _x
        jsr file_getchar
        
        ; Finished?

        cmp #13
        beq ?loop
        cmp #10
        beq ?eol
        cmp #0
        beq ?eof
        cmp #27
        beq ?eof

        ldy _count
        sta (_buffer), y
        jsr direct_print
        inc _count
        
        ldy _count
        cpy _maxlength
    bne ?loop
    jmp errorLineTooLong

?eof:
    ldy #0
    beq ?exit           ; always taken

?eol:
    ldy #1              ; not eof
?exit:
    tya
    pha

    jsr direct_nl
    ldy _count
    lda #0x9b
    sta (_buffer), y

    ldx _x
    lda _count
    sta icbll, x
    lda #0
    sta icblh, x
    
    pla
    tay
    rts

.endp

; Seeks to the position in the IOCB, flushing and loading the buffer as
; required.

.proc change_buffers
    ldy #FCB_R0+0
    lda (_fcb), y
    cmp icax3, x
    bne ?seek_required
    iny
    lda (_fcb), y
    cmp icax4, x
    bne ?seek_required
    clc
    rts

?seek_required:
    jsr flush_buffer

    ; Set up for reading the new record.

    ldy #FCB_R0
    lda icax3, x
    sta (_fcb), y
    iny
    lda icax4, x
    sta (_fcb), y

    ; Do it.

    lda icax1, x
    #if .byte @ == #0x08
        ; If we're output only, we don't actually need to read the next record.
        ; We just clear it.

        ldy #FCB_BUFFER
        lda #0
    ?clear_loop:
        sta (_fcb), y
        iny
        cpy #FCB_BUFFER + 0x80
        bne ?clear_loop
        
        ldy #1
        clc
        rts
    #end

    ; For all other modes, we need to read the next record.

    lda _fcb+0
    add #FCB_BUFFER
    ldx _fcb+1
    scc:inx
    ldy #BDOS_SET_DMA_ADDRESS
    jsr BDOS

    lda _fcb+0
    ldx _fcb+1
    ldy #BDOS_READ_RANDOM
    jsr BDOS
    ldx a2+0

    ldy #1              ; normal success
    scs:rts

    ; Error handling. Results of NODATA or NOEXTENT mean eof.

    cmp #CPME_NODATA
    beq ?eof
    cmp #CPME_NOEXTENT
    beq ?eof

    ; Otherwise it's an I/O error.

    jmp errorIO

?eof:
    ldy #0
    sec
    rts
.endp

.proc flush_buffer
    ; If the buffer isn't dirty, it doesn't need flushing.

    ldy #FCB_DIRTY
    lda (_fcb), y
    smi:rts
    
    ; Do the write.

    lda _fcb+0
    add #FCB_BUFFER
    ldx _fcb+1
    scc:inx
    ldy #BDOS_SET_DMA_ADDRESS
    jsr BDOS

    lda _fcb+0
    ldx _fcb+1
    ldy #BDOS_WRITE_RANDOM
    jsr bdose
    ldx a2+0

    ldy #FCB_DIRTY
    lda #0
    sta (_fcb), y
    rts
.endp

.proc file_close
    lda ichid, x
    ldy #0
    cmp #0xff           ; is this IOCB already closed?
    sne:rts

    ; Flush the file.

    jsr claim_fcb
    jsr flush_buffer

    ; Mark the IOCB as closed.

    lda #0xff
    sta ichid, x

    ; Close it.

    lda _fcb+0
    ldx _fcb+1
    ldy #BDOS_CLOSE_FILE
    jsr bdose

    ldy #1
    rts
.endp

.proc ciov_console
    lda iccmd, x
    cmp #CIOCmdPutChars
    jeq console_putchars
    cmp #CIOCmdGetRecord
    jeq console_getrecord
    cmp #CIOCmdClose
    jeq console_nop
    cmp #CIOCmdOpen
    jeq console_nop
    jmp errorIO
.endp

.proc console_putchars
    mwa icbal,x _t1
    ?loop:
        lda icbll,x
        ora icblh, x
        beq ?endloop
        
        ldy #0
        lda (_t1), y
        jsr console_putchar

        inw _t1

        dew icbll,x
        jmp ?loop
    ?endloop:

    ldy #1
    rts
.endp

.proc console_nop
    ; Do nothing.
    ldy #1
    rts
.endp

.proc console_putchar
    stx a2+0
    
    #if .byte @ == #0x9b
        lda #0x0d
        jsr direct_print
        lda #0x0a
    #end

    jsr direct_print
    
    ; This is a good opportunity to check for ^C.

    ldx #0xff
    ldy #BDOS_DIRECT_IO
    jsr BDOS
    ldx #0
    cmp #3
    sne:sta brkkey

    ldx a2+0
    ldy #1
    rts
.endp

; Reads a line from the console. It is written to icbal/h, and can be of length icbll/h.
.proc console_getrecord
    _buffer = _t0
    _maxlength = _t1+0
    _count = _t1+1
    _tempb = _t2+0

    mwa icbal,x _buffer
    
    ldy #0
    sty _count
    dey
    lda icblh, x
    sne:ldy icbll, x
    sty _maxlength
    
    ?loop:
        ; Read a key without echo.

        ldx #0xfd
        ldy #BDOS_DIRECT_IO
        jsr BDOS
        
        ; Delete?

        cmp #8
        sne:lda #127
        cmp #127
        bne ?not_deletechar
            ldx _count
            beq ?loop

            dec _count
            jsr direct_print
            jmp ?loop
        ?not_deletechar:
        
        ; Retype line?

        cmp #18
        bne ?not_retype
            jsr direct_nl

            lda #0
            sta _tempb
            ?printloop:
                ldy _tempb
                cpy _count
                beq ?loop

                lda (_buffer), y
                jsr direct_print
                inc _tempb
            jmp ?printloop
        ?not_retype:

        ; Delete line?

        cmp #21
        bne ?not_delete
            lda #'#'
            jsr direct_print
            jsr direct_nl

            lda #0
            sta _count
            beq ?loop       ; always taken
        ?not_delete:

        ; Ctrl+C?
        cmp #3
        bne ?not_ctrlc
            lda #0
            sta brkkey
            lda #0
            sta _count
            beq ?exit       ; always taken
        ?not_ctrlc:
        
        ; Finished?

        cmp #13
        beq ?exit
        cmp #10
        beq ?exit

        ; Graphic character?

        cmp #32
        bcc ?loop

        ldy _count
        cpy _maxlength
        beq ?loop

        sta (_buffer), y
        jsr direct_print
        inc _count
        bne ?loop           ; always taken

?exit:
    jsr direct_nl
    ldy _count
    lda #0x9b
    sta (_buffer), y
    
    ldx #0                  ; IOCB pointer for console
    ldy #1
    rts
.endp

; Use direct I/O to print A.

direct_nl:
    lda #0x0d
    jsr direct_print
    lda #0x0a
.proc direct_print
    #if .byte @ > #127
        rts
    #end
    ldy #BDOS_DIRECT_IO
    ldx #0
    jmp BDOS
.endp

; Calls the BDOS, returning an error code in Y.

.proc bdose
    jsr BDOS
    ldx a2+0                ; restore X
    scs:rts
    jmp errorIO
.endp
