; Altirra BASIC - READ/INPUT data module
; Copyright (C) 2023 David Given, All Rights Reserved.
;
; Copying and distribution of this file, with or without modification,
; are permitted in any medium without royalty provided the copyright
; notice and this notice are preserved.  This file is offered as-is,
; without any warranty.

.proc initcio
    ldy #0xff
    sty brkkey
    iny
    sty ichid
    lda #<(console_putchar-1)
    sta icptl
    lda #>(console_putchar-1)
    sta icpth
    
    lda #0x10
?loop:
    tax
    lda #0xff
    sta ichid, x
    txa
    add #0x10
    bpl ?loop
    
    rts
.endp

.proc ciov
    lda ichid, x
    beq ciov_console

    lda iccmd, x
    #if .byte @ == #CIOCmdClose
        lda #0xff
        sta ichid, x
        ldy #0
        rts
    #end
    brk
    rts
.endp

.proc ciov_console
    lda iccmd, x
    #if .byte @ == #CIOCmdPutChars
        mwa icbal,x ztemp3
        mwa icbll,x ztemp1
        ?loop:
            lda ztemp1+0
            ora ztemp1+1
            beq ?endloop
            
            ldy #0
            lda (ztemp3), y
            jsr console_putchar

            inc ztemp3+0
            sne:inc ztemp3+1

            lda ztemp1+0
            sub #1
            sta ztemp1+0
            scs:dec ztemp1+1
        
            jmp ?loop
        ?endloop:
        ldy #0
        rts
    #end
    #if .byte @ == #CIOCmdGetRecord
        jmp console_getrecord
    #end
    #if .byte @ == #CIOCmdClose
        ; Ignore attempts to close the console.
        ldy #0
        rts
    #end
    brk
    rts
.endp

.proc console_putchar
    #if .byte @ == #0x9b
        lda #13
        jsr console_putchar
        lda #10
    #end
    #if .byte @ >= #0x80
        rts
    #end
    ldy #BDOS_CONSOLE_OUTPUT
    jmp BDOS
.endp

.proc console_getrecord
    mwa icbal,x ztemp3
    ldy #0
    lda #0xff
    sta (ztemp3), y
    
    txa
    pha

    lda ztemp3+0
    ldx ztemp3+1
    ldy #BDOS_READ_LINE
    jsr BDOS

    ; Rewrite the buffer into the format which atbasic expects.

    ldy #1
    lda (ztemp3), y          ; get line length
    sta ztemp1+0
    ldy #0
?loop:
    iny
    iny
    lda (ztemp3), y
    dey
    dey
    sta (ztemp3), y
    iny
    cpy ztemp1+0
    bne ?loop
    
    ldy ztemp1+0
    lda #0x9b
    sta (ztemp3), y

    pla
    tax
    ldy ztemp1+0
    iny
    tya
    sta icbll, x
    lda #0
    sta icblh, x

    ; Print a newline (CP/M doesn't).
    
    lda #0x9b
    jsr console_putchar

    ldy #1
    rts
.endp
