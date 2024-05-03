.include "cpm65.inc"

.label test_string

.zproc start
    lda #<test_string
    ldx #>test_string
    ldy #BDOS_PRINTSTRING
    jsr BDOS

    rts
.zendproc

test_string:
    .byte 26, "ADM-3A TEST - Screen cleared", 11,11, 13,10
    .byte "Doing LF", 10, "here, then CR", 13, "[CR]", 13,10,13,10
    .byte "Testing ", 11, "upline", 13, 10, 13, 10
    .byte "Testing non-destructive BS", 8,8, 12,12,12, "and FF", 13,10
    .byte 30, 12,12,12,12,12,12,12, "Test"
\ we cannot test position 4 because that's $ which is also BDOS end-of-string
    .byte 27, '=', 32+10, 32+10, "Position 10,10"
    .byte 27, '=', 32+15, 32+20, "Move to 20,15"
    .byte 27, '=', 32+20, 32+5, 27, "IIgnore invalid escape", 13,10
    .byte 27, '=', 32+22, 32+2, "Press ENTER to scroll", 13,10
    .byte 0
