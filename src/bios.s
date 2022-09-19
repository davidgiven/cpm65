    .include "zif.inc"
    .include "mos.inc"
    .include "cpm65.inc"

    .import __ZEROPAGE_LOAD__
    .import __ZEROPAGE_SIZE__

    .zeropage

ptr: .word 0

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
    lda #4-1            ; rts addresses are one before the target
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
    sta ptr+0
    lda biostable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

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

.proc entry_CONIN
    lda pending_key
    zif_eq
        jsr OSRDCH
    zendif

    ldx #0
    stx pending_key
    rts
.endproc

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

.proc entry_SELDSK
    cmp #0
    zif_ne
        sec                 ; invalid drive
        rts
    zendif

    lda #<dph
    ldx #>dph
    clc
    rts
.endproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

.proc entry_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil_mi
    rts
.endproc

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

.proc init_control_block
    ldy #(osgbpb_block_end - osgbpb_block - 1)
    lda #0
    zrepeat
        sta osgbpb_block, y
        dey
    zuntil_mi

    lda filehandle
    sta osgbpb_block+0
    lda dma+0
    sta osgbpb_block+1
    lda dma+1
    sta osgbpb_block+2
    lda #128
    sta osgbpb_block+5

    ldy #2
    zrepeat
        lda sector_num+0, y
        sta osgbpb_block+10, y
        dey
    zuntil_mi

    clc
    ldx #3
    zrepeat
        ror osgbpb_block+9, x
        dex
    zuntil_mi
    
    rts
.endproc

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

.proc entry_RELOCATE
    sta ptr+0
    stx ptr+1
    pha                 ; store pointer for second pass
    txa
    pha

    ldy #comhdr::rel_offset ; add relocation table offset
    clc
    lda (ptr), y
    adc ptr+0
    sta reloptr+0
    iny
    lda (ptr), y
    adc ptr+1
    sta reloptr+1

    ldx zp_base
    jsr relocate_loop   ; relocate zero page

    pla
    sta ptr+1
    pla
    sta ptr+0
    ldx mem_base
    ; fall through

    ; ptr points at the beginning of the image
    ; reloptr points at the relocation table
    ; x is value to add
relocate_loop:
    ldy #0
    zloop
        ::reloptr = * + 1
        lda $ffff           ; get relocation byte
        inc reloptr+0       ; add one to pointer
        zif_eq
            inc reloptr+1
        zendif
        cmp #$ff
        zbreakif_eq

        pha
        clc
        adc ptr+0
        sta ptr+0
        zif_cs
            inc ptr+1
        zendif
        pla

        cmp #$fe
        zcontinueif_eq

        ; ptr is pointing at the address to fix up.

        clc
        txa
        adc (ptr), y
        sta (ptr), y
    zendloop
    rts
.endproc

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

.macro define_drive sectors, blocksize, dirents, reserved
    .scope
        .word 0, 0, 0, 0    ; CP/M workspace
        .word directory_buffer
        .word dpb
        .word checksum_buffer
        .word allocation_vector

        .if blocksize = 1024
            block_shift = 3
        .elseif blocksize = 2048
            block_shift = 4
        .elseif blocksize = 4096
            block_shift = 5
        .elseif blocksize = 8192
            block_shift = 6
        .elseif blocksize = 16384
            block_shift = 7
        .else
            .fatal "Invalid block size!"
        .endif

        checksum_buffer_size = (dirents+3) / 4
        blocks_on_disk = sectors * 128 / blocksize
        allocation_vector_size = (blocks_on_disk + 7) / 8
        directory_blocks = (dirents * 32) / blocksize

        .if directory_blocks = 0
            .fatal "Directory must be at least one block in size!"
        .endif
        .if ((dirents * 32) .mod blocksize) <> 0
            .fatal "Directory is not an even number of blocks in size!"
        .endif

        .if blocks_on_disk < 256
            .if blocksize = 1024
                extent_mask = %00000000
            .elseif blocksize = 2048
                extent_mask = %00000001
            .elseif blocksize = 4096
                extent_mask = %00000011
            .elseif blocksize = 8192
                extent_mask = %00000111
            .elseif blocksize = 16384
                extent_mask = %00001111
            .endif
        .else
            .if blocksize = 1024
                .fatal "Can't use a block size of 1024 on a large disk"
            .elseif blocksize = 2048
                extent_mask = %00000000
            .elseif blocksize = 4096
                extent_mask = %00000001
            .elseif blocksize = 8192
                extent_mask = %00000011
            .elseif blocksize = 16384
                extent_mask = %00000111
            .endif
        .endif
    dpb:
        .word 0             ; unused
        .byte block_shift   ; block shift
        .byte (1<<block_shift)-1 ; block mask
        .byte extent_mask   ; extent mask
        .word blocks_on_disk - 1 ; number of blocks on the disk
        .word dirents - 1   ; number of directory entries
        .dbyt ($ffff << (16 - directory_blocks)) & $ffff ; allocation bitmap
        .word checksum_buffer_size ; checksum vector size
        .word reserved      ; number of reserved _sectors_ on disk

        .pushseg
        .bss
        checksum_buffer: .res checksum_buffer_size
        allocation_vector: .res allocation_vector_size

        .popseg
    .endscope
.endmacro

; DPH for drive 0 (our only drive)

dph: define_drive 40*32, 2048, 64, 0

    .bss
mem_base: .byte 0
mem_end:  .byte 0

filehandle:  .byte 0    ; file handle of disk image
pending_key: .byte 0    ; pending keypress from system
dma:         .word 0    ; current DMA
sector_num:  .res 3     ; current absolute sector number

directory_buffer: .res 128

osgbpb_block:           ; block used by entry_READ and entry_WRITE
    .res $0d
osgbpb_block_end:

; vim: filetype=asm sw=4 ts=4 et

