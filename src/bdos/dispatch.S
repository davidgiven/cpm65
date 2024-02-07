; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "jumptables.inc"
#include "bdos.inc"

; BDOS entrypoint.

zproc ENTRY
    sta param+0
    stx param+1

    jsr internal_BEGINSYS

    jsr icall               ; preserve carry from this!
    jmp internal_ENDSYS

unimplemented:
    clc
    rts

icall:
    lda jumptable_hi, y
    pha
    lda jumptable_lo, y
    pha
    rts

jumptable_lo:
    jmptablo bdos_EXIT ; exit_program = 0
    jmptablo bdos_CONIN ; console_input = 1
    jmptablo bdos_CONOUT ; console_output = 2
    jmptablo unimplemented ; aux_input = 3 UNSUPPORTED
    jmptablo unimplemented ; aux_output = 4 UNSUPPORTED
    jmptablo unimplemented ; printer_output = 5 UNSUPPORTED
    jmptablo bdos_DIRECTIO ; direct_io = 6
    jmptablo bdos_GETIOBYTE ; get_io_byte = 7 UNSUPPORTED
    jmptablo unimplemented ; set_io_byte = 8 UNSUPPORTED
    jmptablo bdos_WRITESTRING ; write_string = 9
    jmptablo bdos_READLINE ; read_line = 10
    jmptablo bdos_GETCONSOLESTATUS ; console_status = 11
    jmptablo bdos_GETVERSION ; get_version = 12
    jmptablo bdos_RESET ; reset_disks = 13
    jmptablo bdos_LOGINDRIVE ; select_disk = 14
    jmptablo bdos_OPENFILE ; open_file = 15
    jmptablo bdos_CLOSEFILE ; close_file = 16
    jmptablo bdos_FINDFIRST ; find_first = 17
    jmptablo bdos_FINDNEXT ; find_next = 18
    jmptablo bdos_DELETEFILE ; delete_file = 19
    jmptablo bdos_READSEQUENTIAL ; read_sequential = 20
    jmptablo bdos_WRITESEQUENTIAL ; write_sequential = 21
    jmptablo bdos_CREATEFILE ; create_file = 22
    jmptablo bdos_RENAMEFILE ; rename_file = 23
    jmptablo bdos_GETLOGINBITMAP ; get_login_bitmap = 24
    jmptablo bdos_GETDRIVE ; get_current_drive = 25
    jmptablo bdos_SETDMAADDRESS ; set_dma_address = 26
    jmptablo bdos_GETALLOCATIONBITMAP ; get_allocation_bitmap = 27
    jmptablo bdos_SETDRIVEREADONLY ; set_drive_readonly = 28
    jmptablo bdos_GETREADONLYBITMAP ; get_readonly_bitmap = 29
    jmptablo bdos_SETFILEATTRS ; set_file_attributes = 30
    jmptablo bdos_GETDPB ; get_DPB = 31
    jmptablo bdos_GETSETUSER ; get_set_user_number = 32
    jmptablo bdos_READRANDOM ; read_random = 33
    jmptablo bdos_WRITERANDOM ; write_random = 34
    jmptablo bdos_COMPUTEFILESIZE ; compute_file_size = 35
    jmptablo bdos_COMPUTEPOINTER ; compute_random_pointer = 36
    jmptablo bdos_RESETDISK ; reset_disk = 37
    jmptablo bdos_GETBIOS ; get_bios = 38
    jmptablo unimplemented ; 39
    jmptablo bdos_WRITERANDOMFILLED ; write_random_filled = 40
    jmptablo bios_GETZP ; get_zp = 41
    jmptablo bios_GETTPA ; get_tpa = 42
    jmptablo bdos_PARSEFCB ; 43
jumptable_hi:
    jmptabhi bdos_EXIT ;exit_program = 0
    jmptabhi bdos_CONIN ; console_input = 1
    jmptabhi bdos_CONOUT ; console_output = 2
    jmptabhi unimplemented ; aux_input = 3 UNSUPPORTED
    jmptabhi unimplemented ; aux_output = 4 UNSUPPORTED
    jmptabhi unimplemented ; printer_output = 5 UNSUPPORTED
    jmptabhi bdos_DIRECTIO ; direct_console_io = 6
    jmptabhi bdos_GETIOBYTE ; get_io_byte = 7 UNSUPPORTED
    jmptabhi unimplemented ; set_io_byte = 8 UNSUPPORTED
    jmptabhi bdos_WRITESTRING ; write_string = 9
    jmptabhi bdos_READLINE ; read_line = 10
    jmptabhi bdos_GETCONSOLESTATUS ; console_status = 11
    jmptabhi bdos_GETVERSION ; get_version = 12
    jmptabhi bdos_RESET ; reset_disks = 13
    jmptabhi bdos_LOGINDRIVE ; select_disk = 14
    jmptabhi bdos_OPENFILE ; open_file = 15
    jmptabhi bdos_CLOSEFILE ; close_file = 16
    jmptabhi bdos_FINDFIRST ; find_first = 17
    jmptabhi bdos_FINDNEXT ; find_next = 18
    jmptabhi bdos_DELETEFILE ; delete_file = 19
    jmptabhi bdos_READSEQUENTIAL ; read_sequential = 20
    jmptabhi bdos_WRITESEQUENTIAL ; write_sequential = 21
    jmptabhi bdos_CREATEFILE ; create_file = 22
    jmptabhi bdos_RENAMEFILE ; rename_file = 23
    jmptabhi bdos_GETLOGINBITMAP ; get_login_bitmap = 24
    jmptabhi bdos_GETDRIVE ; get_current_drive = 25
    jmptabhi bdos_SETDMAADDRESS ; set_dma_address = 26
    jmptabhi bdos_GETALLOCATIONBITMAP ; get_allocation_bitmap = 27
    jmptabhi bdos_SETDRIVEREADONLY ; set_drive_readonly = 28
    jmptabhi bdos_GETREADONLYBITMAP ; get_readonly_bitmap = 29
    jmptabhi bdos_SETFILEATTRS ; set_file_attributes = 30
    jmptabhi bdos_GETDPB ; get_dpb = 31
    jmptabhi bdos_GETSETUSER ; get_set_user_number = 32
    jmptabhi bdos_READRANDOM ; read_random = 33
    jmptabhi bdos_WRITERANDOM ; write_random = 34
    jmptabhi bdos_COMPUTEFILESIZE ; compute_file_size = 35
    jmptabhi bdos_COMPUTEPOINTER ; compute_random_pointer = 36
    jmptabhi bdos_RESETDISK ; reset_disk = 37
    jmptabhi bdos_GETBIOS ; 38
    jmptabhi unimplemented ; 39
    jmptabhi bdos_WRITERANDOMFILLED ; write_random_filled = 40
    jmptabhi bios_GETZP ; get_zp = 41
    jmptabhi bios_GETTPA ; get_tpa = 42
    jmptabhi bdos_PARSEFCB ; 43
zendproc

