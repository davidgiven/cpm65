; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

; K-1013 FDC registers

HSRC = 0xffe8           ; R/W   - K-1003 Hardware Status Register
ADMA = 0xffea           ; Write - K-1013 Set DMA Address Register
MSTR = 0xffee           ; Read  - NEC-765 Main Status Register 
DATR = 0xffef           ; R/W   - NEC-765 Data Register

; KIM-1 ROM entry points

OUTCH = 0x1ea0
GETCH = 0x1e5a
DELAY = 0x1ed4
DEHALF = 0x1eeb

; KIM-1 I/O

CHAR = 0xfe             ; ZP char buffer
SAD = 0x1740            ; 6530 A Data (TTY)
SBD = 0x1742            ; 6530 B data register

ZEROPAGE

.global ptr
.global ptr1
ptr: .fill 2
ptr1: .fill 2
dma: .fill 2 ; current DMA address

; BASIC loader and relocator. Needs starts at 0xc000 (K-1013 user ram )

.section loader, "ax"

.global _start
_start:
    ; Initialise.

    clc

    ; Print the startup banner (directly with OUTCH).

    ldy #0
    zloop
        tya
        pha
        lda loading_msg, y
        zbreakif_eq
        jsr OUTCH
        pla
        tay
        iny
    zendloop

    ; Relocate the bios into low ram.

1:
    srcp = . + 1
    lda __bios_data_start
    destp = . + 1
    sta __bios_start

    inc srcp+0
    zif_eq
        inc srcp+1
    zendif

    inc destp+0
    zif_eq
        inc destp+1
    zendif

    lda destp+0
    cmp #<__bios_end
    bne 1b

    lda destp+1
    cmp #>__bios_end
    bne 1b

    ; System init

    lda #0
    sta current_drive
    sta pending_key
    sta buffer_dirty
    lda #$ff
    sta buffered_host_sector

    ; BIOS initialisation.

    jsr initdrivers

    ; Open the BDOS file (using low level disk access).

    ; Read the BDOS.

    lda #<bdos_filename
    ldx #>bdos_filename
    ldy #>__TPA_START__
    jsr loadfile

    ; Relocate it.

    lda #>__TPA_START__
    ldx #__ZEROPAGE_START__
    jsr bios_RELOCATE

    ; Compute the entry address and jump.

    lda #<biosentry
    ldx #>biosentry
    jmp __TPA_START__ + COMHDR_ENTRY

loading_msg:
    .byte 13, 10, 10
    .ascii "CP/M-65 for the KIM-1"
    .byte 13, 10, 0

bdos_filename:
    .ascii "BDOS    SYS"

; Actual BIOS code.

; --- TTY driver ------------------------------------------------------------

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

.text

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

; Blocks and waits for the next keypress; returns it in A.

zproc tty_conin
    lda pending_key
    zif_eq
        sty ptr         ; Save Y
        lda SBD         ; Supress echo
        and #0xfe
        sta SBD
        jsr GETCH
        pha
        lda SBD         ; Restore echo
        ora #1
        sta SBD
        pla
        ldy ptr         ; Restore Y
    zendif
    ldx #0
    stx pending_key

    cmp #20         ; DEL
    zif_eq
        lda #8
    zendif

    clc
    rts
zendproc

zproc tty_conout
    sty ptr             ; Save Y
    cmp #'\n'
    zif_eq
        pha
        lda #'\r'
        jsr OUTCH
        pla
    zendif
    jsr OUTCH
    ldy ptr             ; Restore Y
    clc
    rts
zendproc

zproc tty_const
    lda pending_key
    zif_eq
        jsr tty_nbgetch
        sta pending_key
        zif_eq
            clc
            rts
        zendif
    zendif

    lda #$ff
    clc
    rts
zendproc

; Non-blocking tty read. If there is a char ready,
; put it into A. Otherwise, return 0x00. Adapted
; from the KIM-1 ROM

