    .include "cpm65.inc"
    .include "zif.inc"

    .code
    CPM65_BARE_HEADER

    sta bios+0
    stx bios+1

    ldy #BIOS_CONOUT
    lda #'q'
    jsr callbios

    jmp *

callbios:
bios = callbios + 1
    jmp 0
    
    .bss

