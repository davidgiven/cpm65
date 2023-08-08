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
        mwa icbal,x temp0
        mwa icbll,x temp1
        ?loop:
            lda temp1+0
            ora temp1+1
            beq ?endloop
            
            ldy #0
            lda (temp0), y
            jsr console_putchar

            inc temp0+0
            sne:inc temp0+1

            lda temp1+0
            sub #1
            sta temp1+0
            scs:dec temp1+1
        
            jmp ?loop
        ?endloop:
        ldy #0
        rts
    #end
    #if .byte @ == #CIOCmdGetRecord
        jmp console_getrecord
    #end
    brk
    rts
.endp

.proc console_putchar
    #if .byte @ == #0x9b
        lda #10
        jsr console_putchar
        lda #13
    #end
    #if .byte @ >= #0x80
        rts
    #end
    ldy #BDOS_CONSOLE_OUTPUT
    jmp BDOS
.endp

.proc console_getrecord
    mwa icbal,x temp0
    ldy #0
    lda #0xff
    sta (temp0), y
    
    txa
    pha

    lda temp0+0
    ldx temp0+1
    ldy #BDOS_READ_LINE
    jsr BDOS

    ldy #1
    lda (temp0), y          ; get line length
    sta temp1+0
    ldy #0
?loop:
    iny
    iny
    lda (temp0), y
    dey
    dey
    sta (temp0), y
    iny
    cpy temp1+0
    bne ?loop
    
    ldy temp1+0
    lda #0x9b
    sta (temp0), y

    pla
    tax
    ldy temp1+0
    iny
    tya
    sta icbll, x
    lda #0
    sta icblh, x

    ldy #1
    rts
.endp
