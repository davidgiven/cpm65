; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"

SCREEN_80STOREOFF = 0xc000
SCREEN_80STOREON  = 0xc001
SCREEN_80COLOFF   = 0xc00c
SCREEN_80COLON    = 0xc00d
SCREEN_PAGE2OFF   = 0xc054
SCREEN_PAGE2ON    = 0xc055

KBD_READ        = 0xc000
KBD_STROBERESET = 0xc010

DISK_PH0OFF   = 0xc080 + 0x60
DISK_PH0ON    = 0xc081 + 0x60
DISK_PH1OFF   = 0xc082 + 0x60
DISK_PH1ON    = 0xc083 + 0x60
DISK_PH2OFF   = 0xc084 + 0x60
DISK_PH2ON    = 0xc085 + 0x60
DISK_PH3OFF   = 0xc086 + 0x60
DISK_PH3ON    = 0xc087 + 0x60
DISK_MOTOROFF = 0xc088 + 0x60
DISK_MOTORON  = 0xc089 + 0x60
DISK_DRIVE1   = 0xc08a + 0x60
DISK_DRIVE2   = 0xc08b + 0x60
DISK_READ     = 0xc08c + 0x60
DISK_WRITE    = 0xc08d + 0x60
DISK_READEN   = 0xc08e + 0x60
DISK_WRITEEN  = 0xc08f + 0x60

MEM_BANKING   = 0xc080

DECODE_TABLE_START = 0x96

.global _start
ZEROPAGE

.global ptr
ptr:    .word 0
ptr1:   .word 0
dma:    .word 0

track_buffer = 0xd000

; --- Initialisation code ---------------------------------------------------

; Boot sector and relocator. Loaded at 0x0800 when the disk boots. Called once
; on startup and then never again.
.section loader, "ax"
    .byte BIOS_SECTOR_COUNT ; boot loader loads this many sectors
_start:
    cli
    sta MEM_BANKING+0xb     ; R/W 0xe000 RAM; bank 1 in 0xd000
    sta MEM_BANKING+0xb     ; yes, I'm sure
    sta SCREEN_80COLON
    sta SCREEN_80STOREON
    sta SCREEN_PAGE2OFF
    ldx #0xff
    txs                     ; reset stack

    ; Relocate the BIOS to the top of memory.

    zloop
        load = .
        lda bios_load_addr
        store = .
        sta bios_exec_addr

        inc load+1
        zif_eq
            inc load+2
        zendif

        inc store+1
        zif_eq
            inc store+2
            zbreakif_eq
        zendif
    zendloop

    ; Print the startup banner.

    jsr clear_screen
    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr entry_CONOUT
        pla
        tay
        dey
    zuntil_eq

    ; Build the GCR tables.

    ldx #0x03
    ldy #0
    zrepeat
        stx ptr+0
        txa
        asl a               ; check for double ones
        bit ptr+0
        beq reject

        ora ptr+0           ; check for double zeros
        eor #0xff
        and #0x7e
        zrepeat
            bcs reject
            lsr a
        zuntil_eq

        txa
        ora #0x80
        sta encode_tab, y

        tya
        sta decode_tab - DECODE_TABLE_START + 0x80, x

        iny
    reject:
        inx
    zuntil_mi

    ; Initialise the disk.

    ldx #0
    stx current_phase
    dex
    stx buffered_track

    ; Read the BDOS from track 1 into the track buffer..

    lda #1
    jsr seek_to_track
    jsr read_track
    
    ; Copy it to the beginning of TPA1.

    lda #0
    sta ptr+0
    sta ptr1+0
    lda #>track_buffer
    sta ptr1+1
    lda #>__TPA1_START__
    sta ptr+1

    zrepeat
        ldy #0
        zrepeat
            lda (ptr1), y
            sta (ptr), y
            dey
        zuntil_eq

        inc ptr+1
        inc ptr1+1
        lda ptr+1
        and #0x0f
    zuntil_eq

    ; Relocate the BDOS.

    lda #>__TPA1_START__
    ldx #__ZEROPAGE_START__
    jsr entry_RELOCATE
	
    ; Go!

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA1_START__ + COMHDR_ENTRY

banner: ; reversed!
    .byte 13, 10
    .ascii "56-M/PC"
banner_end:

; --- BIOS entrypoints ------------------------------------------------------

; BIOS entry point. Parameter is in XA, function in Y.
zproc biosentry
    pha
    lda biostable_lo, y
    sta ptr+0
    lda biostable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

