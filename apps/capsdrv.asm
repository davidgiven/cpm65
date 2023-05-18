\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.bss pblock, 165
cpm_fcb = pblock
cpm_default_dma = pblock + 0x25

BDOS_WARMBOOT          =  0
BDOS_CONIN             =  1
BDOS_CONOUT            =  2
BDOS_AUXIN             =  3
BDOS_AUXOUT            =  4
BDOS_LSTOUT            =  5
BDOS_CONIO             =  6
BDOS_GET_IOBYTE        =  7
BDOS_SET_IOBYTE        =  8
BDOS_PRINTSTRING       =  9
BDOS_READLINE          = 10
BDOS_CONST             = 11
BDOS_GET_VERSION       = 12
BDOS_RESET_DISK_SYSTEM = 13
BDOS_SELECT_DRIVE      = 14
BDOS_OPEN_FILE         = 15
BDOS_CLOSE_FILE        = 16
BDOS_FINDFIRST         = 17
BDOS_FINDNEXT          = 18
BDOS_DELETE_FILE       = 19
BDOS_READ_SEQUENTIAL   = 20
BDOS_WRITE_SEQUENTIAL  = 21
BDOS_MAKE_FILE         = 22
BDOS_RENAME_FILE       = 23
BDOS_GET_LOGIN_VECTOR  = 24
BDOS_GET_CURRENT_DRIVE = 25
BDOS_SET_DMA           = 26
BDOS_GET_ALLOC_VECTOR  = 27
BDOS_WRITE_PROT_DRIVE  = 28
BDOS_GET_READONLY_VEC  = 29
BDOS_SET_FILE_ATTRS    = 30
BDOS_GET_DPB           = 31
BDOS_GET_SET_USER      = 32
BDOS_READ_RANDOM       = 33
BDOS_WRITE_RANDOM      = 34
BDOS_SEEK_TO_END       = 35
BDOS_SEEK_TO_SEQ_POS   = 36
BDOS_RESET_DRIVES      = 37
BDOS_GET_BIOS          = 38
BDOS_WRITE_RANDOM_FILL = 40
BDOS_GET_TPA           = 41
BDOS_GET_ZP            = 42

BIOS_CONST             = 0
BIOS_CONIN             = 1
BIOS_CONOUT            = 2
BIOS_SELDSK            = 3
BIOS_SETSEC            = 4
BIOS_SETDMA            = 5
BIOS_READ              = 6
BIOS_WRITE             = 7
BIOS_RELOCATE          = 8
BIOS_GETTPA            = 9
BIOS_SETTPA            = 10
BIOS_GETZP             = 11
BIOS_SETZP             = 12
BIOS_SETBANK           = 13
BIOS_ADDDRV            = 14
BIOS_FINDDRV           = 15

DRVID_TTY = 1

TTY_CONST = 0
TTY_CONIN = 1
TTY_CONOUT = 2

BDOS = start - 3
start:
.expand 1

.label entry
.label next

\ --- Resident part starts at the top of the file ---------------------------

.zproc main
    jmp entry
.zendproc

driver:
    .word DRVID_TTY
    .word strategy
    .word 0
    .byte "CapsTTY", 0

.zproc strategy
    cpy #TTY_CONOUT
    .zif eq
        cmp #'a'
        .zif cs
            cmp #'z'+1
            .zif cc
                and #0xdf
            .zendif
        .zendif
    .zendif
    jmp (next)
.zendproc

next: .word 0

\ --- Resident part stops here -------------------------------------------

.zproc entry
    lda #<banner
    ldx #>banner
    ldy #BDOS_PRINTSTRING
    jsr BDOS

    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    \ Find the old TTY driver strategy routine and save it.

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    .zif cc
        sta next+0
        stx next+1

        \ Register the new TTY driver.

        lda #<driver
        ldx #>driver
        ldy #BIOS_ADDDRV
        jsr BIOS
        .zif cc

            \ Our driver uses no ZP, so we don't need to adjust that. But it does use
            \ TPA.

            ldy #BIOS_GETTPA
            jsr BIOS
            clc
            adc #1 \ Allocate one page. We should be using entry to calculate this, but
                   \ the assembler can't do that yet.
            ldy #BIOS_SETTPA
            jsr BIOS

            \ Finished --- don't even need to warm boot.

            rts
        .zendif
    .zendif

    lda #<failed
    ldx #>failed
    ldy #BDOS_PRINTSTRING
    jmp BDOS
    
banner:
    .byte "Everything is in capital letters now", 13, 10, 0
failed:
    .byte "Failed!", 13, 10, 0
BIOS:
    jmp 0

\ vim: sw=4 ts=4 et


