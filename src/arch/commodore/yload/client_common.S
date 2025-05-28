#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

.zeropage uloadtmp
.zeropage ptr

; Tests the link integrity (crudely).

zproc yload_test_link, .text.testlink
    lda #'T'
    jsr yload_send

    ldx #0
    zrepeat
        txa
        jsr yload_send
        inx
    zuntil eq

    ldx #0
    zrepeat
        jsr yload_recv
        sta uloadtmp
        cpx uloadtmp
        zif ne
            brk
        zendif
        inx
    zuntil eq
    
    rts
zendproc

; Loads the response from an F command into ptr.

zproc yload_recv_file, .text.recvfile
    zloop
        jsr yload_recv
        zbreakif eq
        cmp #0xff
        zif eq
            ; Error!
            sec
            rts
        zendif

        tax
        ldy #0
        zrepeat
            jsr yload_recv
            sta (ptr), y
            
            inc ptr+0
            zif eq
                inc ptr+1
            zendif

            dex
        zuntil eq
    zendloop
    rts
zendproc
