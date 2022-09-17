    .include "zif.inc"
    .include "mos.inc"

	.import __ZEROPAGE_LOAD__
	.import __ZEROPAGE_SIZE__

	.zeropage

ptr1: .word 0
ptr2: .word 0

    .code

    lda #<banner
    ldx #>banner
    jsr print_s

    ; Figure out the start and end of the TPA.

    lda #$83
    jsr OSBYTE
    sty mem_base

    lda #$84
    jsr OSBYTE
    sty mem_end

    ; Load the BDOS image.

    lda mem_base
    sta bdos_osfile_block + 3
    lda #$ff
    ldx #<bdos_osfile_block
    ldy #>bdos_osfile_block
    jsr OSFILE

    ; Relocate it.

    lda #0
    ldx mem_base
    jsr entry_RELOCATE

    ; Compute the entry address and jump.

    lda mem_base
    pha
    lda #3-1            ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts

    ; BIOS entry point. Parameter is in XA, function in Y.
biosentry:
    pha
    lda biostable_lo, y
    sta ptr1+0
    lda biostable_hi, y
    sta ptr1+1
    pla
    jmp (ptr1)

biostable_lo:
    .byte <entry_CONST
    .byte <OSRDCH
    .byte <OSWRCH
    .byte <entry_SELDSK
    .byte <entry_SETTRK
    .byte <entry_SETSEC
    .byte <entry_SETDMA
    .byte <entry_READ
    .byte <entry_WRITE
    .byte <entry_RELOCATE
    .byte <entry_GETTPA
    .byte <entry_SETTPA
    .byte <entry_GETZP
    .byte <entry_SETZP
biostable_hi:
    .byte >entry_CONST
    .byte >OSRDCH
    .byte >OSWRCH
    .byte >entry_SELDSK
    .byte >entry_SETTRK
    .byte >entry_SETSEC
    .byte >entry_SETDMA
    .byte >entry_READ
    .byte >entry_WRITE
    .byte >entry_RELOCATE
    .byte >entry_GETTPA
    .byte >entry_SETTPA
    .byte >entry_GETZP
    .byte >entry_SETZP
    
entry_BOOT:
entry_WBOOT:
entry_CONST:
entry_CONIN:
entry_CONOUT:
entry_SELDSK:
entry_SETTRK:
entry_SETSEC:
entry_SETDMA:
entry_READ:
entry_WRITE:
entry_GETTPA:
entry_SETTPA:
entry_GETZP:
entry_SETZP:
    jmp *

    ; Relocate an image whose pointer is in XA.

entry_RELOCATE:
    sta ptr1+0
    stx ptr1+1
    pha                 ; store pointer for second pass
    txa
    pha

    ldy #1              ; add relocation table offset
    clc
    lda (ptr1), y
    adc ptr1+0
    sta ptr2+0
    iny
    lda (ptr1), y
    adc ptr1+1
    sta ptr2+1

    ldx zp_base
    jsr relocate_loop   ; relocate zero page

    pla
    sta ptr1+1
    pla
    sta ptr1+0
    ldx mem_base
    jmp relocate_loop

    ; ptr1 points at the beginning of the image
    ; ptr2 points at the relocation table
    ; x is value to add
relocate_loop:
    ldy #0
@loop:
    lda (ptr2), y       ; get relocation byte
    inc ptr2+0          ; add one to pointer
    bne :+
    inc ptr2+1
:
    cmp #$ff
    beq @done

    pha
    clc
    adc ptr1+0
    sta ptr1+0
    bcc :+
    inc ptr1+1
:
    pla

    cmp #$fe
    beq @loop

    ; ptr1 is pointing at the address to fix up.

    clc
    txa
    adc (ptr1), y
    sta (ptr1), y

    jmp @loop
@done:
    rts

    ; Writes out the string in XA.

print_s:
    sta ptr1+0
    stx ptr1+1
    ldy #0
@loop:
    lda (ptr1), y
    beq @exit
    jsr OSWRCH
    iny
    jmp @loop
@exit:
    rts
    
print_h8:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_h4
    pla
print_h4:
    and #%00001111
    ora #'0'
    cmp #'9'+1
    bcc :+
    adc #6
:   jmp OSWRCH

    .data
zp_base: .byte <(__ZEROPAGE_LOAD__ + __ZEROPAGE_SIZE__)
zp_end:  .byte $90

bdos_osfile_block:
    .word bdos_filename ; filename
    .word 0             ; load address low
    .word 0             ; load address high
    .word 0             ; exec address low
    .word 0             ; exec address high
    .word 0             ; length low
    .word 0             ; length high
    .word 0             ; attrs low
    .word 0             ; attrs high
    
bdos_filename:
    .byte "BDOS", 13

banner:
    .byte "CP/M-65", 10, 13, 0

    .bss
mem_base: .byte 0
mem_end:  .byte 0

