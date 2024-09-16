#include "cpm65.inc"
#include "zif.inc"

ZEROPAGE
__fcb: .fill 2
__olduser: .fill 1

; Preserves XA.
zproc xfcb_clear
    pha
    lda #0
    ;ldy #xfcb::s2   ; this one is actually cleared by the BDOS
    ;sta (__fcb), y

    ldy #FCB_EX
    lda #0
    zrepeat
        sta (__fcb), y
        iny
        cpy #FCB_R2+1
    zuntil_eq

    pla
    rts
zendproc

zproc xfcb_prepare
    sta __fcb+0
    stx __fcb+1
    lda #0xff
    jsr xfcb_getsetuser
    sta __olduser
    ldy #XFCB_US
    lda (__fcb), y
    jsr xfcb_getsetuser
    lda __fcb+0
    ldx __fcb+1
    rts
zendproc

zproc xfcb_execute
    jsr BDOS
    php
    pha
    txa
    pha
    lda __olduser
    jsr xfcb_getsetuser
    pla
    tax
    pla
    plp
    rts
zendproc

zproc xfcb_getsetuser
    ldy #BDOS_GET_SET_USER_NUMBER
    jmp BDOS
zendproc

zproc xfcb_open
    jsr xfcb_prepare
    jsr xfcb_clear
    ldy #BDOS_OPEN_FILE
    jmp xfcb_execute
zendproc

zproc xfcb_close
    jsr xfcb_prepare
    ldy #BDOS_CLOSE_FILE
    jmp xfcb_execute
zendproc

zproc xfcb_erase
    jsr xfcb_prepare
    jsr xfcb_clear
    ldy #BDOS_DELETE_FILE
    jmp xfcb_execute
zendproc

zproc xfcb_readsequential
    jsr xfcb_prepare
    ldy #BDOS_READ_SEQUENTIAL
    jmp xfcb_execute
zendproc

zproc xfcb_writesequential
    jsr xfcb_prepare
    ldy #BDOS_WRITE_SEQUENTIAL
    jmp xfcb_execute
zendproc

; vim: sw=4 ts=4 et ft=asm