zproc tty_nbgetch
    stx ptr+0           ; Save XY
    sty ptr+1
    ldx #8              ; Set up 8 bit count
    lda #1
    bit SAD             ; Check start bit
    bne 1f 
    bmi 1f              ; No start bit
    jsr DELAY           ; Delay 1 bit
    jsr DEHALF          ; Delay 1/2 bit time
    zloop               ; Get 8 bits loop
        lda SAD
        and #0x80       ; Mask off low order bits
        lsr CHAR        ; Shift bit into CHAR
        ora CHAR
        sta CHAR
        jsr DELAY
        dex
    zuntil_eq  
    jsr DEHALF
    lda CHAR
    rol a               ; Shift off parity
    lsr a
    bne 2f
1:  lda #0
2:  ldx ptr+0           ; Restore XY
    ldy ptr+1
    rts
zendproc

; --- BIOS entrypoints ------------------------------------------------------

zproc bios_GETTPA
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc bios_SETTPA
    sta mem_base
    stx mem_end
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
    rts
zendproc


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
    cmp #4
    zif_cc
        sta current_drive
        tay
        lda dph_lo, y
        ldx dph_hi, y
    zendif
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

zproc bios_SETSEC
    sta ptr+0
    stx ptr+1

    ; Copy bottom 16 of sector number to temporary (the top byte must be 0).

    ldy #0
    lda (ptr), y
    sta ptr1+0
    iny
    lda (ptr), y
    sta ptr1+1

    ; There are 52 CP/M sectors per host track (each 256 byte host sector
    ; contains two CP/M sects). Do a 16-bit divide.

    ldx #16
    lda #0
    zrepeat
        asl ptr1+0
        rol ptr1+1
        rol a
        cmp #52
        zif_cs
            sbc #52
            inc ptr1+0
        zendif
        dex
    zuntil_eq
    sta requested_cpm_sector

    lda ptr1+0
    sta requested_track
    rts
zendproc

zproc bios_READ
    jsr change_sector
    zif_cs
        rts
    zendif

    ; transfer data from FDC into disk buffer

    lda requested_cpm_sector  
    lsr a                           ; Divide by 2 to get the host sector
    cmp buffered_host_sector
    zif_ne
        sta buffered_host_sector
        ldx requested_track
        ldy current_drive
        jsr fdc_exec_read
        zif_cs
            ; Some kind of read error. The data in the buffer is corrupt.

            lda #0xff
            sta buffered_host_sector

            sec
            rts
        zendif
    zendif

    ; Calculate offset in DISK_BUFFER

    lda requested_cpm_sector
    lsr a                       ; Push even/odd bit into C
    and #0                      ; Clear A
    ror a                       ; Shift C into bit 7 (results in 0x00 or 0x80)
    sta __read_buf_offset

    ldy #0
    zrepeat
__read_buf_offset = . + 1
        lda DISK_BUFFER, y
        sta (dma), y
        iny
        cpy #0x80
    zuntil_eq
    clc
    rts
zendproc

zproc bios_WRITE
    pha
    jsr change_sector
    pla

    zif_cc
        pha

        ; Calculate offset in DISK_BUFFER

        lda requested_cpm_sector
        lsr a                       ; Divide by 2 and push even/odd bit into C
        sta buffered_host_sector
        and #0                      ; Clear A
        ror a                       ; Shift C into bit 7 (results in 0x00 or 0x80)
        sta __write_buf_offset

        ldy #0
        zrepeat
            lda (dma), y
__write_buf_offset = . + 1
            sta DISK_BUFFER, y
            iny
            cpy #0x80
        zuntil_eq

        lda #0x80
        sta buffer_dirty

        clc
        pla
        zif_ne
            jsr flush_buffer
        zendif
    zendif
    rts
zendproc

; --- Disk access -----------------------------------------------------------

zproc change_sector
    lda requested_cpm_sector
    lsr a                           ; Divide by 2 to get the host sector
    cmp buffered_host_sector
    zif_eq
        lda requested_track
        cmp buffered_track
        zif_eq
            lda current_drive
            cmp buffered_drive
                ; Buffered disk/track/sector not changing, so do no work.

                clc
                rts
        zendif
    zendif

    bit buffer_dirty
    zif_mi
        jsr flush_buffer
        zif_cs
            rts
        zendif
    zendif

    lda requested_track
    sta buffered_track
    lda #0xff
    sta buffered_host_sector
    ldy current_drive
    sty buffered_drive

    ; Seek track (Seek track is cheap if the controller is already there)

    jsr fdc_exec_seek
    zif_cs
        ; Seek error. Invalidate buffered track

        lda #0xff
        sta buffered_track
    zendif

    rts
