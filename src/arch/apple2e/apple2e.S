; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "wait.inc"
#include "driver.inc"

SCREEN_80STOREOFF = 0xc000
SCREEN_80STOREON  = 0xc001
SCREEN_80COLOFF   = 0xc00c
SCREEN_80COLON    = 0xc00d
SCREEN_PAGE2OFF   = 0xc054
SCREEN_PAGE2ON    = 0xc055

KBD_READ        = 0xc000
KBD_STROBERESET = 0xc010

; It's tempting to bake in the 0x60 offset for the drive unit at slot 6... but this
; changes the timing of the instructions which access these registers, and then
; writes don't work! You _must_ use lda <addr>, x or sta <addr>, x instructions
; (the right ones; they take 4 and 5 cycles respectively).
DISK_SLOT     = 0x60
DISK_PH0OFF   = 0xc080 ; Q0
DISK_PH0ON    = 0xc081
DISK_PH1OFF   = 0xc082 ; Q1
DISK_PH1ON    = 0xc083
DISK_PH2OFF   = 0xc084 ; Q2
DISK_PH2ON    = 0xc085
DISK_PH3OFF   = 0xc086 ; Q3
DISK_PH3ON    = 0xc087
DISK_MOTOROFF = 0xc088 ; Q4
DISK_MOTORON  = 0xc089
DISK_DRIVE1   = 0xc08a ; Q5
DISK_DRIVE2   = 0xc08b
DISK_SHIFT    = 0xc08c ; Q6
DISK_LOAD     = 0xc08d
DISK_READ     = 0xc08e ; Q7
DISK_WRITE    = 0xc08f

MEM_BANKING   = 0xc080

DECODE_TABLE_START = 0x96

.extern biosentry

.global _start
ZEROPAGE

.global ptr
.global ptr1
ptr:    .word 0
ptr1:   .word 0
dma:    .word 0

disk_sixes_buffer = 0x300
track_buffer = 0xd000

; --- Initialisation code ---------------------------------------------------

; Boot sector and relocator. Loaded at 0x0800 when the disk boots. Called once
; on startup and then never again.
.section loader, "ax"
    .byte BIOS_SECTOR_COUNT ; boot loader loads this many sectors
_start:
    cli
    lda MEM_BANKING+0xb     ; R/W 0xe000 RAM; bank 1 in 0xd000
    lda MEM_BANKING+0xb     ; yes, I'm sure
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

    ; Initialise it.

    jsr initdrivers

    ; Print the startup banner.

    jsr clear_screen
    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr bios_CONOUT
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
    stx buffer_dirty
    dex
    stx buffered_track

    ; Read the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy #>__TPA1_START__
    jsr loadfile

    ; Relocate it.

    lda #>__TPA1_START__
    ldx #__ZEROPAGE_START__
    jsr bios_RELOCATE

    ; Go!

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA1_START__ + COMHDR_ENTRY

bdos_filename:
    .ascii "BDOS    SYS"

banner: ; reversed!
    .byte 13, 10
    .ascii "II elppA eht rof 56-M/PC"
banner_end:

; --- BIOS entrypoints ------------------------------------------------------

zproc bios_GETTPA
    ldy current_bank
    lda mem_base, y
    ldx mem_end, y
    clc
    rts
zendproc

zproc bios_SETTPA
    ldy current_bank
    sta mem_base, y
    txa                 ; BUG: stx mem_end, y - invalid 6502 instruction
    sta mem_end, y
    clc
    rts
zendproc

zproc bios_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc

zproc bios_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc bios_SETBANK
    sta current_bank
    rts
zendproc

; --- TTY driver ------------------------------------------------------------

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    pha
    lda jmptable_lo, y
    sta ptr+0
    lda jmptable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

jmptable_lo:
    .byte tty_const@mos16lo
    .byte tty_conin@mos16lo
    .byte tty_conout@mos16lo
jmptable_hi:
    .byte tty_const@mos16hi
    .byte tty_conin@mos16hi
    .byte tty_conout@mos16hi
zendproc

; Writes the character in A.

zproc tty_conout
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

zproc tty_const
    ldx motor_countdown
    zif_ne
        dec motor_countdown
        zif_eq
            ldx #DISK_SLOT
            lda DISK_MOTOROFF, x
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

zproc tty_conin
    ; Turn the disk motor off.

    ldx #DISK_SLOT
    lda DISK_MOTOROFF, x
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

zproc bios_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc bios_SELDSK
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

zproc bios_SETSEC
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

zproc bios_READ
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

; On entry, A=0 for a normal write; A=1 to always flush to disk.

