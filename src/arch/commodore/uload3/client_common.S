#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

.zeropage uloadtmp
.zeropage ptr

; Tests the link integrity (crudely).

zproc uload3_test_link, .text.testlink
    lda #'T'
    jsr uload3_send

    ldx #0
    zrepeat
        txa
        jsr uload3_send
        inx
    zuntil eq

    ldx #0
    zrepeat
        jsr uload3_recv
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

zproc uload3_recv_file, .text.recvfile
    zloop
        jsr uload3_recv
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
            jsr uload3_recv
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