zendproc

zproc flush_buffer

    lda buffered_host_sector
    ldx buffered_track
    ldy buffered_drive

    jsr fdc_exec_write
    zif_cc
        ; A successful write, so mark the buffer as clean.

        lda #0
        sta buffer_dirty
    zendif

    rts
zendproc

; --- K-1013 command functions----------------------------------------------------

; Seek track in A, drive in Y

zproc fdc_exec_seek

    ; Save cylinder for later check

    pha

    ; Put new cylinder number into third byte of seek command

    sta fdc_seek+3
    sty fdc_seek+2              ; Put drive in second byte of command

    ldx #fdc_seek-fdc_commands  ; Command index into X
    jsr fdc_exec_command
    zif_cs
        rts
    zendif

    ; Wait until FDC interrupt

1:  lda HSRC
    bmi 1b

    ; Execute Sense Interrupt command

    ldx #fdc_senseint-fdc_commands
    jsr fdc_exec_command
    zif_cs
        rts
    zendif

    ; Read results into memory

    jsr fdc_read_result
    zif_cs
        rts
    zendif

    ; Compare cylinder number with desired one in ST1

    pla
    cmp disk_status+1
    bne 2f

    ; Look for error in the status registers

    lda disk_status     ; Check ST0
    and #0xf8           ; Delete don't care bits
    cmp #0x20           ; Result must be "Seek Completed"
    bne fdc_fail

    clc
    rts

zendproc

zproc fdc_fail
    sec
    rts
zendproc

; Sector num in A, cylinder in X, drive in Y

zproc fdc_exec_rw

    stx fdc_rw+3        ; Put cylinder in third byte of command
    sta fdc_rw+5        ; Put sector in fifth byte of command
    sta fdc_rw+7        ; Put last sector in seventh byte of command
    sty fdc_rw+2        ; Put drive in second byte of command

    ; Encode read/write buffer address into the DMA address register
    ; DISK_BUFFER is in the higher half of the FDC system RAM, at page 0xfe
    ; Bit 7 and 6: 11  ->  Upper half of system RAM, sys. RAM starts in even boundary
    ; Bits 5-0: Bits 11-6 of the buffer address

    lda #$f8
    sta ADMA

    ; Read/Write data into/from disk buffer

    ldx #fdc_rw-fdc_commands ; Command index into X
    jsr fdc_exec_command
    zif_cs
        rts
    zendif

    ; Wait until IRQ from FDC

1:  lda HSRC            ; Wait until IRQ from FDC
    bmi 1b
    
    ; Read results into memory

    jsr fdc_read_result
    zif_cs
        rts
    zendif   

    ; Look for error in the status registers

    lda disk_status     ; Check ST0
    and #0xd8           ; Delete don't care bits
    beq 2f              ; Jump ahead if ST0 clear
    cmp #0x40           ; Test if abnormal termination
    bne fdc_fail        ; Real error if not
    lda disk_status+1   ; If abnormal termination, check ST1 for end of cylinder
    bpl fdc_fail        ; Nope, then it is an error
2:  lda disk_status+1   ; Check ST1
    and #0x35           ; Mask out non-error bits
    bne fdc_fail        ; Error if any remainder set
    lda disk_status+2   ; Check ST2
    and #0x33           ; Mask out non-error bits
    bne fdc_fail        ; Error if any remainder set

    clc
    rts

zendproc

; Sector num in A, cylinder in X, drive in Y

zproc fdc_exec_read
    pha

    ; Put READ DATA command code into command byte

    lda #$46            ; Read, no multitrack, MFM, don't skip deleted
    sta fdc_rw+1

    ; Set FDC DMA write mode

    lda #1
    sta HSRC

    pla

    jmp fdc_exec_rw
