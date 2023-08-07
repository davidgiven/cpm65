; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

/* FCB layout (and XFCB). */

FCB_DR = $00
FCB_F1 = $01
FCB_F2 = $02
FCB_F3 = $03
FCB_F4 = $04
FCB_F5 = $05
FCB_F6 = $06
FCB_F7 = $07
FCB_F8 = $08
FCB_T1 = $09
FCB_T2 = $0a
FCB_T3 = $0b
FCB_EX = $0c
FCB_S1 = $0d
FCB_S2 = $0e
FCB_RC = $0f
FCB_AL = $10
FCB_CR = $20
FCB_R0 = $21
FCB_R1 = $22
FCB_R2 = $23
FCB__SIZE = $24
XFCB_US = $24
XFCB__SIZE = $25

/* BDOS entrypoints. */

/* These are the same as CP/M 2.2. */

BDOS_EXIT_PROGRAM = 0
BDOS_CONSOLE_INPUT = 1
BDOS_CONSOLE_OUTPUT = 2
BDOS_AUX_INPUT = 3
BDOS_AUX_OUTPUT = 4
BDOS_PRINTER_OUTPUT = 5
BDOS_DIRECT_IO = 6
BDOS_GET_IO_BYTE = 7
BDOS_SET_IO_BYTE = 8
BDOS_WRITE_STRING = 9
BDOS_READ_LINE = 10
BDOS_CONSOLE_STATUS = 11
BDOS_GET_VERSION = 12
BDOS_RESET_DISKS = 13
BDOS_SELECT_DISK = 14
BDOS_OPEN_FILE = 15
BDOS_CLOSE_FILE = 16
BDOS_FIND_FIRST = 17
BDOS_FIND_NEXT = 18
BDOS_DELETE_FILE = 19
BDOS_READ_SEQUENTIAL = 20
BDOS_WRITE_SEQUENTIAL = 21
BDOS_CREATE_FILE = 22
BDOS_RENAME_FILE = 23
BDOS_GET_LOGIN_BITMAP = 24
BDOS_GET_CURRENT_DRIVE = 25
BDOS_SET_DMA_ADDRESS = 26
BDOS_GET_ALLOCATION_BITMAP = 27
BDOS_SET_DRIVE_READONLY = 28
BDOS_GET_READONLY_BITMAP = 29
BDOS_SET_FILE_ATTRIBUTES = 30
BDOS_GET_DPB = 31
BDOS_GET_SET_USER_NUMBER = 32
BDOS_READ_RANDOM = 33
BDOS_WRITE_RANDOM = 34
BDOS_COMPUTE_FILE_SIZE = 35
BDOS_COMPUTE_RANDOM_POINTER = 36
BDOS_RESET_DISK = 37
BDOS_GET_BIOS = 38                /* <-- custom */
BDOS_WRITE_RANDOM_FILLED = 40

/* These are custom extensions. */

BDOS_GETZP = 41       /* forwards to BIOS */
BDOS_GETTPA = 42      /* forwards to BIOS */

/* DMA points at an FCB structure; the filename pointed to by XA is parsed
 * into it. The updated XA pointing to the end of the filename is returned.
 * If the filename is invalid, C is set on return (but CP/M filenames are
 * so vague that the only real time when this can happen is if the drive
 * letter is wrong).
 */

BDOS_PARSEFILENAME = 43

/* Error codes returned by various BDOS entrypoints. */

CPME_OK = $00 /* success (usually) */
CPME_NODATA = $01 /* or EOF */
CPME_DISKFULL = $02 /* no free blocks on disk */
CPME_CANTCLOSE = $03 /* can't write extent back to disk */
CPME_NOEXTENT = $04 /* only on random access reads */
CPME_DIRFULL = $05 /* no free dirents on disk */
CPME_BADFCB = $09 /* FCB couldn't be parsed */
CPME_FAILED = $ff /* general purpose failure code */

/* BIOS entrypoints. */

BIOS_CONST = 0 /* get console status */
BIOS_CONIN = 1 /* blocking read character */
BIOS_CONOUT = 2 /* blocking write character */
BIOS_SELDSK = 3 /* select disk and return DPH pointer */
BIOS_SETSEC = 4 /* set sector; XA is pointer to 24-bit int */
BIOS_SETDMA = 5 /* set DMA address */
BIOS_READ = 6 /* read sector */
BIOS_WRITE = 7 /* write sector: A=0 for normal, 1 for directory, 2 to suppress read */
BIOS_RELOCATE = 8 /* relocates a binary: A=TPA page, X=ZP base */
BIOS_GETTPA = 9 /* gets TPA bounds: A=lo, X=hi */
BIOS_SETTPA = 10 /* sets TPA bounds: A=lo, X=hi */
BIOS_GETZP = 11 /* gets ZP bounds: A=lo, X=hi */
BIOS_SETZP = 12 /* sets ZP bounds: A=lo, X=hi */
BIOS_SETBANK = 13 /* sets current memory bank */
BIOS_ADDDRV = 14 /* entry: XA=new driver */
BIOS_FINDDRV = 15 /* entry: XA=driver ID; exit: XA=driver strategy routine */

/* Memory banks. */

BANK_MAIN = 0   /* normal bank */
BANK_EXTRA = 1   /* used for the BDOS and CCP */

/* DPH structure layout. */

DPH_XLT = 0   /* unused in CP/M-65 */
DPH_CDRMAX = 2   /* number of used dirents */
DPH_SCRATCH1 = 4   /* unused in CP/M-65 */
DPH_SCRATCH2 = 6   /* unused in CP/M-65 */
DPH_DIRBUF = 8   /* pointer to 128-byte directory buffer */
DPH_DPB = 10  /* pointer to DPB for this drive */
DPH_CSV = 12  /* pointer to checksum vector */
DPH_ALV = 14  /* pointer to allocation vector */

DPB_SPT = 0   /* unused in CP/M-65 */
DPB_BSH = 2   /* block shift */
DPB_BLM = 3   /* block mask */
DPB_EXM = 4   /* extent mask */
DPB_DSM = 5   /* blocks on disk minus one */
DPB_DRM = 7   /* number of directory entries minus one */
DPB_AL = 9   /* allocation bitmap */
DPB_CKS = 11  /* checksum vector size */
DPB_OFF = 13  /* number of reserved sectors */

; vim: filetype=asm sw=4 ts=4 et

