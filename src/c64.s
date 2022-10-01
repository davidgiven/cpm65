.include "zif.inc"
.include "cpm65.inc"

.import __ZEROPAGE_LOAD__
.import __ZEROPAGE_SIZE__

READST = $ffb7
SETLFS = $ffba
SETNAM = $ffbd
OPEN = $ffc0
CLOSE = $ffc3
CHKIN = $ffc6
CHKOUT = $ffc9
CHRIN = $ffcf
CHROUT = $ffd2
LOAD = $ffd5
SAVE = $ffd8
CLALL = $ffe7
SETMSG = $ff90
IECIN = $ffa5
IECOUT = $ffa8
UNTALK = $ffab
UNLSTN = $ffae
LISTEN = $ffb1
TALK = $ffb4
LSTNSA = $ff93
TALKSA = $ff96
CLRCHN = $ffcc
GETIN = $ffe4

    .zeropage

ptr:        .word 0
dma:        .word 0    ; current DMA

    .code

    .word $0801
    .word :+, 1
    .byte $9e, "2061", 0
:   .word 0
entry:
    jsr init_system

    ; Open the CPMFS image.

    lda #2              ; file number
    ldx #8              ; device
    ldy #2              ; secondary address
    jsr SETLFS

    ldx #<cpmfs_filename
    ldy #>cpmfs_filename
    lda #cpmfs_filename_end - cpmfs_filename
    jsr SETNAM

    jsr OPEN
    zif_cs
        lda #<msg
        ldx #>msg
        jsr print
        jmp *
    msg:
        .byte "Cannot open CPMFS", 0
    zendif

    ; Open the command channel.

    lda #15             ; file number
    ldx #8              ; device
    ldy #15             ; secondary address
    jsr SETLFS

    lda #0              ; filename length
    jsr SETNAM

    jsr OPEN            ; always succeeds

    ; Load the BDOS.

    lda #1              ; file number
    ldx #8              ; device
    ldy #0              ; secondary address
    jsr SETLFS

    ldx #<bdos_filename
    ldy #>bdos_filename
    lda #bdos_filename_end - bdos_filename
    jsr SETNAM

    lda #0
    ldx #<(top+2)       ; LOAD skips the first two bytes
    ldy #>(top+2)       ; (which, luckily, we don't need)
    jsr LOAD ; load
    zif_cs
        lda #<msg
        ldx #>msg
        jsr print
        jmp *
    msg:
        .byte "Cannot load BDOS", 0
    zendif

    ; Relocate the BDOS.

    lda mem_base
    ldx zp_base
    jsr entry_RELOCATE

    ; Compute the entry address and jump.

    lda mem_base
    pha
    lda #4-1            ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump

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
    .lobytes entry_CONOUT
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
    .hibytes entry_CONOUT
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
        zrepeat
            jsr GETIN
            tax
        zuntil_ne
    zendif
    ldx #0
    stx pending_key

    cmp #20         ; DEL
    zif_eq
        lda #8
    zendif

    clc
    rts
.endproc

.proc entry_CONOUT
    jsr topetscii
    jsr CHROUT
    clc
    rts
.endproc

.proc entry_CONST
    lda pending_key
    bne yes

    jsr GETIN
    sta pending_key
    beq no
yes:
    lda #$ff
    clc
    rts

no:
    lda #0
    clc
    rts
.endproc

; Sets the current DMA address.

.proc entry_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
.endproc

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
    clc
    rts
.endproc

entry_GETTPA:
    lda mem_base
    ldx mem_end
    clc
    rts

entry_SETTPA:
    sta mem_base
    stx mem_end
    clc
    rts

entry_GETZP:
    lda zp_base
    ldx zp_end
    clc
    rts

entry_SETZP:
    sta zp_base
    stx zp_end
    clc
    rts

entry_READ:
    jsr seek
    jsr seek

    ldx #2                  ; set data channel as input
    jsr CHKIN

    ldy #0
    zrepeat
        jsr CHRIN
        sta (dma), y

        iny
        cpy #128
    zuntil_eq

    jsr CLRCHN

    clc
    rts

entry_WRITE:
    jsr seek
    jsr seek

    ldx #2                  ; set data channel as input
    jsr CHKOUT

    ldy #0
    zrepeat
        lda (dma), y
        jsr CHROUT

        iny
        cpy #128
    zuntil_eq

    jsr CLRCHN

    clc
    rts

; Seeks the REL file to the appropriate record.

.proc seek
    ldx #15 
    jsr CHKOUT              ; set command channel as output

    lda #'P'
    jsr CHROUT
    lda #2                  ; channel
    jsr CHROUT
    ldx sector_num+0
    ldy sector_num+1
    inx
    zif_eq
        iny
    zendif
    txa
    jsr CHROUT
    tya
    jsr CHROUT
    lda #1
    jsr CHROUT

    jsr CLRCHN

    rts
.endproc

.proc getstatus
    ldx #15
    jsr CHKIN

    zrepeat
        jsr CHRIN
        jsr CHROUT
        cmp #13
    zuntil_eq

    jsr CLRCHN
    rts
.endproc

.include "relocate.inc" ; standard entry_RELOCATE

; Prints the string at XA with the kernel.

.proc print
    sta ptr+0
    stx ptr+1

    ldy #0
    zloop
        lda (ptr), y
        zbreakif_eq

        jsr topetscii
        jsr CHROUT
        
        iny
    zendloop
    rts
.endproc

; Converts ASCII to PETSCII for printing.

.proc topetscii
    cmp #8
    zif_eq
        lda #20
        rts
    zendif
    cmp #127
    zif_eq
        lda #20
        rts
    zendif

    cmp #'A'
    zif_cs
        cmp #'Z'+1
        bcc swapcase
    zendif

    cmp #'a'
    zif_cs
        cmp #'z'+1
        bcc swapcase
    zendif
    rts

swapcase:
    eor #$20
    rts
.endproc

.proc init_system
    lda #$36
    sta 1                   ; map Basic out
    lda #0
    sta pending_key
    sta 53280               ; black border
    sta 53281               ; black background

    ; Print the startup banner (directly with CHROUT).

    ldy #0
    zloop
        lda loading_msg, y
        zbreakif_eq
        jsr CHROUT
        iny
    zendloop
    rts
.endproc

loading_msg:
    .byte 147, 14, 5, 13, "cp/m-65", 13, 13, 0

bdos_filename:
    .byte "BDOS"
bdos_filename_end:

cpmfs_filename:
    .byte "CPMFS,L,", 128
cpmfs_filename_end:

.data

zp_base:    .byte <(__ZEROPAGE_LOAD__ + __ZEROPAGE_SIZE__)
zp_end:     .byte $90
mem_base:   .byte >top
mem_end:    .byte >$d000

; DPH for drive 0 (our only drive)

dph: define_drive $600, 1024, 64, 0

.bss

pending_key: .byte 0    ; pending keypress from system
sector_num:  .res 3     ; current absolute sector number

directory_buffer: .res 128

top = (* + $ff) & ~$ff

; vim: sw=4 ts=4 et ft=asm