zproc bios_WRITE
    pha
    jsr change_tracks
    pla
    zif_cc
        pha

        lda wanted_trackoffset+0
        sta ptr+0
        lda wanted_trackoffset+1
        sta ptr+1

        ldy #127
        zrepeat
            lda (dma), y
            sta (ptr), y
            dey
        zuntil_mi

        pla
        zif_ne
            jmp write_track
        zendif

        lda #1
        sta buffer_dirty
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

    lda buffer_dirty
    zif_ne
        jsr write_track
    zendif

    lda wanted_track
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
            ldx #DISK_SLOT          ; remains here for the duration
            zrepeat
                sty ptr+0
                zrepeat
                    ldy DISK_SHIFT, x
                zuntil_mi
                eor decode_tab-DECODE_TABLE_START, y
                ldy ptr+0
                dey
                sta disk_twos_buffer, y
            zuntil_eq

            ; Reads the second section (the sixes) into the output buffer.
            ; Y is 0 on entry. X is DISK_SLOT.

            zrepeat
                sty ptr+0
                zrepeat
                    ldy DISK_SHIFT, x
                zuntil_mi
                eor decode_tab-DECODE_TABLE_START, y
                ldy ptr+0
                sta (ptr1), y
                iny
            zuntil_eq

            ; Read the checksum byte.
            ; X is still DISK_SLOT.

            zrepeat
                ldy DISK_SHIFT, x
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
    ora #DISK_SLOT      ; add in the slot offset
    tax
    sta DISK_PH0OFF, x  ; turn off current phase

    tya
    clc
    adc current_phase
    sta current_phase
    and #3
    asl a
    ora #DISK_SLOT      ; add in the slot offset
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

; Waits for a sector header. Returns the unencoded ID byte immediately
; following in Y. Preserves A.

zproc read_header
    ldx #DISK_SLOT
    zrepeat
        zrepeat
            zrepeat
                ldy DISK_SHIFT, x
            zuntil_mi
            cpy #0xd5
        zuntil_eq
        zrepeat
            ldy DISK_SHIFT, x
        zuntil_mi
        cpy #0xaa
    zuntil_eq
    zrepeat
        ldy DISK_SHIFT, x
    zuntil_mi
    rts
zendproc

; Reads and decodes a gcr44 value.
; X must be DISK_SLOT. Preserves and Y. Corrupts ptr.

zproc read_gcr44
    zrepeat
        lda DISK_SHIFT, x
    zuntil_mi
    rol a
    sta ptr+0
    zrepeat
        lda DISK_SHIFT, x
    zuntil_mi
    and ptr+0
    rts
zendproc

; Corrupts X.

zproc motor_on
    ldx #0xff
    stx motor_countdown
    ldx #DISK_SLOT
    sta DISK_MOTORON, x
    rts
zendproc

; Write the track buffer to disk.
; The timing in this routine is critical, so it's important that it doesn't
; cross page boundary. Therefore this must be the last routine in the BIOS so
; all the timing-critical bits are in the last page.

.section write_track, "ax"
    jsr motor_on
    clc

    ; Timing here is super-critical. We have 32 cycles to write each byte, and
    ; we have to be on time. Normally we'd just blat out the entire track worth
    ; of data in one go, but we don't have time to compute the sector encoding
    ; on the fly! So we have to do a normal sector-by-sector write: we compute
    ; a sector, then wait for its header, then write it, then compute the next
    ; sector and wait for its header. Because of the ProDOS sector skew we can
    ; write the entire track in two rotations.

    lda #>track_buffer  ; bottom nibble is also our ProDOS sector number
    sta ptr1+1
    lda #0
    sta ptr1+0          ; remains zero for the duration

    zloop
        lda ptr1+1
        and #0x0f
        tax

        ; Precompute the 2s and I/O buffer.

        ldx #0
        ldy #2
        zrepeat
            zrepeat
                dey

                lda (ptr1), y
                lsr a
                rol disk_twos_buffer, x
                lsr a
                rol disk_twos_buffer, x
                sta disk_sixes_buffer, y

                inx
                cpx #0x56
            zuntil_cs

            ldx #0
            tya
        zuntil_eq

        ldx #0x55
        zrepeat
            lda disk_twos_buffer, x
            and #0x3f
            sta disk_twos_buffer, x
            dex
        zuntil_mi

        ; Wait for the right sector header.

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
            lda ptr1+1
            and #0x0f
            cmp prodos_reverse_sector_map, x
        zuntil_eq

        ; Skip the tail of the sector header.

        ldy #4*4
        ; Each loop here is 8 cycles, so four times round gives a byte.
        zrepeat
            WAIT3           ; 3
            dey             ; 2
        zuntil_eq           ; 3 for every iteration

        ldx #DISK_SLOT
        lda DISK_LOAD, x    ; prime drive
        lda DISK_READ, x
        zif_mi
            sec             ; write protected
            rts
        zendif

        ; Timing-critical part starts when the first byte is queued!

            ; Write the 40-cycle sync pulses. 40 cycles means that
            ; we actually end up with 0b1111.1111.00 on disk.

            lda #0xff
            sta DISK_WRITE, x  ; start writing
            cmp DISK_SHIFT, x
/*  0 */    ldy #4                            ; 2
/*  2 */    WAIT3                             ; 3
            zrepeat
