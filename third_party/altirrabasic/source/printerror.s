.proc print_error
    ldx fr0
    #if .byte @ > #28
?fallback:
        jmp IoPrintInt
    #end

    lda error_table, x
    cmp #0xff
    beq ?fallback
    
    add #<errors_start
    sta inbuff+0
    lda #>errors_start
    adc #0
    sta inbuff+1

?loop:
    ldy #0
    lda (inbuff), y
    beq ?exit
    cmp #1
    beq ?printerror
    jsr	IoPutCharAndInc
    bpl	?loop			;!! - unconditional
?exit:
    rts
?printerror:
    mwa #error_msg inbuff
    jmp ?loop
error_msg:
    dta c' error', 0

    ; 1 = " error" and stop
errors_start:
error_2:    dta c"out of memory", 0
error_3:    dta c"value", 1
error_4:    dta c"too many variables", 0
error_5:    dta c"bad string length", 0
error_6:    dta c"out of data", 0
error_7:    dta c"value greater than 32K", 0
error_8:    dta c"input", 1
error_9:    dta c"DIM", 1
error_11:   dta c"math", 1
error_12:   dta c"line not found", 0
error_13:   dta c"no matching FOR", 0
error_14:   dta c"line too long", 0
error_15:   dta c"GOSUB or FOR gone", 0
error_16:   dta c"bad RETURN", 0
error_17:   dta c"syntax", 1
error_18:   dta c"invalid string", 0
error_19:   dta c"load", 1
error_20:   dta c"bad device number", 0
error_28:   dta c"invalid structure", 0

.macro error_entry
    dta :1 - errors_start
.endm

error_table:
    dta 0xff
    dta 0xff
    error_entry error_2
    error_entry error_3
    error_entry error_4
    error_entry error_5
    error_entry error_6
    error_entry error_7
    error_entry error_8
    error_entry error_9
    dta 0xff
    error_entry error_11
    error_entry error_12
    error_entry error_13
    error_entry error_14
    error_entry error_15
    error_entry error_16
    error_entry error_17
    error_entry error_18
    error_entry error_19
    error_entry error_20
    dta 0xff
    dta 0xff
    dta 0xff
    dta 0xff
    dta 0xff
    dta 0xff
    dta 0xff
    error_entry error_28
.endp

.proc do_print_error
.endp

