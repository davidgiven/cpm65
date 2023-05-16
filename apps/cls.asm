\ cls - clear screen
BDOS_CONOUT = 2
BDOS = start-3
start:
    ldy #BDOS_CONOUT
    lda #26
    jmp BDOS