/*  5 */        WAIT12                        ; 12
/* 17 */        WAIT12                        ; 12
/* 29 */        WAIT2                         ; 3
/* 32 */        sta DISK_LOAD, x              ; 5
/* 36 */        cmp DISK_SHIFT, x             ; 4
/*  0 */        dey                           ; 2
/*  2 */    zuntil_eq       ; 3 if taken, 2 if not
/*  4 */
/* -- */    WAIT9 ; waste four cycles for the last 40-cycle sync byte.
                  ; plus five to sync up with the loop below.

            ; Write prologue. (From here on we're at 32-cycle, er, cycles.)
            ; Y is 0.

/*  5 */    ldy #sector_prologue_len      ; 2
            zrepeat
/*  7 */        WAIT12                    ; 12
/* 19 */        lda sector_prologue-1, y  ; 4
/* 23 */        sta DISK_LOAD, x          ; 5
/* 28 */        cmp DISK_SHIFT, x         ; 4
/*  0 */        WAIT2                     ; 2
/*  2 */        dey                       ; 2
/*  4 */    zuntil_eq       ; 3 if taken, 2 if not
/*  6 */

            ; Write out the 2s buffer.
            ; Y is 0.

/*  6 */    tya                           ; 2
/*  8 */    ldy #0x56                     ; 2
            zrepeat
/* 10 */        eor disk_twos_buffer-1, y ; 5 (always crosses page boundary)
/* 15 */        tax                       ; 2
/* 17 */        lda encode_tab, x         ; 4
/* 21 */        ldx #DISK_SLOT            ; 2
/* 23 */        sta DISK_LOAD, x          ; 5
/* 28 */        cmp DISK_SHIFT, x         ; 4
/*  0 */        lda disk_twos_buffer-1, y ; 5 (always crosses page boundary)
/*  5 */        dey                       ; 2
/*  7 */    zuntil_eq       ; 3 if taken, 2 is not
/*  9 */

            ; Write out the 6s buffer.
            ; (y is zero)

            zrepeat
/*  9 */        WAIT2                     ; 2
/* 11 */        eor disk_sixes_buffer, y  ; 4
/* 15 */        tax                       ; 2
/* 17 */        lda encode_tab, x         ; 4
/* 21 */        ldx #DISK_SLOT            ; 2
/* 23 */        sta DISK_LOAD, x          ; 5
/* 28 */        ora DISK_SHIFT, x         ; 4
/*  0 */        lda disk_sixes_buffer, y  ; 4
/*  4 */        iny                       ; 2
/*  6 */    zuntil_eq       ; 3 if taken, 2 if not
/*  8 */

            ; Write checksum byte.

/*  8 */    tax                           ; 2
/* 10 */    lda encode_tab, x             ; 4
/* 14 */    WAIT7                         ; 7
/* 21 */    ldx #DISK_SLOT                ; 2
/* 23 */    sta DISK_LOAD, x              ; 5
/* 28 */    ora DISK_SHIFT, x             ; 4

            ; Write epilogue.
            ; X is still DISK_SLOT.

/*  0 */    WAIT6                         ; 6
/*  6 */    WAIT7                         ; 7
/* 13 */    ldy #sector_epilogue_len      ; 2
            zrepeat
/* 15 */        lda sector_epilogue-1, y  ; 4
/* 19 */        WAIT2                     ; 2
/* 21 */        ldx #DISK_SLOT            ; 2
/* 23 */        sta DISK_LOAD, x          ; 5
/* 28 */        ora DISK_SHIFT, x         ; 4
/*  0 */        WAIT10                    ; 10
/* 10 */        dey                       ; 2
/* 12 */    zuntil_eq       ; 3 if taken, 2 if not

        ; Finished with the timing-critical stuff. Write mode off.
        ; X is still DISK_SLOT.

        lda DISK_READ, x
        lda DISK_SHIFT, x

        ; Advance to the next sector and go again.

        inc ptr1+1
        lda ptr1+1
        and #0x0f
        zif_eq
            lda #0
            sta buffer_dirty
            clc
            rts
        zendif
    zendloop

sector_prologue:
    .byte 0xad, 0xaa, 0xd5 ; REVERSED
sector_prologue_end:
sector_prologue_len = sector_prologue_end - sector_prologue
sector_epilogue:
    .byte 0xff, 0xeb, 0xaa, 0xde ; REVERSED
sector_epilogue_end:
sector_epilogue_len = sector_epilogue_end - sector_epilogue
zendproc


.data
prodos_reverse_sector_map:
    .byte 0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA0_START__@mos16hi, __TPA1_START__@mos16hi
mem_end:    .byte __TPA0_END__@mos16hi,   __TPA1_END__@mos16hi

; DPH for drive 0 (our only drive)

define_drive dph, 0x42e, 1024, 64, 32

.section aligneddata, "ax", @nobits
disk_twos_buffer:   .fill 86 ; must be aligned
encode_tab:         .fill 64 ; must be within one page

.global directory_buffer
.bss
cursorx:            .fill 1
cursory:            .fill 1
cursork:            .fill 1
current_bank:       .fill 1
current_phase:      .fill 1
directory_buffer:   .fill 128
decode_tab:         .fill 0x100 - DECODE_TABLE_START
wanted_track:       .fill 1
wanted_trackoffset: .fill 2
pending_key:        .fill 1
motor_countdown:    .fill 1
buffered_track:     .fill 1
buffer_dirty:       .fill 1
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

