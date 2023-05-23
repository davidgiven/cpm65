\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.bss pblock, 165
cpm_fcb = pblock
cpm_fcb2 = pblock + 16
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
BDOS_GETZP             = 41
BDOS_GETTPA            = 42
BDOS_PARSE_FILENAME    = 43

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

FCB_DR = 0x00
FCB_F1 = 0x01
FCB_F2 = 0x02
FCB_F3 = 0x03
FCB_F4 = 0x04
FCB_F5 = 0x05
FCB_F6 = 0x06
FCB_F7 = 0x07
FCB_F8 = 0x08
FCB_T1 = 0x09
FCB_T2 = 0x0a
FCB_T3 = 0x0b
FCB_EX = 0x0c
FCB_S1 = 0x0d
FCB_S2 = 0x0e
FCB_RC = 0x0f
FCB_AL = 0x10
FCB_CR = 0x20
FCB_R0 = 0x21
FCB_R1 = 0x22
FCB_R2 = 0x23
FCB_SIZE = 0x24

DPB_BSH     = 2
DPB_EXM     = 4
DPB_DSM     = 5
DPB_DRM     = 7
DPB_CKS     = 11
DPB_OFF     = 13

BDOS = start-3

\ vim: filetype=asm sw=4 ts=4 et