biostable_lo:
    .byte entry_CONST@mos16lo
    .byte entry_CONIN@mos16lo
    .byte entry_CONOUT@mos16lo
    .byte entry_SELDSK@mos16lo
    .byte entry_SETSEC@mos16lo
    .byte entry_SETDMA@mos16lo
    .byte entry_READ@mos16lo
    .byte entry_WRITE@mos16lo
    .byte entry_RELOCATE@mos16lo
    .byte entry_GETTPA@mos16lo
    .byte entry_SETTPA@mos16lo
    .byte entry_GETZP@mos16lo
    .byte entry_SETZP@mos16lo
    .byte entry_SETBANK@mos16lo
biostable_hi:
    .byte entry_CONST@mos16hi
    .byte entry_CONIN@mos16hi
    .byte entry_CONOUT@mos16hi
    .byte entry_SELDSK@mos16hi
    .byte entry_SETSEC@mos16hi
    .byte entry_SETDMA@mos16hi
    .byte entry_READ@mos16hi
    .byte entry_WRITE@mos16hi
    .byte entry_RELOCATE@mos16hi
    .byte entry_GETTPA@mos16hi
    .byte entry_SETTPA@mos16hi
    .byte entry_GETZP@mos16hi
    .byte entry_SETZP@mos16hi
    .byte entry_SETBANK@mos16hi
zendproc

entry_WRITE:
    rts

zproc entry_GETTPA
	ldy current_bank
    lda mem_base, y
    ldx mem_end, y
    clc
    rts
zendproc

zproc entry_SETTPA
	ldy current_bank
    sta mem_base, y
    stx mem_end, y
    clc
    rts
zendproc

zproc entry_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc

zproc entry_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc entry_SETBANK
	sta current_bank
    rts
zendproc

; --- Screen ----------------------------------------------------------------

; Writes the character in A.

zproc entry_CONOUT
    cmp #13
    zif_eq
        lda #0
        sta cursorx
        rts
    zendif
    cmp #127
    zif_eq
        dec cursorx
        zif_mi
            inc cursorx
        zendif
        jsr prepare_for_screen_write
        lda #0xa0
        sta (ptr), y
        rts
    zendif
    cmp #10
    beq write_nl

    pha
    jsr prepare_for_screen_write
    pla
    eor #0x80
    sta (ptr), y

    inc cursorx
    lda cursorx
    cmp #80
    zif_eq
        lda #0
        sta cursorx
        jmp write_nl
    zendif
    rts
zendproc

zproc write_nl
    inc cursory
    lda cursory
    cmp #24
    zif_eq
        dec cursory
        jmp scroll_up
    zendif
    rts
zendproc

zproc scroll_up
    ldx #0              ; current line
    zrepeat
        txa
        jsr calculate_screen_address
        lda ptr+0
        sta ptr1+0
        lda ptr+1
        sta ptr1+1      ; ptr1 is dest pointer

        inx
        txa
        jsr calculate_screen_address ; ptr is source pointer

        ldy #39
        zrepeat
            sta SCREEN_PAGE2OFF
            lda (ptr), y
            sta (ptr1), y
            sta SCREEN_PAGE2ON
            lda (ptr), y
            sta (ptr1), y
            dey
        zuntil_mi

        cpx #23
    zuntil_eq

    ldy #39
    lda #32|0x80
    zrepeat
        sta SCREEN_PAGE2OFF
        sta (ptr), y
        sta SCREEN_PAGE2ON
        sta (ptr), y
        dey
    zuntil_mi
    rts
zendproc

; Sets ptr to the current cursor row address; also sets up the page stuff.
; Leaves Y to the screen line offset.

zproc prepare_for_screen_write
    lda cursory
    jsr calculate_screen_address
    lda cursorx
    lsr a
    tay
    lda #0
    rol
    eor #1
    tax
    sta SCREEN_PAGE2OFF, x
    rts
zendproc

; Given a row number in A, set ptr to the address of that
; row of video memory.
;
; Given a row 000abcde, the address is 000001cd eabab000.
; Preserves X and Y.
zproc calculate_screen_address
    pha
    lsr a
    and #0x03
    ora #0x04
    sta ptr+1
    pla

    lsr a           ; 0000abcd, e -> carry
    php
    and #0x0c       ; 0000ab00
    sta ptr+0
    lsr a
    lsr a           ; 000000ab
    ora ptr+0       ; 0000abab
    asl a
    asl a
    asl a
    asl a           ; abab0000
    plp
    ror a           ; eabab000
    sta ptr+0
    rts
