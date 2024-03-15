#include "cpm65.inc"
#include "zif.inc"

.macro bdos name, func
    zproc \name
        ldy #\func
        jmp BDOS
    zendproc
.endm

.macro bios name, func
    zproc \name
        ldy #\func
        jmp BIOS
    zendproc
.endm

bdos bdos_EXIT,            BDOS_EXIT_PROGRAM
bdos bdos_SET_DMA_ADDRESS, BDOS_SET_DMA_ADDRESS
bdos bdos_CONIN,           BDOS_CONSOLE_INPUT
bdos bdos_CONOUT,          BDOS_CONSOLE_OUTPUT
bdos bdos_WRITESTRING,     BDOS_WRITE_STRING
bdos bdos_READLINE,        BDOS_READ_LINE
bdos bdos_SELECTDISK,      BDOS_SELECT_DISK
bdos bdos_FINDFIRST,       BDOS_FIND_FIRST
bdos bdos_FINDNEXT,        BDOS_FIND_NEXT
bdos bdos_GETSETUSER,      BDOS_GET_SET_USER_NUMBER
bdos bdos_GETDRIVE,        BDOS_GET_CURRENT_DRIVE
bdos bdos_GETBIOS,         BDOS_GET_BIOS
bdos bdos_RENAME,          BDOS_RENAME_FILE
bdos bdos_READ_SEQUENTIAL, BDOS_READ_SEQUENTIAL
bdos bdos_GETTPA,          BDOS_GETTPA
bdos bdos_OPEN_FILE,       BDOS_OPEN_FILE

bios bios_SETBANK,     BIOS_SETBANK
bios bios_GETTPA,      BIOS_GETTPA
bios bios_GETZP,       BIOS_GETZP
bios bios_RELOCATE,    BIOS_RELOCATE

; vim: sw=4 ts=4 et ft=asm