zendproc

; Sector num in A, cylinder in X, drive in Y

zproc fdc_exec_write
    pha

    ; Put READ DATA command code into command byte

    lda #$45            ; Write, no multitrack, MFM, don't skip deleted
    sta fdc_rw+1

    ; Set FDC DMA read mode

    lda #0
    sta HSRC

    pla

    jmp fdc_exec_rw
zendproc

; Command index in X

zproc fdc_exec_command
    lda MSTR            ; Load Main Status Register
    and #0x10           ; Check if busy
    bne fail

    ldy fdc_commands, x ; Load command length
    inx

    zloop
1:      lda MSTR            ; Load Main Status Register again
        bpl 1b              ; Wait until RQM from controller
        and #0x40           ; Test data direction bit
        bne fail            ; Error if controller wants to talk

        lda fdc_commands, x ; Get command byte
        sta DATR            ; Store into FDC data register
        inx                 ; Next command byte
        dey
    zuntil_eq

    clc
    rts
zendproc

zproc fdc_read_result
    ldx #0
    zloop
1:      lda MSTR            ; Load Main Status Register again
        bpl 1b              ; Wait until RQM from controller
        and #0x40           ; Test data direction bit
        beq fail            ; Error if controller wants to listen

        lda DATR            ; Get status byte from data register
        sta disk_status, x  ; Put it into memory
        inx                 ; Next byte
        nop                 ; Give the controller time to update
        nop                 ; the MSTR with a valid busy status
        lda #0x10           ; Check if busy and go get another
        and MSTR            ; byte while so
    zuntil_eq

    clc
    rts
zendproc

zproc fail
    sec
    rts
zendproc

; --- Data ------------------------------------------------------------------

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA_START__@mos16hi
mem_end:    .byte __TPA_END__@mos16hi

; NEC-765 pre-formatted command strings

fdc_commands:
fdc_senseint:
    .byte 1             ; Command length
    .byte 8             ; Sense Interrupt Status

fdc_seek:
    .byte 3             ; Command length
    .byte 0xf           ; Command code
    .byte 0             ; Drive number in bits 0-1, side number in bit 2
    .byte 0             ; NCN: New cylinder number

fdc_rw:
    .byte 9             ; Command length
    .byte 0             ; Read or write command code. Updated by function
    .byte 0             ; Drive number in bits 0-1, side number in bit 2
    .byte 0             ; C: Present cylinder number. Must match current track
    .byte 0             ; H: Head
    .byte 0             ; R: Sector number to read
    .byte 1             ; N: Code for 256 bytes per sector
    .byte 0             ; EOT: Last sector to read
    .byte 0xe           ; GPL: Gap length for 26 sectors, 256 bytes/sect
    .byte 0xff          ; DTL: Data length = 0xff since N is non-zero

; DPH for drives 0-3

dph_lo:
    .byte dph0@mos16lo
    .byte dph1@mos16lo
    .byte dph2@mos16lo
    .byte dph3@mos16lo
dph_hi:
    .byte dph0@mos16hi
    .byte dph1@mos16hi
    .byte dph2@mos16hi
    .byte dph3@mos16hi

define_drive dph0, 77*52, 2048, 128, 52
define_drive dph1, 77*52, 2048, 128, 52
define_drive dph2, 77*52, 2048, 128, 52
define_drive dph3, 77*52, 2048, 128, 52

.bss

; Keep directory_buffer here! Must be page-aligned.

directory_buffer:       .fill 128   ; used by the BDOS

.global directory_buffer

pending_key:            .byte 0
disk_status:            .fill 8     ; Result phase readouts from NEC-765
current_drive:          .fill 1     ; Current selected disk drive number
requested_cpm_sector:   .fill 1     ; CP/M sector requested by user
requested_track:        .fill 1     ; track requested by user
buffered_drive:         .fill 1     ; Drive of track/sector in buffer
buffered_host_sector:   .fill 1     ; host sector in buffer
buffered_track:         .fill 1     ; track in buffer
buffer_dirty:           .fill 1     ; top bit set if the buffer was modified