zendproc

zproc clear_screen
    lda #24
    sta ptr1
    zrepeat
        lda ptr1
        jsr calculate_screen_address
        ldy #40
        lda #32|0x80
        zrepeat
            dey
            sta SCREEN_PAGE2ON
            sta (ptr), y
            sta SCREEN_PAGE2OFF
            sta (ptr), y
        zuntil_eq

        dec ptr1
    zuntil_mi
    lda #0
    sta cursorx
    sta cursory
    rts
zendproc


; --- Keyboard --------------------------------------------------------------

zproc entry_CONST
    ldx motor_countdown
    zif_ne
        dec motor_countdown
        zif_eq
            lda DISK_MOTOROFF
        zendif
    zendif

    ldy #0
    ldx KBD_READ
    zif_mi
        dey
    zendif

    tya
    clc
    rts
zendproc

zproc entry_CONIN
    ; Turn the disk motor off.

    lda DISK_MOTOROFF
    lda #0
    sta motor_countdown

    ; Display the cursor.

    jsr prepare_for_screen_write
    lda (ptr), y
    sta cursork
    lda #0x60           ; flashing block
    sta (ptr), y

    ; Wait for the key.

    zrepeat
        lda KBD_READ
    zuntil_mi
    sta KBD_STROBERESET
    and #0x7f
    clc

    ; Cursor off again.

    tax
    lda cursork
    sta (ptr), y
    txa
    rts
zendproc

; --- Disk handling ---------------------------------------------------------

; Sets the current DMA address.

zproc entry_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc entry_SELDSK
    cmp #0
    zif_ne
        sec                 ; invalid drive
        rts
    zendif

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte sector number.

zproc entry_SETSEC
	sta ptr+0
	stx ptr+1

    ; The bottom five bits need to become bits 12..7 of the
    ; offset into the track address.

    ldy #0
    lda (ptr), y
    and #0x1f
    lsr a                   ; carry contains bottom bit
    ora #>track_buffer      ; turn into an actual address
    sta wanted_trackoffset+1
    lda #0
    ror a                   ; 0x00 or 0x80
    sta wanted_trackoffset+0

    ; The rest of the sector number becomes the track number.

    lda (ptr), y
    sta ptr1+0
    iny
    lda (ptr), y

    asl ptr1+0
    rol a
    asl ptr1+0
    rol a
    asl ptr1+0
    rol a

    sta wanted_track
    rts
zendproc

; Reads the current sector to the DMA address

zproc entry_READ
    jsr change_tracks
    zif_cc
        lda wanted_trackoffset+0
        sta ptr+0
        lda wanted_trackoffset+1
        sta ptr+1

        ldy #127
        zrepeat
            lda (ptr), y
            sta (dma), y
            dey
        zuntil_mi
        clc
    zendif
    rts
zendproc

; Changes the track in the buffer.

zproc change_tracks
    lda wanted_track
    cmp buffered_track
    zif_eq
        ; If we're changing to the same track, do nothing.
        clc
        rts
    zendif

    sta buffered_track
    jsr seek_to_track

    ; fall through
zendproc

; Read the current track into the track buffer.

