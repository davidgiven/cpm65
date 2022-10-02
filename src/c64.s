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
ACPTR = $ffa5
CIOUT = $ffa8
UNTALK = $ffab
UNLSN = $ffae
LISTEN = $ffb1
TALK = $ffb4
SECOND = $ff93
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

    ; Load the BDOS (using DOS).

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

bdos_filename:
    .byte "BDOS"
bdos_filename_end:

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
    jsr change_sectors

    lda sector_num+0
    ror a               ; bottom bit -> C
    lda #0
    ror a               ; C -> top bit, producing $00 or $80
    tax

    ldy #0
    zrepeat
        lda disk_buffer, x
        sta (dma), y
        iny
        inx
        cpy #$80
    zuntil_eq

    clc
    rts

; On entry, A=0 for a normal write; A=1 to always flush to disk.

entry_WRITE:
    pha
    jsr change_sectors

    lda sector_num+0
    ror a               ; bottom bit -> C
    lda #0
    ror a               ; C -> top bit, producing $00 or $80
    tax

    ldy #0
    zrepeat
        lda (dma), y
        sta disk_buffer, x
        iny
        inx
        cpy #$80
    zuntil_eq

    lda #$80
    sta buffer_dirty

    pla
    zif_ne
        jsr flush_buffered_sector
    zendif

    clc
    rts

.proc change_sectors
    ; If the buffered sector is the one we want, just return.

    lda sector_num+0
    and #$fe
    cmp buffered_sector+0
    zif_eq
        lda sector_num+1
        cmp buffered_sector+1
        zif_eq
            lda sector_num+2
            cmp buffered_sector+2
            zif_eq
                rts
            zendif
        zendif
    zendif

    ; We need to change sectors. Flush the current one?

    jsr flush_buffered_sector

    ; Now read the new one.

    lda sector_num+0
    and #$fe
    sta buffered_sector+0
    lda sector_num+1
    sta buffered_sector+1
    lda sector_num+2
    sta buffered_sector+2

    jsr buffered_sector_to_lba
    jmp read_sector
.endproc

; Compute the current LBA sector number in XA for the buffered sector.

.proc buffered_sector_to_lba
    lda buffered_sector+1
    lsr a
    tax
    lda buffered_sector+0
    ror
    rts
.endproc

; Flush the current buffer to disk, if necessary.

.proc flush_buffered_sector
    lda buffer_dirty
    zif_mi
        jsr buffered_sector_to_lba
        jsr write_sector

        lda #0
        sta buffer_dirty
    zendif
    rts
.endproc

.include "relocate.inc" ; standard entry_RELOCATE

; Reads a 256-byte sector whose LBA index is in XA.

.proc read_sector
    jsr convert_to_ts
    pha
    tya
    pha

    lda #8
    jsr LISTEN
    lda #$6f
    jsr SECOND

    lda #'U'
    jsr CIOUT
    lda #'1'
    jsr CIOUT
    lda #2
    jsr decimal_out
    lda #0
    jsr decimal_out
    pla                 ; get sector
    jsr decimal_out
    pla                 ; get track
    jsr decimal_out

    jsr UNLSN

    ;jsr get_status

    lda #8
    jsr TALK
    lda #$62
    jsr TALKSA

    ldy #0
    zrepeat
        jsr ACPTR
        sta disk_buffer, y
        iny
    zuntil_eq

    jsr UNTALK
    rts
.endproc

; Writes a 256-byte sector whose LBA index is in XA.

.proc write_sector
    jsr convert_to_ts
    pha
    tya
    pha

    ; Reset buffer pointer.

    lda #8
    jsr LISTEN
    lda #$6f
    jsr SECOND

    lda #<reset_buffer_pointer_command
    ldx #>reset_buffer_pointer_command
    jsr string_out

    jsr UNLSN

    ; Write bytes.

    lda #8
    jsr LISTEN
    lda #$62
    jsr SECOND

    ldy #0
    zrepeat
        lda disk_buffer, y
        jsr CIOUT
        iny
    zuntil_eq

    jsr UNLSN

    ; Write buffer to disk.

    lda #8
    jsr LISTEN
    lda #$6f
    jsr SECOND

    lda #'U'
    jsr CIOUT
    lda #'2'
    jsr CIOUT
    lda #2
    jsr decimal_out
    lda #0
    jsr decimal_out
    pla                 ; get sector
    jsr decimal_out
    pla                 ; get track
    jsr decimal_out
    lda #13
    jsr CIOUT

    jsr UNLSN

    ; jsr get_status

    rts

reset_buffer_pointer_command:
    .byte "B-P 2 0", 13, 0
.endproc

; Prints an 8-bit hex number in A.
.proc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr h4
    pla
h4:
    and #%00001111
    ora #'0'
    cmp #'9'+1
	zif_cs
		adc #6
	zendif
   	pha
	jsr CHROUT
	pla
	rts
.endproc

.proc get_status
    lda #8
    jsr TALK
    lda #$6f
    jsr TALKSA

    zrepeat
        jsr ACPTR
        jsr CHROUT
        cmp #13
    zuntil_eq

    jsr UNTALK
    rts
.endproc

; Converts an LBA sector number in XA to track/sector in Y, A.

.proc convert_to_ts
    ldy #0
    zloop
        cpx #0
        zif_eq
            cmp track_size_table, y
            zif_cc
                iny     ; tracks are one-based.
                rts
            zendif
        zendif

        sec
        sbc track_size_table, y
        zif_cc
            dex
        zendif
        iny
    zendloop

track_size_table:
    .res 17, 21
    .res 7, 19
    .res 6, 18
    .res 10, 17
.endproc

; Prints a decimal number in A to the IEC output.

.proc decimal_out
    pha
    lda #' '
    jsr CIOUT
    pla

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #100
    zuntil_cc
    adc #100
    jsr digit

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #10
    zuntil_cc
    adc #10
    jsr digit
    tax
digit:
    pha
    txa
    ora #'0'
    jsr CIOUT
    pla
    rts
.endproc

.proc string_out
    sta ptr+0
    stx ptr+1

    ldy #0
    zloop
        lda (ptr), y
        zif_eq
            rts
        zendif
        jsr CIOUT
        iny
    zendloop
.endproc

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

    ; General initialisation.

    lda #0
    sta pending_key
    sta buffer_dirty
    lda #$ff
    sta buffered_sector+0
    sta buffered_sector+1
    sta buffered_sector+2

    lda #8
    jsr LISTEN
    lda #$f2
    jsr SECOND
    lda #'#'
    jsr CIOUT
    jsr UNLSN

    rts
.endproc

loading_msg:
    .byte 147, 14, 5, 13, "cp/m-65", 13, 13, 0

.data

zp_base:    .byte <(__ZEROPAGE_LOAD__ + __ZEROPAGE_SIZE__)
zp_end:     .byte $90
mem_base:   .byte >top
mem_end:    .byte >$d000

; DPH for drive 0 (our only drive)

dph: define_drive 136*10, 1024, 64, 0

.bss

pending_key: .byte 0    ; pending keypress from system
sector_num:  .res 3     ; current absolute sector number
buffered_sector: .res 3 ; sector currently in disk buffer
buffer_dirty: .res 1    ; non-zero if sector needs flushing

directory_buffer: .res 128
disk_buffer: .res 256

top = (* + $ff) & ~$ff

; vim: sw=4 ts=4 et ft=asm

