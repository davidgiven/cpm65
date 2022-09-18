    .include "zif.inc"
    .include "mos.inc"

    .import __ZEROPAGE_LOAD__
    .import __ZEROPAGE_SIZE__

    .zeropage

ptr1: .word 0
ptr2: .word 0

    .code

; --- Initialisation code ---------------------------------------------------

; Called once on startup and then never again.
; TODO: figure out a way to discard this after startup.

    ; Print banner.

    ldy #banner_end - banner
:
    lda banner - 1, y
    jsr OSWRCH
    dey
    bne :-

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

    ; Open the file system image file.

    lda #$c0            ; open file for r/w
    ldx #<cpmfs_filename
    ldy #>cpmfs_filename
    jsr OSFIND
    sta filehandle

    ; Compute the entry address and jump.

    lda mem_base
    pha
    lda #3-1            ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump

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
    .byte 13, 10, 13, 10, "56-M/PC" ; reversed!
banner_end:

cpmfs_filename:
    .byte "CPMFS", 13

; --- BIOS entrypoints ------------------------------------------------------

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
    .lobytes entry_CONST
    .lobytes entry_CONIN
    .lobytes OSWRCH
    .lobytes entry_SELDSK
    .lobytes entry_SETSEC
    .lobytes entry_SETDMA
    .lobytes entry_READ
    .lobytes entry_WRITE
    .lobytes entry_RELOCATE
    .lobytes entry_GETTPA
    .lobytes entry_SETTPA
    .lobytes entry_GETZP
    .lobytes entry_SETZP
biostable_hi:
    .hibytes entry_CONST
    .hibytes entry_CONIN
    .hibytes OSWRCH
    .hibytes entry_SELDSK
    .hibytes entry_SETSEC
    .hibytes entry_SETDMA
    .hibytes entry_READ
    .hibytes entry_WRITE
    .hibytes entry_RELOCATE
    .hibytes entry_GETTPA
    .hibytes entry_SETTPA
    .hibytes entry_GETZP
    .hibytes entry_SETZP

; Blocks and waits for the next keypress; returns it in A.

entry_CONIN:
    lda pending_key
    bne @exit
    jsr OSRDCH
@exit:
    ldx #0
    stx pending_key
    rts

entry_CONST:
    lda pending_key
    bne @yes
    lda #$81
    ldx #0
    ldy #0
    jsr OSBYTE
    bcs @no
    sta pending_key
@yes:
    lda #$ff
    rts
@no:
    lda #0
    rts

; Sets the current DMA address.

entry_SETDMA:
    sta dma+0
    stx dma+1
    rts

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

entry_SELDSK:
    cmp #0
    beq :+
    sec                 ; invalid drive
    rts
:
    lda #<dph
    ldx #>dph
    clc
    rts

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

entry_SETSEC:
    sta ptr1+0
    stx ptr1+1
    ldy #2
@loop:
    lda (ptr1), y
    sta sector_num, y
    dey
    bpl @loop
    rts

entry_READ:
    jsr init_control_block
    lda #3              ; read bytes using pointer
    jmp do_gbpb

entry_WRITE:
    jsr init_control_block
    lda #1              ; write bytes using pointer
do_gbpb:
    ldx #<osgbpb_block
    ldy #>osgbpb_block
    jsr OSGBPB
    lda #0
    rol a
    rts

init_control_block:
    ldy #(osgbpb_block_end - osgbpb_block - 1)
    lda #0
:
    sta osgbpb_block, y
    dey
    bpl :-

    lda filehandle
    sta osgbpb_block+0
    lda dma+0
    sta osgbpb_block+1
    lda dma+1
    sta osgbpb_block+2
    lda #128
    sta osgbpb_block+5

    ldy #2
:
    lda sector_num+0, y
    sta osgbpb_block+10, y
    dey
    bpl :-

    clc
    ldx #3
:
    ror osgbpb_block+9, x
    dex
    bpl :-
    
    rts

entry_GETTPA:
    lda mem_base
    ldx mem_end
    rts

entry_SETTPA:
    sta mem_base
    stx mem_end
    rts

entry_GETZP:
    lda zp_base
    ldx zp_end
    rts

entry_SETZP:
    sta zp_base
    stx zp_end
    rts

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
    ; fall through

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

; DPH for drive 0 (our only drive)

dph:
    .word 0             ; sector translation table
    .word 0, 0, 0       ; CP/M workspace
    .word directory_buffer
    .word dpb
    .word checksum_buffer
    .word allocation_vector

; DPB for drive 0 (our only drive)

dpb:
    .word 0             ; number of sectors per track (unused)
    .byte 3             ; block shift
    .byte %00000111     ; block mask
    .byte %11111110     ; extent mask
    .word (40 * 32 * 128 / 1024) - 1 ; number of blocks on the disk
    .word 63            ; number of directory entries
    .byte %11000000     ; allocation bitmap byte 0
    .byte %00000000     ; allocation bitmap byte 1
    .word (64+3) / 4    ; checksum vector size
    .word 0             ; number of reserved _sectors_ on disk

    .bss
mem_base: .byte 0
mem_end:  .byte 0

filehandle: .byte 0     ; file handle of disk image
pending_key: .byte 0    ; pending keypress from system
dma:        .word 0     ; current DMA
sector_num: .res 3      ; current absolute sector number

directory_buffer: .res 128
checksum_buffer:  .res (64+3) / 4
allocation_vector: .res ((40 * 32 * 128 / 1024) + 7) / 8

osgbpb_block:           ; block used by entry_READ and entry_WRITE
    .res $0d
osgbpb_block_end:

; vim: filetype=asm sw=4 ts=4 et