zproc read_track
    jsr motor_on

    ; No sectors have been read.

    ldx #15
    lda #1
    zrepeat
        sta track_flags, x
        dex
    zuntil_mi

    ; Low byte of ptr1 remains 0 throughout.

    lda #0
    sta ptr1+0

    ; Start reading sectors.

    zloop
        zrepeat
            ; Wait for the next sector header.

            zrepeat
                zrepeat
                    zrepeat
                        jsr read_header
                        cpy #0x96
                    zuntil_eq
                    jsr read_gcr44
                    jsr read_gcr44
                    jsr read_gcr44
                    
                    ; Found a sector. Has it already been read?
                    ; Remember to undo the ProDOS sector skew.

                    tax
                    lda prodos_reverse_sector_map, x
                    tax
                    ldy track_flags, x
                zuntil_ne

                ; Set up ptr1 to point to this sector's buffer.

                and #0x0f
                ora #0xd0
                sta ptr1+1

                ; Wait for the next data header.

                jsr read_header
                cpy #0xad
            zuntil_eq

            ; Reads the first section of the sector data (the twos) into the special
            ; buffer.

            ldy #0x56
            lda #0                  ; accumulated checksum
            zrepeat
                sty ptr+0
                zrepeat
                    ldy DISK_READ
                zuntil_mi
                eor decode_tab-DECODE_TABLE_START, y
                ldy ptr+0
                dey
                sta disk_twos_buffer, y
            zuntil_eq

            ; Reads the second section (the sixes) into the output buffer.
            ; Y is 0 on entry

            zrepeat
                sty ptr+0
                zrepeat
                    ldy DISK_READ
                zuntil_mi
                eor decode_tab-DECODE_TABLE_START, y
                ldy ptr+0
                sta (ptr1), y
                iny
            zuntil_eq

            ; Read the checksum byte.

            zrepeat
                ldy DISK_READ
            zuntil_mi
            eor decode_tab-DECODE_TABLE_START, y
        zuntil_eq

        ; We now have a successfully read sector. We just need to decode it.

        ldy #0
        ldx #0x56
        zrepeat
            dex
            zif_mi
                ldx #0x55
            zendif
            lda (ptr1), y
            lsr disk_twos_buffer, x
            rol a
            lsr disk_twos_buffer, x
            rol a
            sta (ptr1), y
            iny
        zuntil_eq

        ; Mark this sector as having been successfully read.

        lda ptr1+1
        and #0x0f           ; recover the sector number
        tax
        lda #0
        sta track_flags, x  ; clear sector marker

        ; Find out if we've read all the sectors yet.

        ldx #15
        lda #0
        clc
        zrepeat
            adc track_flags, x
            dex
        zuntil_mi
        tax
        zbreakif_eq
    zendloop

    clc
    rts

    ; Waits for a sector header. Returns the unencoded ID byte immediately
    ; following in Y.

read_header:
    zrepeat
        zrepeat
            zrepeat
                ldy DISK_READ
            zuntil_mi
            cpy #0xd5
        zuntil_eq
        zrepeat
            ldy DISK_READ
        zuntil_mi
        cpy #0xaa
    zuntil_eq
    zrepeat
        ldy DISK_READ
    zuntil_mi
    rts

read_gcr44:
    zrepeat
        lda DISK_READ
    zuntil_mi
    rol a
    sta ptr+0
    zrepeat
        lda DISK_READ
    zuntil_mi
    and ptr+0
    rts
zendproc

; Seek to the track number in A.

zproc seek_to_track
    jsr motor_on

    asl a               ; convert to phase number
    zloop
        cmp current_phase
        zif_eq
            rts
        zendif
        ldy #0xff           ; default to counting down
        zif_cs
            ; A > track, count up
            ldy #1
        zendif

        pha
        jsr change_phase
        jsr change_phase
        pla
    zendloop

    ; Takes in Y either +1 to change up, or -1 to change down.
    ; Preserves it.
change_phase:
    lda current_phase
    and #3
    asl a
    tax
    sta DISK_PH0OFF, x  ; turn off current phase

    tya
    clc
    adc current_phase
    sta current_phase
    and #3
    asl a
    tax
    sta DISK_PH0ON, x   ; turn on new phase

    ; Waits the appropriate amount of time for the head to move.

    lda #86
    sec
    zrepeat
        pha
        zrepeat
            sbc #1
        zuntil_eq
        pla
        sbc #1
    zuntil_eq
    rts
zendproc

; Corrupts X.

zproc motor_on
    ldx #0xff
    stx motor_countdown
    stx DISK_MOTORON
zendproc

.data
prodos_sector_map:
    .byte 0, 2, 4, 6, 8, 10, 12, 14, 1, 3, 5, 7, 9, 11, 13, 15
prodos_reverse_sector_map:
    .byte 0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA0_START__@mos16hi, __TPA1_START__@mos16hi
mem_end:    .byte __TPA0_END__@mos16hi,   __TPA1_END__@mos16hi

; DPH for drive 0 (our only drive)

define_drive dph, 0x42e, 1024, 64, 64

.bss
cursorx:            .fill 1
cursory:            .fill 1
cursork:            .fill 1
current_bank:       .fill 1
current_phase:      .fill 1
disk_twos_buffer:   .fill 86
encode_tab:         .fill 64
directory_buffer:   .fill 128
decode_tab:         .fill 0x100 - DECODE_TABLE_START
wanted_track:       .fill 1
wanted_trackoffset: .fill 2
buffered_track:     .fill 1
pending_key:        .fill 1
motor_countdown:    .fill 1
track_flags:        .fill 16

; This must go last --- it's the three 6502 vectors.
.text
nmi_handler:
reset_handler:
irq_handler:
    rti

.section tail, "ax"
    .word nmi_handler
    .word reset_handler
    .word irq_handler

; vim: filetype=asm sw=4 ts=4 et

