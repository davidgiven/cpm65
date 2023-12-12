start:
    lda #<message
    ldx #>message
    ldy #9
    jsr start - 3
    rts

message:
    .byte "Hello, world!", 13, 10, 0

\ vim: ts=4 sw=4 et


