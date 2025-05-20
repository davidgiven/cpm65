; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

.macro ZEROPAGE
    .section .zp, "zax", @nobits
.endm

.macro NOINIT
    .section .noinit, "ax", @nobits
.endm

/* Layout of the CP/M-65 relocatable header. */

#define COMHDR_ZP_USAGE   0 /* bytes of zero page used */
#define COMHDR_TPA_USAGE  1 /* pages of TPA required (including space for relocation) */
#define COMHDR_REL_OFFSET 2 /* relative address of relocation data (and start of BSS) */
#define COMHDR_BDOS_JMP   4 /* jump instruction for calling BDOS: $4c for the 6502 */
#define COMHDR_BDOS       5 /* BDOS entrypoint address */
#define COMHDR_ENTRY      7 /* program entrypoint */

/* FCB layout (and XFCB). */

#define FCB_DR     0x00
#define FCB_F1     0x01
#define FCB_F2     0x02
#define FCB_F3     0x03
#define FCB_F4     0x04
#define FCB_F5     0x05
#define FCB_F6     0x06
#define FCB_F7     0x07
#define FCB_F8     0x08
#define FCB_T1     0x09
#define FCB_T2     0x0a
#define FCB_T3     0x0b
#define FCB_EX     0x0c
#define FCB_S1     0x0d
#define FCB_S2     0x0e
#define FCB_RC     0x0f
#define FCB_AL     0x10
#define FCB_CR     0x20
#define FCB_R0     0x21
#define FCB_R1     0x22
#define FCB_R2     0x23
#define FCB__SIZE  0x24
#define XFCB_US    0x24
#define XFCB__SIZE 0x25

/* BDOS entrypoints. */

/* These are the same as CP/M 2.2. */

#define BDOS_EXIT_PROGRAM 0
#define BDOS_CONSOLE_INPUT 1
#define BDOS_CONSOLE_OUTPUT 2
#define BDOS_AUX_INPUT 3
#define BDOS_AUX_OUTPUT 4
#define BDOS_PRINTER_OUTPUT 5
#define BDOS_DIRECT_IO 6
#define BDOS_GET_IO_BYTE 7
#define BDOS_SET_IO_BYTE 8
#define BDOS_WRITE_STRING 9
#define BDOS_READ_LINE 10
#define BDOS_CONSOLE_STATUS 11
#define BDOS_GET_VERSION 12
#define BDOS_RESET_DISKS 13
#define BDOS_SELECT_DISK 14
#define BDOS_OPEN_FILE 15
#define BDOS_CLOSE_FILE 16
#define BDOS_FIND_FIRST 17
#define BDOS_FIND_NEXT 18
#define BDOS_DELETE_FILE 19
#define BDOS_READ_SEQUENTIAL 20
#define BDOS_WRITE_SEQUENTIAL 21
#define BDOS_CREATE_FILE 22
#define BDOS_RENAME_FILE 23
#define BDOS_GET_LOGIN_BITMAP 24
#define BDOS_GET_CURRENT_DRIVE 25
#define BDOS_SET_DMA_ADDRESS 26
#define BDOS_GET_ALLOCATION_BITMAP 27
#define BDOS_SET_DRIVE_READONLY 28
#define BDOS_GET_READONLY_BITMAP 29
#define BDOS_SET_FILE_ATTRIBUTES 30
#define BDOS_GET_DPB 31
#define BDOS_GET_SET_USER_NUMBER 32
#define BDOS_READ_RANDOM 33
#define BDOS_WRITE_RANDOM 34
#define BDOS_COMPUTE_FILE_SIZE 35
#define BDOS_COMPUTE_RANDOM_POINTER 36
#define BDOS_RESET_DISK 37
#define BDOS_GET_BIOS 38                /* <-- custom */
#define BDOS_WRITE_RANDOM_FILLED 40

/* These are custom extensions. */

#define BDOS_GETZP 41       /* forwards to BIOS */
#define BDOS_GETTPA 42      /* forwards to BIOS */

/* DMA points at an FCB structure; the filename pointed to by XA is parsed
 * into it. The updated XA pointing to the end of the filename is returned.
 * If the filename is invalid, C is set on return (but CP/M filenames are
 * so vague that the only real time when this can happen is if the drive
 * letter is wrong).
 */

#define BDOS_PARSEFILENAME 43

/* Error codes returned by various BDOS entrypoints. */

#define CPME_OK        $00 /* success (usually) */
#define CPME_NODATA    $01 /* or EOF */
#define CPME_DISKFULL  $02 /* no free blocks on disk */
#define CPME_CANTCLOSE $03 /* can't write extent back to disk */
#define CPME_NOEXTENT  $04 /* only on random access reads */
#define CPME_DIRFULL   $05 /* no free dirents on disk */
#define CPME_BADFCB    $09 /* FCB couldn't be parsed */
#define CPME_FAILED    $ff /* general purpose failure code */

/* BIOS entrypoints. */

