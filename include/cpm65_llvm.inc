; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

.macro ZEROPAGE
    .section .zp, "zax", @nobits
.endm

#define FCB_DR 0x00
#define FCB_F1 0x01
#define FCB_F2 0x02
#define FCB_F3 0x03
#define FCB_F4 0x04
#define FCB_F5 0x05
#define FCB_F6 0x06
#define FCB_F7 0x07
#define FCB_F8 0x08
#define FCB_T1 0x09
#define FCB_T2 0x0a
#define FCB_T3 0x0b
#define FCB_EX 0x0c
#define FCB_S1 0x0d
#define FCB_S2 0x0e
#define FCB_RC 0x0f
#define FCB_AL 0x10
#define FCB_CR 0x20
#define FCB_R0 0x21
#define FCB_R1 0x22
#define FCB_R2 0x23
#define XFCB_US 0x24
#define XFCB__SIZE 0x25

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
#define BDOS_GET_BIOS 38
#define BDOS_WRITE_RANDOM_FILLED 40

; vim: filetype=asm sw=4 ts=4 et