#define BIOS_CONST     0 /* get console status */
#define BIOS_CONIN     1 /* blocking read character */
#define BIOS_CONOUT    2 /* blocking write character */
#define BIOS_SELDSK    3 /* select disk and return DPH pointer */
#define BIOS_SETSEC    4 /* set sector; XA is pointer to 24-bit int */
#define BIOS_SETDMA    5 /* set DMA address */
#define BIOS_READ      6 /* read sector */
#define BIOS_WRITE     7 /* write sector: A=0 for normal, 1 for directory, 2 to suppress read */
#define BIOS_RELOCATE  8 /* relocates a binary: A=TPA page, X=ZP base */
#define BIOS_GETTPA    9 /* gets TPA bounds: A=lo, X=hi */
#define BIOS_SETTPA   10 /* sets TPA bounds: A=lo, X=hi */
#define BIOS_GETZP    11 /* gets ZP bounds: A=lo, X=hi */
#define BIOS_SETZP    12 /* sets ZP bounds: A=lo, X=hi */
#define BIOS_SETBANK  13 /* sets current memory bank */
#define BIOS_ADDDRV   14 /* entry: XA=new driver */
#define BIOS_FINDDRV  15 /* entry: XA=driver ID; exit: XA=driver strategy routine */

/* Memory banks. */

#define BANK_MAIN    0   /* normal bank */
#define BANK_EXTRA   1   /* used for the BDOS and CCP */

/* DPH structure layout. */

#define DPH_XLT      0   /* unused in CP/M-65 */
#define DPH_CDRMAX   2   /* number of used dirents */
#define DPH_SCRATCH1 4   /* unused in CP/M-65 */
#define DPH_SCRATCH2 6   /* unused in CP/M-65 */
#define DPH_DIRBUF   8   /* pointer to 128-byte directory buffer */
#define DPH_DPB      10  /* pointer to DPB for this drive */
#define DPH_CSV      12  /* pointer to checksum vector */
#define DPH_ALV      14  /* pointer to allocation vector */

#define DPB_SPT      0   /* unused in CP/M-65 */
#define DPB_BSH      2   /* block shift */
#define DPB_BLM      3   /* block mask */
#define DPB_EXM      4   /* extent mask */
#define DPB_DSM      5   /* blocks on disk minus one */
#define DPB_DRM      7   /* number of directory entries minus one */
#define DPB_AL       9   /* allocation bitmap */
#define DPB_CKS      11  /* checksum vector size */
#define DPB_OFF      13  /* number of reserved sectors */

.macro define_dpb name, sectors, blocksize, dirents, reserved
    .if \blocksize == 1024
        block_shift = 3
    .elseif \blocksize == 2048
        block_shift = 4
    .elseif \blocksize == 4096
        block_shift = 5
    .elseif \blocksize == 8192
        block_shift = 6
    .elseif \blocksize == 16384
        block_shift = 7
    .else
        .error "Invalid block size!"
    .endif

    checksum_buffer_size = (\dirents+3) / 4
    blocks_on_disk = \sectors * 128 / \blocksize
    allocation_vector_size = (blocks_on_disk + 7) / 8
    directory_blocks = (\dirents * 32) / \blocksize
    allocation_bitmap = ($ffff << (16 - directory_blocks)) & $ffff

    .if directory_blocks == 0
        .error "Directory must be at least one block in size!"
    .endif
    .if ((\dirents * 32) % \blocksize) != 0
        .error "Directory is not an even number of blocks in size!"
    .endif

    .if blocks_on_disk < 256
        .if \blocksize == 1024
            extent_mask = 0x00 ; %00000000
        .elseif \blocksize == 2048
            extent_mask = 0x01 ; %00000001
        .elseif \blocksize == 4096
            extent_mask = 0x03 ; %00000011
        .elseif \blocksize == 8192
            extent_mask = 0x07 ; %00000111
        .elseif \blocksize == 16384
            extent_mask = 0x0f ; %00001111
        .endif
    .else
        .if \blocksize == 1024
            .fatal "Can't use a block size of 1024 on a large disk"
        .elseif \blocksize == 2048
            extent_mask = 0x00 ; %00000000
        .elseif \blocksize == 4096
            extent_mask = 0x01 ; %00000001
        .elseif \blocksize == 8192
            extent_mask = 0x03 ; %00000011
        .elseif \blocksize == 16384
            extent_mask = 0x07 ; %00000111
        .endif
    .endif

.data
\name:
    .word 0             ; unused
    .byte block_shift   ; block shift
    .byte (1<<block_shift)-1 ; block mask
    .byte extent_mask   ; extent mask
    .word blocks_on_disk - 1 ; number of blocks on the disk
    .word \dirents - 1  ; number of directory entries
    .byte allocation_bitmap >> 8
    .byte allocation_bitmap & 0xff
    .word checksum_buffer_size ; checksum vector size
    .word \reserved     ; number of reserved _sectors_ on disk

    checksum_buffer_size_\name = checksum_buffer_size
    allocation_vector_size_\name = allocation_vector_size
.endmacro

.macro define_dph name, dpb
.data
\name:
    .word 0, 0, 0, 0    ; CP/M workspace
    .word directory_buffer
    .word \dpb
    .word 1f
    .word 2f

NOINIT

1: .fill checksum_buffer_size_\dpb
2: .fill allocation_vector_size_\dpb

.endmacro

; vim: filetype=asm sw=4 ts=4 et

