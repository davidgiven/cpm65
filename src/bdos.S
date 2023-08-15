; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.


#include "cpm65.inc"
#include "zif.inc"
#include "jumptables.inc"

CPM_MACHINE_TYPE = $f ; 6502!
CPM_SYSTEM_TYPE = 0
CPM_VERSION = $22 ; CP/M 2.2 (compatible)

ZEROPAGE

current_dirent:   .word 0 ; current directory entry
param:            .word 0 ; current user input parameter
user_dma:         .word 0 ; current user DMA address
dph:              .word 0 ; currently selected DPH

directory_buffer: .word 0 ; directory buffer from the DPH
current_dpb:      .word 0 ; currently selected DPB
checksum_buffer:  .word 0 ; checksum buffer from the DPH
bitmap:           .word 0 ; allocation bitmap from the DPH

temp:             .fill 4 ; temporary storage
tempb:            .byte 0 ; more temporary storage

; --- Initialisation --------------------------------------------------------
; TODO: figure out how to discard this.

zproc main
    ; Store BIOS entrypoint pointer.

    sta bios+0
    stx bios+1

    ; Reset persistent state.

    lda #0
    sta current_user
    sta current_drive

    ; Update memory region.

    ldy #BIOS_SETBANK
    lda #BANK_EXTRA
    jsr callbios

    ldy #BIOS_GETZP
    jsr callbios
    clc
    adc cpm_header + COMHDR_ZP_USAGE
    ldy #BIOS_SETZP
    jsr callbios
    
    jsr bios_GETTPA
    clc
    adc cpm_header + COMHDR_TPA_USAGE
    ldy #BIOS_SETTPA
    jsr callbios
    jmp entry_EXIT
zendproc

; --- Warm start ------------------------------------------------------------

; Prints the message in XA and performs a warm boot.

harderror:
    jsr internal_WRITESTRING
    ; fall through
entry_EXIT:
    ldx #$ff                ; reset stack point
    txs

    jsr bios_NEWLINE
    jsr entry_RESET

    ; Open the CCP.SYS file.

    lda #0
    sta ccp_fcb + FCB_EX
    sta ccp_fcb + FCB_S2
    sta ccp_fcb + FCB_CR
    lda #1
    sta ccp_fcb + FCB_DR

    lda #<ccp_fcb
    sta param+0
    lda #>ccp_fcb
    sta param+1
    jsr entry_OPENFILE
    zif_cs
        lda #<1f
        ldx #>1f
        jsr internal_WRITESTRING
        jmp .
    1:
        .ascii "Couldn't open CCP"
        .byte 13, 10, 0
    zendif

    ; Read the first sector.

    lda directory_buffer+0
    sta user_dma+0
    lda directory_buffer+1
    sta user_dma+1
    jsr internal_READSEQUENTIAL ; load one record

    ; Compute the load address.

    ldy #BIOS_SETBANK
    lda #BANK_EXTRA
    jsr callbios

    jsr bios_GETZP          ; top of ZP in X
    txa
    sec
    ldy #COMHDR_ZP_USAGE
    sbc (directory_buffer), y
    pha
    
    jsr bios_GETTPA         ; top of TPA page number in X
    txa
    sec
    ldy #COMHDR_TPA_USAGE
    sbc (directory_buffer), y
    sta user_dma+1
    pha                     ; store load address for later
    lda #0
    sta user_dma+0

    ; Copy the first record into memory.

    jsr copy_directory_buffer_to_dma
    lda #$80
    sta user_dma+0

    ; Read the CCP into memory.

    zloop
        ; param remains set from above
        jsr internal_READSEQUENTIAL
        zbreakif_cs

        lda user_dma+0
        eor #$80
        sta user_dma+0
        zif_eq
            inc user_dma+1
        zendif
    zendloop

    ; Patch the BIOS entry vector.

    lda #0                  ; pop start address, saved earlier
    sta temp+0
    pla
    sta temp+1
    
    ldy #COMHDR_BDOS
    lda #<ENTRY
    sta (temp), y
    iny
    lda #>ENTRY
    sta (temp), y

    ; Relocate.

    pla                     ; pop start zero page address, saved earlier
    tax
    lda temp+1              ; start of TPA, in pages
    ldy #BIOS_RELOCATE
    jsr callbios

    ; Execute it.

    ldy #BIOS_SETBANK
    lda #BANK_MAIN
    jsr callbios

    lda #COMHDR_ENTRY      ; start address is 256-byte aligned
    sta temp+0
calltemp:
    jmp (temp)

    .data
ccp_fcb:
    .byte 1                 ; drive A:
    .ascii "CCP     SYS"    ; filename: CCP.SYS
    .byte 0, 0, 0, 0        ; EX, S1, S2, RC
    .fill 16, 1, 0          ; allocation block
    .byte 0                 ; CR

; --- BDOS entrypoint -------------------------------------------------------

zproc ENTRY
    sta param+0
    stx param+1

    lda #$ff
    sta old_fcb_drive       ; mark FCB as not fiddled with

    ; Reset per-system-call state

    lda #0
    sta block_needs_clearing

    jsr icall               ; preserve carry from this!
    php
    pha
    tya
    pha

    lda old_fcb_drive
    zif_pl
        ldy #FCB_DR
        sta (param), y      ; restore user FCB
    zendif

    pla
    tay
    pla
    plp
    rts

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
    jmptablo entry_EXIT ; exit_program = 0
    jmptablo entry_CONIN ; console_input = 1
    jmptablo entry_CONOUT ; console_output = 2
    jmptablo entry_UNIMPLEMENTED ; aux_input = 3 UNSUPPORTED
    jmptablo entry_UNIMPLEMENTED ; aux_output = 4 UNSUPPORTED
    jmptablo entry_UNIMPLEMENTED ; printer_output = 5 UNSUPPORTED
    jmptablo entry_DIRECTIO ; direct_io = 6
    jmptablo entry_GETIOBYTE ; get_io_byte = 7 UNSUPPORTED
    jmptablo entry_UNIMPLEMENTED ; set_io_byte = 8 UNSUPPORTED
    jmptablo entry_WRITESTRING ; write_string = 9
    jmptablo entry_READLINE ; read_line = 10
    jmptablo entry_GETCONSOLESTATUS ; console_status = 11
    jmptablo entry_GETVERSION ; get_version = 12
    jmptablo entry_RESET ; reset_disks = 13
    jmptablo entry_LOGINDRIVE ; select_disk = 14
    jmptablo entry_OPENFILE ; open_file = 15
    jmptablo entry_CLOSEFILE ; close_file = 16
    jmptablo entry_FINDFIRST ; find_first = 17
    jmptablo entry_FINDNEXT ; find_next = 18
    jmptablo entry_DELETEFILE ; delete_file = 19
    jmptablo entry_READSEQUENTIAL ; read_sequential = 20
    jmptablo entry_WRITESEQUENTIAL ; write_sequential = 21
    jmptablo entry_CREATEFILE ; create_file = 22
    jmptablo entry_RENAMEFILE ; rename_file = 23
    jmptablo entry_GETLOGINBITMAP ; get_login_bitmap = 24
    jmptablo entry_GETDRIVE ; get_current_drive = 25
    jmptablo entry_SETDMAADDRESS ; set_dma_address = 26
    jmptablo entry_GETALLOCATIONBITMAP ; get_allocation_bitmap = 27
    jmptablo entry_SETDRIVEREADONLY ; set_drive_readonly = 28
    jmptablo entry_GETREADONLYBITMAP ; get_readonly_bitmap = 29
    jmptablo entry_SETFILEATTRS ; set_file_attributes = 30
    jmptablo entry_GETDPB ; get_DPB = 31
    jmptablo entry_GETSETUSER ; get_set_user_number = 32
    jmptablo entry_READRANDOM ; read_random = 33
    jmptablo entry_WRITERANDOM ; write_random = 34
    jmptablo entry_COMPUTEFILESIZE ; compute_file_size = 35
    jmptablo entry_COMPUTEPOINTER ; compute_random_pointer = 36
    jmptablo entry_RESETDISK ; reset_disk = 37
    jmptablo entry_GETBIOS ; get_bios = 38
    jmptablo unimplemented ; 39
    jmptablo entry_WRITERANDOMFILLED ; write_random_filled = 40
    jmptablo bios_GETZP ; get_zp = 41
    jmptablo bios_GETTPA ; get_tpa = 42
    jmptablo entry_PARSEFCB ; 43
jumptable_hi:
    jmptabhi entry_EXIT ;exit_program = 0
    jmptabhi entry_CONIN ; console_input = 1
    jmptabhi entry_CONOUT ; console_output = 2
    jmptabhi entry_UNIMPLEMENTED ; aux_input = 3 UNSUPPORTED
    jmptabhi entry_UNIMPLEMENTED ; aux_output = 4 UNSUPPORTED
    jmptabhi entry_UNIMPLEMENTED ; printer_output = 5 UNSUPPORTED
    jmptabhi entry_DIRECTIO ; direct_console_io = 6
    jmptabhi entry_GETIOBYTE ; get_io_byte = 7 UNSUPPORTED
    jmptabhi entry_UNIMPLEMENTED ; set_io_byte = 8 UNSUPPORTED
    jmptabhi entry_WRITESTRING ; write_string = 9
    jmptabhi entry_READLINE ; read_line = 10
    jmptabhi entry_GETCONSOLESTATUS ; console_status = 11
    jmptabhi entry_GETVERSION ; get_version = 12
    jmptabhi entry_RESET ; reset_disks = 13
    jmptabhi entry_LOGINDRIVE ; select_disk = 14
    jmptabhi entry_OPENFILE ; open_file = 15
    jmptabhi entry_CLOSEFILE ; close_file = 16
    jmptabhi entry_FINDFIRST ; find_first = 17
    jmptabhi entry_FINDNEXT ; find_next = 18
    jmptabhi entry_DELETEFILE ; delete_file = 19
    jmptabhi entry_READSEQUENTIAL ; read_sequential = 20
    jmptabhi entry_WRITESEQUENTIAL ; write_sequential = 21
    jmptabhi entry_CREATEFILE ; create_file = 22
    jmptabhi entry_RENAMEFILE ; rename_file = 23
    jmptabhi entry_GETLOGINBITMAP ; get_login_bitmap = 24
    jmptabhi entry_GETDRIVE ; get_current_drive = 25
    jmptabhi entry_SETDMAADDRESS ; set_dma_address = 26
    jmptabhi entry_GETALLOCATIONBITMAP ; get_allocation_bitmap = 27
    jmptabhi entry_SETDRIVEREADONLY ; set_drive_readonly = 28
    jmptabhi entry_GETREADONLYBITMAP ; get_readonly_bitmap = 29
    jmptabhi entry_SETFILEATTRS ; set_file_attributes = 30
    jmptabhi entry_GETDPB ; get_dpb = 31
    jmptabhi entry_GETSETUSER ; get_set_user_number = 32
    jmptabhi entry_READRANDOM ; read_random = 33
    jmptabhi entry_WRITERANDOM ; write_random = 34
    jmptabhi entry_COMPUTEFILESIZE ; compute_file_size = 35
    jmptabhi entry_COMPUTEPOINTER ; compute_random_pointer = 36
    jmptabhi entry_RESETDISK ; reset_disk = 37
    jmptabhi entry_GETBIOS ; 38
    jmptabhi unimplemented ; 39
    jmptabhi entry_WRITERANDOMFILLED ; write_random_filled = 40
    jmptabhi bios_GETZP ; get_zp = 41
    jmptabhi bios_GETTPA ; get_tpa = 42
    jmptabhi entry_PARSEFCB ; 43
zendproc

; --- Misc ------------------------------------------------------------------

zproc entry_GETBIOS
    lda bios+0
    sta param+0
    ldx bios+1
    stx param+1
    rts
zendproc

zproc entry_GETVERSION
    lda #CPM_VERSION
    ldx #(CPM_MACHINE_TYPE<<4) | CPM_SYSTEM_TYPE
    rts
zendproc

zproc entry_GETIOBYTE
    lda #0x94               ; %10010100
    clc
    rts
zendproc

zproc entry_UNIMPLEMENTED
    sec
    rts
zendproc

; --- Console ---------------------------------------------------------------

zproc entry_CONIN
    lda buffered_key
    zif_eq
        jsr bios_CONIN
        tax
    zelse
        ldx #0
        stx buffered_key
    zendif
    txa
    pha
    cmp #31
    zif_cs
        jsr entry_CONOUT
    zendif
    rts
zendproc

; Prints the character in param+0.
zproc entry_CONOUT
    lda param+0
    ; fall through
zendproc
zproc internal_CONOUT
    pha
    jsr bios_CONST
    cmp #0
    zif_ne                  ; is there a key pending?
        jsr bios_CONIN      ; read it
        cmp #19             ; was it ^S?
        zif_eq
            jsr bios_CONIN  ; wait for another key press
            cmp #3
            beq reboot$
            jmp continue$
        zendif
        cmp #3              ; was it ^C?
        beq reboot$
        sta buffered_key
    zendif
continue$:
    pla
        
    ; Actually print it.

    jsr bios_CONOUT

    ; Compute column position?

    ldx column_position
    cmp #8
    beq backspace$
    cmp #127
    beq backspace$
    cmp #9
    zif_eq
        inx
        tax
        and #<~7
        sta column_position
        rts
    zendif
    cmp #32
    bcc zero_column$
    inx
    jmp exit$

backspace$:
    dex
    bpl exit$
zero_column$:
    ldx #0
exit$:
    stx column_position
    rts
reboot$:
    jmp entry_EXIT
zendproc

zproc entry_GETCONSOLESTATUS
    lda buffered_key
    zif_eq
        jsr bios_CONST
    zendif
    clc
    rts
zendproc

; If param+1 == $ff, returns a character without waiting and without echo.
; If param+1 == $fd, returns a character while waiting and without echo.
; If otherwise, prints param+0.

zproc entry_DIRECTIO
    ldx param+1
    cpx #$ff    
    zif_eq
        lda buffered_key
        ; A is either a character, or zero
        zif_eq
            jsr bios_CONST
            cmp #$ff
            zif_eq
                jsr bios_CONIN
            zendif
            ; A is either a character, or zero
        zendif
        clc
        rts
    zendif

    cpx #$fd
    zif_eq
        jmp bios_CONIN
    zendif

    lda param+0
    jsr bios_CONOUT
    clc
    rts
zendproc

internal_WRITESTRING:
    sta param+0
    stx param+1
zproc entry_WRITESTRING
    zloop
        ldy #0
        lda (param), y
        zbreakif_eq
        cmp #'$'
        zbreakif_eq

        jsr internal_CONOUT

        inc param+0
        zif_eq
            inc param+1
        zendif
    zendloop
    rts
zendproc

; Read a line from the keyboard. Buffer is at param, size at param+0.
zproc entry_READLINE
    start_column_position = temp+0
    buffer_pos = temp+1
    buffer_max = temp+2
    count = temp+3
    current_column_position = temp+4

    lda column_position
    sta start_column_position
    sta current_column_position
    lda #2
    sta buffer_pos
    ldy #0
    lda (param), y
    sta buffer_max

    zloop
        ; Read a key without echo.

        lda buffered_key
        zif_eq
            jsr bios_CONIN
            tax
        zendif
        ldx #0
        stx buffered_key
        
        ; Delete?

        cmp #8
        zif_eq
            lda #127
        zendif
        cmp #127
        zif_eq
            ldy buffer_pos
            cpy #2
            zif_ne
                dec buffer_pos
                dec current_column_position
                jsr bios_CONOUT
            zendif
            zcontinue
        zendif
        
        ; Reboot?

        cmp #3
        zif_eq
            ldy buffer_pos
            cpy #2
            zif_eq
                jmp entry_EXIT
            zendif
            zcontinue
        zendif

        ; Retype line?

        cmp #18
        zif_eq
            jsr indent_new_line
            ldy #1
            sty count
            zloop
                ldy count
                cpy buffer_pos
                zbreakif_eq

                lda (param), y
                jsr bios_CONOUT
                inc current_column_position
                inc count
            zendloop
            zcontinue
        zendif

        ; Delete line?

        cmp #21
        zif_eq
            lda #'#'
            jsr bios_CONOUT
            jsr indent_new_line

            lda #2
            sta buffer_pos
            zcontinue
        zendif

        ; Finished?

        cmp #13
        zbreakif_eq
        cmp #10
        zbreakif_eq

        ; Graphic character?

        cmp #32
        zif_cs
            ldy buffer_max
            cpy buffer_pos
            zif_cs
                ldy buffer_pos
                sta (param), y
                jsr bios_CONOUT
                inc buffer_pos
                inc current_column_position
            zendif
        zendif
    zendloop

    lda #13
    jsr internal_CONOUT
    ldx buffer_pos
    dex
    dex
    txa
    ldy #1
    sta (param), y
    rts

indent_new_line:
    jsr bios_NEWLINE
    lda #0
    sta current_column_position
    zloop
        lda current_column_position
        cmp start_column_position
        zbreakif_eq
        lda #' '
        jsr bios_CONOUT
        inc current_column_position
    zendloop
    rts
zendproc

; --- Reset disk system -----------------------------------------------------

zproc entry_RESET
    ; Reset transient BDOS state.

    ldy #(bdos_state_end - bdos_state_start - 1)
    lda #0
    zrepeat
        sta bdos_state_start, y
        dey
    zuntil_mi
    
    ; Log in drive A.

    ; A is 0
    jmp internal_LOGINDRIVE
zendproc

; Reset the write-protect bits for the drives the user asked for.

zproc entry_RESETDISK
    lda param+0
    eor #$ff
    and write_protect_vector+0
    sta write_protect_vector+0

    lda param+1
    eor #$ff
    and write_protect_vector+1
    sta write_protect_vector+1

    clc
    rts
zendproc

zproc entry_GETDRIVE
    lda current_drive
    sta param+0
    rts
zendproc

zproc entry_GETSETUSER
    clc
    lda param+0
    zif_mi
        lda current_user
        rts
    zendif
    sta current_user
    rts
zendproc

zproc entry_SETDMAADDRESS
    lda param+0
    sta user_dma+0
    lda param+1
    sta user_dma+1
    rts
zendproc

; --- FCB parsing -----------------------------------------------------------

; This is a CP/M-65 extension. DMA points at the FCB structure; on entry,
; XA points at the string. A filename is parsed into the FCB and the updated
; pointer returned. fcb->f[0] will be zero for an invalid filename.

zproc entry_PARSEFCB
    ; param -> filename
    ; dma -> FCB

    lda #0
    sta temp+1                  ; failure flag

    ; Check for drive.

    ldy #0
    ldx #0                      ; drive byte
    lda (param), y              ; drive letter
    zif_ne
        iny
        lda (param), y
        dey
        cmp #':'                    ; colon?
        zif_eq
            lda (param), y
            jsr toupper
            sec
            sbc #'A'-1              ; to 1-based drive
            cmp #16
            zif_cs
                dec temp+1
            zendif

            tax
            iny
            iny
        zendif
    zendif
    txa
    pha

    ; Read the filename.

    ; y = offset into string
    ldx #8
    zrepeat
        lda (param), y         ; get a character
        jsr toupper

        jsr is_terminator_char
        zif_cs
            ; Turn "ABC .X" -> "AB     .X"
            lda #' '
            dey                 ; reread the char again next time
        zendif
        cmp #'*'
        zif_eq
            ; Turn "ABC*.X" -> "ABC?????.X"
            lda #'?'
            dey                 ; reread the * again next time
        zendif
        pha
        iny

        dex
    zuntil_eq
    ; X is cmdoffset

    ; Skip non-dot filename characters.

    lda (param), y
    zloop
        cmp #'.'
        zbreakif_eq
        jsr is_terminator_char
        zif_cs
            lda #' '            ; filename has no extension
            pha
            pha
            pha
            bne parse_filename_exit  ; always taken
        zendif

        iny
        lda (param), y
    zendloop
    ; A is the character just read
    ; X is cmdoffset

    ; Read the extension

    iny                         ; skip dot
    ldx #3
    zrepeat
        lda (param), y          ; get a character
        jsr toupper

        jsr is_terminator_char
        zif_cs
            ; Turn "ABC .X" -> "AB     .X"
            lda #' '
            dey                 ; reread the char again next time
        zendif
        cmp #'*'
        zif_eq
            ; Turn "ABC.X*" -> "ABC.X*"
            lda #'?'
            dey                 ; reread the * again next time
        zendif
        pha
        iny

        dex
    zuntil_eq
        
    ; Discard any remaining filename characters.

    lda (param), y          ; get a character
    zrepeat
        jsr is_terminator_char
        zbreakif_cs

        iny
        lda (param), y
    zuntil_eq

parse_filename_exit:
    ; Push the four zeroes for the metadata.

    lda #0
    pha
    pha
    pha
    pha

    ; Now A contains the terminating character --- either a space or \0.  We
    ; have a valid FCB!

    ; Copy the generated bytes off the stack into the destination.

    tya
    tax
    ldy #15
    zrepeat
        pla
        sta (user_dma), y
        dey
    zuntil_mi
    txa                         ; offset into A

    ; Compute the updated pointer.

    clc
    adc param+0
    ldx param+1
    zif_cs
        inx
    zendif

    ; Exit status.

    clc
    ldy temp+1
    zif_ne
        sec
    zendif

    rts

is_terminator_char:
    stx temp+2
    ldx #(terminators_end - terminators) - 1
    zrepeat
        cmp terminators, x
        beq 1f                  ; carry set on branch
        dex
    zuntil_mi
    clc
1:
    ldx temp+2
    rts

terminators:
    .ascii " =><.:,[]/|"
    .byte 10, 13, 127, 9, 0
terminators_end:
zendproc

zproc toupper
    cmp #'a'
    zif_cs
        cmp #'z'+1
        zif_cc
            and #$5f
        zendif
    zendif
    rts
zendproc

; --- Open a file -----------------------------------------------------------

; Opens a file; the FCB is in param.
; Returns C is error; the code is in A.

entry_OPENFILE:
    jsr new_user_fcb
zproc internal_OPENFILE
    lda #FCB_S2+1              ; match 15 bytes of FCB
    jsr find_first
    zif_cc
        ; We have a matching dirent!

        ldy #FCB_EX
        lda (param), y          ; fetch user extent byte
        sta tempb

        ; Copy the dirent to FCB.

        ldy #31
        zrepeat
            lda (current_dirent), y
            sta (param), y
            dey
        zuntil_mi

        ; Set bit 7 of S2 to indicate that this file hasn't been modified.

        jsr fcb_is_not_modified

        ; Compare the user extent byte with the dirent to determine
        ; if we're at the end of the file or not.

        ldy #FCB_EX
        lda (param), y
        cmp tempb                   ; C if ex >= tempb
        zif_ne
            lda #$00                ; after the end of the file, record count empty
            zif_cs
                ; user extent is smaller
                lda #$80            ; middle of the file, record count full
            zendif
            ldy #FCB_RC
            sta (param), y            ; set extent record count
        zendif

        ; Set the FCB extent to what the user originally asked for,
        ; and not the value in the dirent.

        lda tempb
        ldy #FCB_EX
        sta (param), y

        clc
    zendif
    rts
zendproc
    
; Creates a file; the FCB is in param.
; Returns C is error; the code is in A.

entry_CREATEFILE:
    jsr new_user_fcb
zproc internal_CREATEFILE
    jsr check_disk_writable

    ; Check to see if the file exists.

    lda #FCB_S2+1
    jsr find_first
    bcc error$

    ; Clear the allocation buffer in the FCB.

    lda #0
    ldy #FCB_AL
    zrepeat
        sta (param), y
        iny
        cpy #FCB_AL+16
    zuntil_eq

    ; Search for an empty dirent.

    lda #$e5
    ldy #FCB_DR
    sta (param), y
    lda #FCB_DR+1
    jsr find_first
    bcs error$

    ; We found an empty dirent! Copy the user's FCB into it.

    ldy #1
    zrepeat
        lda (param), y
        sta (current_dirent), y
        iny
        cpy #FCB_AL+16
    zuntil_eq
    
    ; Set the user code correctly.

    lda current_user
    ldy #FCB_DR
    sta (current_dirent), y
    
    ; We might have extended the directory, so make sure
    ; the count is updated.

    jsr update_cdrmax

    ; Write the update directory buffer back to disk. find_next left all
    ; the pointers set correctly for this to work.

    lda #1
    jsr write_sector

    ; Set bit 7 of S2 in the FCB to indicate that this file hasn't been
    ; modified.

    jsr fcb_is_not_modified

    clc
    rts

error$:
    lda #$ff                ; only defined error code
    sec
    rts
zendproc

; Sets up a user-supplied FCB.

zproc new_user_fcb
    ldy #FCB_S2
    lda #0
    sta (param), y
zendproc
    ; falls through

; Selects the drive referred to in the FCB.

zproc convert_user_fcb
    ldy #FCB_DR
    lda (param), y              ; get drive byte
    sta old_fcb_drive           ; to restore on exit
    and #$0f                    ; extract drive
    tax
    dex                         ; convert to internal drive numbering
    zif_mi
        ldx current_drive       ; override with current drive
    zendif
    txa
    sta active_drive            ; set the active drive

    lda current_user
    sta (param), y              ; update FCB
    
    jmp select_active_drive
zendproc

; --- Close a file (flush the FCB to disk) ----------------------------------

entry_CLOSEFILE:
    jsr convert_user_fcb
zproc internal_CLOSEFILE
    jsr check_fcb_writable
    jsr check_disk_writable

    ; Check that this FCB has actually changed.

    ldy #FCB_S2
    lda (param), y
    zif_mi
        clc                     ; just return if not
        rts
    zendif

    ; Find the directory entry for this extent.

    lda #FCB_S2+1
    jsr find_first
    zif_cs
        rts
    zendif

    ; Update the directory entry from the FCB.

    ldy #FCB_RC
    lda (param), y
    sta (current_dirent), y

    ldy #FCB_EX
    lda (param), y
    sta (current_dirent), y

    ; Merge the allocation maps.

    jsr merge_fcb_into_dirent
    zif_cs
        rts
    zendif

    ; Write the dirent back to disk.

    lda #1
    jsr write_sector            ; sector number remains set up from find_first
    
    ; Mark the FCB as modified and exit.
    
    jsr fcb_is_not_modified
    clc
    rts
zendproc

; --- Other file manipulation -----------------------------------------------

zproc entry_DELETEFILE
    jsr convert_user_fcb
    jsr check_disk_writable

    ; Search for and destroy all files matching the filename.

    lda #FCB_T3+1
    jsr find_first
    zif_cc
        jsr check_dirent_writable
        zrepeat
            ; Free all the blocks in the matching dirent.

            ldx #0
            jsr update_bitmap_for_dirent

            ; Now mark the dirent as deleted.

            lda #$e5
            ldy #FCB_DR
            sta (current_dirent), y
            lda #1
            jsr write_sector

            ; Get the next matching dirent.

            lda #FCB_T3+1
            jsr find_next
        zuntil_cs
        clc
    zendif

    rts
zendproc

zproc entry_RENAMEFILE
    jsr convert_user_fcb
    jsr check_disk_writable

    ; Rename all files matching the filename.

    lda #FCB_T3+1
    jsr find_first
    zif_cc
        jsr check_dirent_writable
        zrepeat
            ; Replace the filename in the dirent with the new one.

            lda #FCB_F1
            sta temp+0      ; dirent index
            lda #16+FCB_F1
            sta temp+1      ; filename index
            zrepeat
                ldy temp+1
                lda (param), y

                ldy temp+0
                sta (current_dirent), y

                inc temp+0
                inc temp+1
                lda temp+0
                cmp #FCB_T3+1
            zuntil_eq

            ; Write back to disk.

            lda #1
            jsr write_sector

            ; Get the next matching dirent.

            lda #FCB_T3+1
            jsr find_next
        zuntil_cs
        clc
    zendif

    rts
zendproc

zproc entry_SETFILEATTRS
    jsr convert_user_fcb

    ; Update the filename (and attribute bits) of all files matching the
    ; filename.

    lda #FCB_T3+1
    jsr find_first
    zif_cc
        zrepeat
            ; Replace the filename in the dirent with the new one.

            ldy #FCB_F1    ; FCB/dirent index
            zrepeat
                lda (param), y
                sta (current_dirent), y
                iny
                cpy #FCB_T3+1
            zuntil_eq

            ; Write back to disk.

            lda #1
            jsr write_sector

            ; Get the next matching dirent.

            lda #FCB_T3+1
            jsr find_next
        zuntil_cs
        clc
    zendif

    rts
zendproc

; --- Read next sequential record -------------------------------------------

zproc entry_READSEQUENTIAL
    jsr convert_user_fcb
zendproc
zproc internal_READSEQUENTIAL
    ldy #FCB_CR
    lda (param), y
    ldy #FCB_RC
    cmp (param), y
    zif_eq
        cmp #$80                ; is this extent full?
        bne eof$                ; no, we've reached the end of the file
            
        ; Move to the next extent.

        jsr close_extent_and_move_to_next_one
        bcs eof$

        ; Open it.

        jsr internal_OPENFILE
        bcs eof$
    zendif
    
    jsr get_fcb_block           ; get disk block value in XA
    beq eof$
    jsr get_sequential_sector_number

    ; Move the FCB on to the next record, for next time.

    ldy #FCB_CR
    lda (param), y
    clc
    adc #1
    sta (param), y

    ; Actually do the read!

    jsr reset_user_dma
    jsr read_sector
    clc
    rts

eof$:
    lda #CPME_NODATA           ; = EOF
    sec
    rts
zendproc

; Closes the current extent, and move to the next one, but doesn't open it.
; Sets C on error (like maximum file size).
zproc close_extent_and_move_to_next_one
    jsr internal_CLOSEFILE

    ldy #FCB_EX
    lda (param), y
    clc
    adc #1
    and #$1f
    sta (param), y
    zif_eq
        ldy #FCB_S2
        lda (param), y
        and #$7f            ; remove not-modified flag
        cmp #$7f            ; maximum possible file size?
        beq eof

        lda (param), y
        clc
        adc #1
        sta (param), y
    zendif
    lda #0
    ldy #FCB_CR
    sta (param), y
    ; We also want to clear the record count, to avoid a nasty edge
    ; case where we've just moved to a non-existent record. This
    ; causes subsequent reads to fail with EOF rather than just
    ; reading garbage.
    ldy #FCB_RC
    sta (param), y
    clc
    rts

eof:
    sec
    rts
zendproc

; Fetch the current block number in the FCB in XA.
; Returns Z if the block number is zero (i.e., there isn't one).
zproc get_fcb_block
    jsr get_fcb_block_index     ; gets index in Y
    ldx blocks_on_disk+1        ; are we a big disk?
    zif_ne                      ; yes
        lda (param), y
        iny
        ora (param), y          ; check for zero
        zif_ne
            lda (param), y          ; high byte!
            tax
            dey
            lda (param), y          ; low byte
            rts
        zendif
    zendif

    ldx #0
    lda (param), y              ; sets Z if zero
    rts
zendproc

; Set the current block number in the FCB to XA.
; Preserves XA.
zproc set_fcb_block
    sta temp+0
    stx temp+1

    jsr get_fcb_block_index     ; gets index in Y
    lda temp+0                  ; fetch low byte
    sta (param), y
    ldx blocks_on_disk+1        ; are we a big disk?
    zif_ne                      ; yes
        iny
        lda temp+1              ; fetch high byte
        sta (param), y
    zendif

    lda temp+0
    ldx temp+1
    rts
zendproc

; Return offset to the current block in the FCB in Y.
; Uses temp+2.
zproc get_fcb_block_index
    lda #7
    sec
    sbc block_shift 
    tax                         ; x = how much to shift extent number

    lda extent_mask
    ldy #FCB_EX                ; get current extent
    and (param), y              ; extent offset into dirent
    zrepeat                     ; shift extent to get allocation map start
        asl a
        dex
    zuntil_eq
    sta temp+2

    ldy #FCB_CR                ; get current record
    clc
    lda (param), y

    ldx block_shift             ; get block index
    zrepeat
        lsr a
        dex
    zuntil_eq                   ; A = block index

    clc
    adc temp+2                  ; add extent start index

    ldx blocks_on_disk+1        ; are we a big disk?
    zif_ne                      ; yes
        asl a                   ; blocks occupy two bytes
    zendif

    clc
    adc #FCB_AL                ; get offset into allocation map
    tay
    rts
zendproc

; When closing the file, we want to merge the allocation map in the
; FCB with the one in the dirent.
zproc merge_fcb_into_dirent
    ldy #FCB_AL                ; index into FCB/dirent
    lda blocks_on_disk+1        ; are we a big disk?
    zif_ne                      ; yes
        zrepeat
            lda (param), y
            iny
            ora (param), y
            zif_eq              ; FCB <- dirent
                lda (current_dirent), y
                sta (param), y
                dey
                lda (current_dirent), y
                sta (param), y
                iny
            zendif

            lda (current_dirent), y
            dey
            ora (current_dirent), y
            zif_eq              ; FCB -> dirent
                lda (param), y
                sta (current_dirent), y
                iny
                lda (param), y
                sta (current_dirent), y
                dey
            zendif

            lda (param), y
            cmp (current_dirent), y
            iny
            lda (param), y
            sbc (current_dirent), y
            bne merge_error         ; FCB != dirent --- this is bad

            iny
            cpy #FCB_AL+16
        zuntil_eq
        clc
        rts
    zendif

    zrepeat
        lda (param), y          ; get FCB block number
        zif_eq                  ; FCB <- dirent
            lda (current_dirent), y
            sta (param), y
        zendif

        lda (current_dirent), y
        zif_eq                  ; FCB -> dirent
            lda (param), y
            sta (current_dirent), y
        zendif

        lda (param), y
        cmp (current_dirent), y
        bne merge_error         ; FCB != dirent --- this is bad

        iny
        cpy #FCB_AL+16
    zuntil_eq
    clc
    rts

merge_error:
    sec
    rts
zendproc

; Computes the sector number of the block in XA.  XA must not be zero.
zproc get_sequential_sector_number
    sta current_sector+0
    stx current_sector+1

    lda #0
    sta current_sector+2

    ; Convert block number to sector number.

    ldx block_shift
    zrepeat
        asl current_sector+0
        rol current_sector+1
        rol current_sector+2
        dex
    zuntil_eq

    ; Add on record number.

    ldy #FCB_CR
    lda (param), y
    and block_mask              ; get offset in block

    clc
    adc current_sector+0
    sta current_sector+0
    zif_cs
        inc current_sector+1
        zif_eq
            inc current_sector+2
        zendif
    zendif

    ; Add on reserved sector count.

    clc
    lda current_sector+0
    adc reserved_sectors+0
    sta current_sector+0
    lda current_sector+1
    adc reserved_sectors+1
    sta current_sector+1
    zif_cs
        inc current_sector+2
    zendif
    rts
zendproc

; --- Write the next sequential record --------------------------------------

zproc entry_WRITESEQUENTIAL
    jsr convert_user_fcb
    jsr check_fcb_writable
    jsr check_disk_writable

    ldy #FCB_CR
    lda (param), y
    cmp #$80
    zif_eq                      ; is this extent full?
        ; Move to the next extent.

        jsr close_extent_and_move_to_next_one
        lda #2                  ; disk full
        zif_cs
            rts
        zendif

        ; Open it.

        ldy #FCB_RC            ; clear record count
        lda #0
        sta (param), y

        jsr internal_OPENFILE
        zif_cs
            ; Could not open new extent --- it must not exist.

            jsr internal_CREATEFILE
            lda #1              ; directory full
            zif_cs
                rts
            zendif
        zendif
    zendif

    jsr seek_to_block_and_create
    
    ; Move the FCB on to the next record, for next time.

    ldy #FCB_CR
    lda (param), y
    clc
    adc #1
    sta (param), y

    ; If (CR+1) > RC, update RC.

    ldy #FCB_RC
    cmp (param), y
    zif_cs
        sta (param), y
        jsr fcb_is_modified
    zendif

    ; Actually do the write!

    jsr reset_user_dma
    lda #0
    jsr write_sector
    lda #0
    clc
    rts
zendproc

; Sets the current sector to the block pointed to by the FCB,
; creating a new one if necessary.

zproc seek_to_block_and_create
    jsr get_fcb_block           ; get disk block value in XA
    zif_eq
        jsr fcb_is_modified
        jsr allocate_unused_block
        jsr set_fcb_block
        jsr get_sequential_sector_number

        lda block_needs_clearing
        zif_ne
            ; Wipe the new block.

            ldy #0
            tya
            zrepeat
                sta (directory_buffer), y
                iny
                cpy #128
            zuntil_eq

            ; Now write zeroes until the block is full.

            lda directory_buffer+0
            ldx directory_buffer+1
            ldy #BIOS_SETDMA
            jsr callbios

            zrepeat
                lda #2
                jsr write_sector

                inc current_sector+0
                zif_eq
                    inc current_sector+1
                    zif_eq
                        inc current_sector+2
                    zendif
                zendif
                
                lda current_sector+0
                and block_mask
            zuntil_eq
        zendif

        ; Get the block number again for get_sequential_sector_number.

        jsr get_fcb_block
    zendif
    jmp get_sequential_sector_number
zendproc

zproc fcb_is_not_modified
    ldy #FCB_S2
    lda (param), y
    ora #$80
    sta (param), y
    rts
zendproc

zproc fcb_is_modified
    ldy #FCB_S2
    lda (param), y
    and #$7f
    sta (param), y
    rts
zendproc

; --- Random access ---------------------------------------------------------

zproc entry_WRITERANDOM
    jsr convert_user_fcb
    jsr check_fcb_writable
    jsr check_disk_writable

    jsr seek_to_random_location
    zif_cs
        ; Do we need a new extent?

        cmp #CPME_NOEXTENT
        zif_eq
            sec
            rts
        zendif
            
        ; Could not open new extent --- it must not exist.

        jsr internal_CREATEFILE
        lda #CPME_DIRFULL
        sec
    zendif
    zif_cc
        ; If (CR+1) > RC, update RC.

        ldy #FCB_CR
        lda (param), y
        clc
        adc #1
        ldy #FCB_RC
        cmp (param), y
        zif_cs
            sta (param), y
            jsr fcb_is_modified
        zendif

        ; Actually do the write!

        jsr seek_to_block_and_create
        jsr reset_user_dma
        lda #0
        jsr write_sector
        lda #0
        clc
    zendif
    rts
zendproc

zproc entry_WRITERANDOMFILLED
    lda #1
    sta block_needs_clearing
    jmp entry_WRITERANDOM
zendproc

zproc entry_READRANDOM
    jsr convert_user_fcb
    jsr seek_to_random_location
    zif_cc
        ; If CR > RC, fail.

        ldy #FCB_CR
        lda (param), y
        ldy #FCB_RC
        cmp (param), y
        bcs nodata

        ; Actually do the read!

        jsr get_fcb_block           ; get disk block value in XA
        beq nodata
        jsr get_sequential_sector_number

        ; Actually do the read!

        jsr reset_user_dma
        jsr read_sector
        lda #0
        clc
    zendif
    rts
nodata:
    lda #CPME_NODATA
    sec
    rts
zendproc

; Adjust the FCB to point to the random access location, shifting
; extents as necessary. Returns C on error.

zproc seek_to_random_location
    ; Convert random access record number to M/E/R.

    ldy #FCB_R0
    lda (param), y
    and #$7f
    ldy #FCB_CR
    sta (param), y          ; new current record

    ldy #FCB_R0
    lda (param), y          ; get low byte
    rol a                   ; top bit into carry
    iny
    lda (param), y          ; get high byte
    rol a                   ; carry into bottom bit and x2
    and #$1f
    sta temp+1              ; new extent

    ldy #FCB_R1
    lda (param), y          ; get high byte
    lsr a
    lsr a
    lsr a
    lsr a
    sta temp+2              ; new module

    ; Do we need to switch to a different extent?

    ldy #FCB_S2
    lda (param), y          ; compare S2
    and #$7f                ; ...ignoring not-modified bit
    cmp temp+2
    zif_eq
        ldy #FCB_EX
        lda (param), y
        cmp temp+1
    zendif
    zif_ne
        lda temp+1
        pha                     ; push EX
        lda temp+2
        pha                     ; push S2

        jsr internal_CLOSEFILE
        lda #CPME_CANTCLOSE
        bcs 1f

        ldy #FCB_S2
        pla
        sta (param), y          ; update S2

        ldy #FCB_EX
        pla
        sta (param), y          ; update EX

        jsr internal_OPENFILE
        lda #CPME_NOEXTENT
        bcs 1f
    zendif
    clc
1:
    rts

zendproc

; Sets the random access pointer to whereever the FCB is currently
; pointing.

zproc entry_COMPUTEPOINTER
    ldy #FCB_EX
    lda (param), y              ; get EX
    lsr a                       ; bottom bit -> C
    sta temp+1                  ; store high byte
    lda #0
    ror a                       ; C -> top bit
    ; low byte in A (the top bit)

    ldy #FCB_CR
    ora (param), y              ; merge in record count
    ldy #FCB_R0
    sta (param), y              ; finished with low byte

    ldy #FCB_S2                ; get S2
    lda (param), y
    asl a
    asl a
    asl a
    asl a
    ora temp+1
    ldy #FCB_R1                ; finished with high byte
    sta (param), y

    clc
    rts
zendproc

; Determines the size of a file and seeks to the end.

zproc entry_COMPUTEFILESIZE
    jsr new_user_fcb

    ; temp+0/1 are used by find_first
    lda #0
    sta temp+2                  ; file size accumulator
    sta temp+3

    lda #FCB_T3+1              ; match just the filename
    jsr find_first
    zif_cc
        zrepeat
            ; Check for a maximum-possible-length file,
            ; resulting in file size overflow.

            ldy #FCB_RC
            lda (current_dirent), y
            cmp #$80            ; maximum possible RC
            zif_eq
                ldy #FCB_EX
                lda (current_dirent), y
                cmp #$1f        ; maximum possible EX
                zif_eq
                    ldy #FCB_S2
                    lda (current_dirent), y
                    cmp #$0f    ; maximum possible S2
                    zif_eq
                        ; This file is the maximum possible length!
                        ; We can just stop here.

                        ldy #FCB_R0
                        lda #0
                        sta (param), y  ; 0 -> r0
                        iny
                        sta (param), y  ; 0 -> r1
                        lda #1
                        iny
                        sta (param), y  ; 0 -> r2
                        clc
                        rts
                    zendif
                zendif
            zendif

            ; We now know that the file size can't overflow.
            ; *But*, the current dirent may still have a size
            ; of 128 records...

            ; Calculate the size of the file.

            ldy #FCB_S2                ; get S2
            lda (current_dirent), y
            asl a
            asl a
            asl a
            asl a
            sta tempb

            ldy #FCB_EX
            lda (current_dirent), y      ; get EX
            lsr a
            ora tempb
            tax

            lda #0
            ror a                       ; $00 or $80, from LSB of EX

            ldy #FCB_RC
            clc
            adc (current_dirent), y     ; add in record count
            zif_cs
                inx
            zendif

            ; high byte of file size -> x
            ; low byte of file size -> a

            cpx temp+3
            zif_cs
                zif_eq
                    cmp temp+2
                zendif
            zendif
            zif_ne
                ; Update the file size accumulator.

                sta temp+2
                stx temp+3
            zendif

            lda #FCB_T3+1
            jsr find_next
        zuntil_cs
    zendif

    ; temp+2/3 now contains the record count of the file.

    lda #0
    ldy #FCB_R2
    sta (param), y
    dey
    lda temp+3
    sta (param), y              ; r1
    dey
    lda temp+2
    sta (param), y              ; r0

    clc
    rts
zendproc

; --- Directory scanning ----------------------------------------------------

; Find a dirent matching the user FCB.
; On entry, A is the number of significant bytes in the FCB to use when
; searching.
; Returns C on error.

zproc entry_FINDFIRST
    jsr setup_fcb_for_find
    bcs find_error
    ; A = number of bytes to search
    jsr find_first
    jmp copy_result_of_find
zendproc

zproc entry_FINDNEXT
    jsr setup_fcb_for_find
    bcs find_error
    ; A = number of bytes to search
    jsr find_next
    ; fall through
copy_result_of_find:
    zif_cc
        ; Copy the directory buffer into the DMA buffer.

        jsr copy_directory_buffer_to_dma

        ; Calculate the offset into the DMA buffer.

        lda current_dirent+0
        sec
        sbc directory_buffer+0
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        clc
    zendif
find_error:
    rts
zendproc

; Returns the number of bytes to search.
zproc setup_fcb_for_find
    ldy #FCB_DR
    lda (param), y
    cmp #'?'
    zif_eq
        lda #FCB_DR+1          ; number of bytes to search
    zelse
        jsr convert_user_fcb
        bcs error

        ldy #FCB_EX
        lda (param), y
        cmp #'?'
        zif_eq                  ; get all extents?
            ldy #FCB_S2
            sta (param), y      ; module number should be a wildcard
        zendif

        lda #FCB_S2+1          ; number of bytes to search
    zendif
    clc
error:
    rts
zendproc

; This is used twice, so factor it out. That's not a lot, but it's strange it's
; happened twice.
zproc copy_directory_buffer_to_dma
    lda user_dma+0
    sta temp+0
    lda user_dma+1
    sta temp+1

    ldy #127
    zrepeat
        lda (directory_buffer), y
        sta (temp), y
        dey
    zuntil_mi
    rts
zendproc

find_first:
    sta find_first_count
    jsr home_drive
    jsr reset_dir_pos
    ; fall through
zproc find_next
    jsr read_dir_entry
    jsr check_dir_pos
    beq no_more_files

    ; Does the user actually want to see deleted files?

    lda #$e5
    ldy #0
    cmp (param), y
    zif_ne
        ; If current_dirent is higher than cdrmax, we know that
        ; the rest of the directory is empty, so give up now.
        ldy #DPH_CDRMAX
        lda (dph), y
        cmp directory_pos+0
        iny
        lda (dph), y
        sbc directory_pos+1
        bcc no_more_files
    zendif

    ldy #0
    zrepeat
        lda (param), y
        cmp #'?'                ; wildcard
        beq same_characters    ; ...skip comparing this byte
        cpy #FCB_S1            ; don't care about byte 13
        beq same_characters
        cpy #FCB_EX
        bne compare_chars

        ; Special logic for comparing extents.

        lda extent_mask
        eor #$ff                ; inverted extent mask
        pha
        and (param), y          ; mask FCB extent
        sta tempb
        pla
        and (current_dirent),y  ; mask dirent extent
        sec
        sbc tempb
        and #$1f                ; only check bits 0..4
        bne find_next           ; not the same? give up
        jmp same_characters

    compare_chars:
        sec
        sbc (current_dirent), y ; compare the two characters
        and #$7f                ; ignore top bit
        bne find_next           ; not the same? give up
    same_characters:
        iny
        cpy find_first_count    ; reached the end of the string?
    zuntil_eq

    ; We found a file!

    clc
    rts
    
no_more_files:
    jsr reset_dir_pos
    sec
    rts
zendproc
    
; Check that the currently opened FCB is r/w.

zproc check_fcb_writable
    ldy #FCB_T1
    lda (param), y
    bmi not_writable_error
    rts
zendproc

zproc check_dirent_writable
    ldy #FCB_T1
    lda (current_dirent), y
    bmi not_writable_error
    rts
zendproc 

zproc not_writable_error
    lda #<msg
    ldx #>msg
    jmp harderror
msg:
    .ascii "BDOS: file is R/O"
    .byte 13, 10, 0
zendproc

; --- Login drive -----------------------------------------------------------

; Logs in active_drive. If the drive was not already logged in, the bitmap
; is recomputed. In all cases the drive is selected.

zproc entry_LOGINDRIVE
    lda param+0
zendproc
zproc internal_LOGINDRIVE
    ; Select the drive.

    jsr select_active_drive

    ; Decide if the drive was already logged in.

    lda login_vector+0
    ldx login_vector+1
    ldy active_drive
    jsr shiftr              ; flag at bottom of temp+0

    ror temp+0
    zif_cs
        rts
    zendif

    ; Not already logged in. Update the login vector.

    lda #<login_vector
    ldx #>login_vector
    ldy active_drive
    jsr setbit              ; sets the login vector bit

    ; Zero the bitmap.

    lda blocks_on_disk+0
    ldx blocks_on_disk+1
    clc                     ; add 7 to round up
    adc #7
    zif_cs
        inx
    zendif
    ldy #3
    jsr shiftr              ; XA = temp+0 = number of bytes of bitmap

    lda bitmap+0            ; pointer to bitmap into temp
    sta temp+2
    lda bitmap+1
    sta temp+3

    ldy #0
    zrepeat
        tya
        sta (temp+2), y     ; zero a byte

        inc temp+2          ; advance pointer
        zif_eq
            inc temp+3
        zendif

        lda temp+0          ; decrement count
        sec
        sbc #1
        sta temp+0
        zif_cc
            dec temp+1
        zendif

        lda temp+0
        ora temp+1
    zuntil_eq

    ; Initialise the bitmap with the directory.

    lda bitmap+0            ; reset temporary pointer to the beginning of the bitmap
    sta temp+2
    lda bitmap+1
    sta temp+3

    ldy #1
    zrepeat
        lda bitmap_init+0, y
        sta (temp+2), y
        dey
    zuntil_mi

    ; Zero cdrmax.

    lda #0
    ldy #DPH_CDRMAX+0
    sta (dph), y
    iny
    sta (dph), y

    ; Actually read the disk.

    jsr home_drive
    jsr reset_dir_pos
    zloop
        jsr read_dir_entry
        jsr check_dir_pos
        zbreakif_eq

        ldy #0
        lda (current_dirent), y
        cmp #$e5                    ; is this directory entry in use?
        zif_ne
            ldx #1
            jsr update_bitmap_for_dirent
            jsr update_cdrmax
        zendif
    zendloop

    rts
zendproc

; Reads the next directory entry.

zproc read_dir_entry
    ; Have we run out of directory entries?

    lda directory_pos+0         ; is this the last?
    cmp directory_entries+0
    zif_eq
        lda directory_pos+1
        cmp directory_entries+1
        zif_eq
            jmp reset_dir_pos
        zendif
    zendif

    ; Move to the next dirent

    inc directory_pos+0
    zif_eq
        inc directory_pos+1
    zendif

    ; Calculate offset in directory record

    lda directory_pos+0
    and #3
    clc
    rol a
    rol a
    rol a
    rol a
    rol a

    ; If at the beginning of a new record, reload it from disk.

    zif_eq
        jsr calculate_dirent_sector

        lda directory_buffer+0
        ldx directory_buffer+1
        ldy #BIOS_SETDMA
        jsr callbios

        jsr read_sector
        lda #0
    zendif
    
    clc
    adc directory_buffer+0
    sta current_dirent+0
    lda directory_buffer+1
    adc #0
    sta current_dirent+1
    rts
zendproc

; Updates the cdrmax field in the DPH to mark the maximum directory
; entry for a drive (from directory_pos).
zproc update_cdrmax
    ldy #DPH_CDRMAX
    lda directory_pos+0
    cmp (dph), y
    iny
    lda directory_pos+1
    sbc (dph), y
    zif_cs
        ; Update cdrmax.
        sta (dph), y
        dey
        lda directory_pos+0
        sta (dph), y
    zendif
    rts
zendproc

; Marks a dirent's blocks as either used or free in the bitmap.
; X=1 to mark as used, X=0 to mark as free.
zproc update_bitmap_for_dirent
    stx temp+2              ; cache set/free flag
    ldy #16                 ; offset into dirent
    zloop
        cpy #32
        zif_eq
            rts
        zendif

        lda blocks_on_disk+1
        bne bigdisk
        
        lda (current_dirent), y
        sta temp+0              ; store low bye
        lda #0
        jmp checkblock
    bigdisk:
        lda (current_dirent), y
        sta temp+0              ; store low byte
        iny
        lda (current_dirent), y
    checkblock:
        iny
        sta temp+1              ; store high byte
        ora temp+0              ; check for zero
        zcontinueif_eq

        sty temp+3

        lda temp+2              ; get set/free flag
        jsr update_bitmap_status

        ldy temp+3
    zendloop
zendproc

; Given a block number in temp+0, return the address of the bitmap byte
; in temp+0 and the bit position in A.

get_bitmap_location:
    lda temp+0              ; get bit position
    and #7
    eor #$ff
    sec
    adc #7                  ; compute 7-a

    pha
    ldy #3
    jsr shiftr_temp0        ; temp0 is now offset into bitmap

    lda bitmap+0            ; add bitmap address
    clc
    adc temp+0
    sta temp+0
    lda bitmap+1
    adc temp+1
    sta temp+1

    pla
    rts

; Given a block number in temp+0, return the rotated block status in A.

zproc get_bitmap_status
    jsr get_bitmap_location
    tax
    ldy #0
    lda (temp+0), y
    jmp rotater8
zendproc

; Given a block number in temp+0 and a single-bit block status in A,
; sets it.

zproc update_bitmap_status
    sta value
    jsr get_bitmap_location
    sta bitpos
    tax

    ldy #0
    lda (temp+0), y
    jsr rotater8            ; get rotated status
    and #$fe                ; mask off bit we care about
value = .+1
    ora #$00                ; or in the new status
bitpos = .+1
    ldx #$00
    jsr rotatel8            ; unrotate
    ldy #0
    sta (temp+0), y         ; update bitmap
    rts
zendproc

; Finds an unused block from the bitmap and allocates it. Returns it in XA.

zproc allocate_unused_block
    lda #0                  ; block number
    sta temp+2
    sta temp+3

    zloop
        lda temp+2
        sta temp+0
        lda temp+3
        sta temp+1
        jsr get_bitmap_status
        and #$01
        zbreakif_eq

        inc temp+2
        zif_eq
            inc temp+3
        zendif
    zendloop

    lda temp+2
    sta temp+0
    lda temp+3
    sta temp+1
    lda #1
    jsr update_bitmap_status

    lda temp+2
    ldx temp+3
    rts
zendproc

; Sets a drive as being readonly.

zproc entry_SETDRIVEREADONLY
    lda #<write_protect_vector
    ldx #>write_protect_vector
    ldy current_drive
    jsr setbit
    clc
    rts
zendproc

; Returns the login bitmap in XA.

zproc entry_GETLOGINBITMAP
    lda login_vector+0
    ldx login_vector+1
    clc
    rts
zendproc

; Returns the readonly bitmap in XA.

zproc entry_GETREADONLYBITMAP
    lda write_protect_vector+0
    ldx write_protect_vector+1
    rts
zendproc

; Returns a pointer to the allocation bitmap in XA.

zproc entry_GETALLOCATIONBITMAP
    lda bitmap+0
    ldx bitmap+1
    clc
    rts
zendproc

; Returns a pointer to the current drive's DPB.

zproc entry_GETDPB
    lda current_dpb+0
    ldx current_dpb+1
    clc
    rts
zendproc

; --- Drive management ------------------------------------------------------

reset_user_dma:
    lda user_dma+0
    ldx user_dma+1
    ldy #BIOS_SETDMA
    jmp callbios

set_current_sector:
    lda #<current_sector
    ldx #>current_sector
    ldy #BIOS_SETSEC
    jmp callbios

read_sector:
    jsr set_current_sector
    ldy #BIOS_READ
    jmp callbios

; A=0, 1 or 2 as for BIOS_WRITE on entry.

write_sector:
    pha
    jsr set_current_sector
    pla
    ldy #BIOS_WRITE
    jmp callbios

; Calculates the block and sector addresses of the dirent in
; directory_pos.

calculate_dirent_sector:
    lda directory_pos+0
    ldx directory_pos+1
    ldy #2
    jsr shiftr                  ; 4 dirents per sector

    clc
    adc reserved_sectors+0
    sta current_sector+0

    txa
    adc reserved_sectors+1
    sta current_sector+1

    lda #0
    sta current_sector+2
    rts

; Resets the directory position to -1 (it's preincremented).

reset_dir_pos:
    lda #$ff
    sta directory_pos+0
    sta directory_pos+1
    rts

; Checks that the directory position is valid.
; Returns Z if invalid.

check_dir_pos:
    ldx directory_pos+0
    cpx directory_pos+1
    zif_ne                      ; if not the same, cannot be 0xffff
        ldx #1
        rts
    zendif
    inx                         ; they are the same, so test one byte for 0xff
    rts

zproc home_drive
    lda #0
    ldy #2
    zrepeat
        sta current_sector, y
        dey
    zuntil_mi
    rts
zendproc

zproc select_active_drive
    lda active_drive
    ldy #BIOS_SELDSK
    jsr callbios
    zif_cc
        ; Copy DPH into local storage.

        sta dph+0
        stx dph+1

        ldy #DPH_DIRBUF
        ldx #0
        zloop
            lda (dph), y
            sta directory_buffer, x
            iny
            inx
            cpy #DPH_ALV+2
        zuntil_eq

        ; Copy DPB into local storage.

        ldy #dpb_copy_end - dpb_copy - 1
        zrepeat
            lda (current_dpb), y
            sta dpb_copy, y
            dey
        zuntil_mi

        clc
    zendif
    rts
zendproc
    
; Checks that the current disk isn't in the read-only vector.

zproc check_disk_writable
    lda write_protect_vector+0
    ldx write_protect_vector+1
    ldy active_drive
    jsr shiftr              ; flag at bottom of temp+0

    ror temp+0
    zif_cs
        lda #<1f
        ldx #>1f
        jmp harderror
    zendif
    rts

1:
    .ascii "BDOS: disk is R/O"
    .byte 13, 10, 0
zendproc

; --- Utilities -------------------------------------------------------------

; Shifts XA right Y bits.
; Uses temp. Leaves the shifted value in temp+0.

zproc shiftr
    sta temp+0
    stx temp+1
shiftr_temp0:
    iny
    zloop
        dey
        beq shift_exit
        clc
        ror temp+1
        ror temp+0
    zendloop
shift_exit:
    lda temp+0
    ldx temp+1
    rts
zendproc
    
; Shifts XA left Y bits.
; Uses temp. Leaves the shifted value in temp+0.

zproc shiftl
    sta temp+0
    stx temp+1
    iny
    zloop
        dey
        beq shift_exit
        clc
        rol temp+0
        rol temp+1
    zendloop
zendproc

; Sets bit Y of (XA).
; Uses temp.

zproc setbit
    sta temp+2
    stx temp+3

    lda #1
    ldx #0
    jsr shiftl      ; shift it left by Y

    ldy #1
    zrepeat
        lda (temp+2), y
        ora temp+0, y
        sta (temp+2), y
        dey
    zuntil_mi

    rts
zendproc

; Rotate A right X times.
zproc rotater8
    inx
    zloop
        dex
        zbreakif_eq
        lsr a
        zif_cs
            ora #$80
        zendif
    zendloop
    rts
zendproc

; Rotate A left X times.
zproc rotatel8
    inx
    zloop
        dex
        zbreakif_eq
        asl a
        adc #0
    zendloop
    rts
zendproc
    
; Calls the BIOS entrypoint.

callbios:
bios = callbios + 1
    jmp 0

bios_NEWLINE:
    lda #13
    jsr bios_CONOUT
    lda #10
    ; fall through
bios_CONOUT:
    ldy #BIOS_CONOUT
    jmp callbios

bios_CONIN:
    ldy #BIOS_CONIN
    jmp callbios

bios_CONST:
    ldy #BIOS_CONST
    jmp callbios

bios_GETTPA:
    ldy #BIOS_GETTPA
    jmp callbios

bios_GETZP:
    ldy #BIOS_GETZP
    jmp callbios

bios_SETDMA:
    ldy #BIOS_SETDMA
    jmp callbios

NOINIT

; State preserved between BDOS invocations.

current_drive:  .byte 0     ; current working drive
current_user:   .byte 0     ; current working user

; State used by BDOS invocation. Reset to zero every time the BDOS
; is initialised.

bdos_state_start:
find_first_count:       .byte 0
active_drive:           .byte 0 ; drive currently being worked on
old_drive:              .byte 0 ; if the drive has been overridden by the FCB
old_fcb_drive:          .byte 0 ; drive in user FCB on entry
write_protect_vector:   .word 0
login_vector:           .word 0
directory_pos:          .word 0
current_sector:         .fill 3  ; 24-bit sector number
block_needs_clearing:   .byte 0 ; if set, any new block that's created will be zeroed

buffered_key:           .byte 0
output_paused:          .byte 0 ; top bit set if paused
column_position:        .byte 0
entry_stack:            .byte 0 ; saved stack on system call entry
bdos_state_end:

; Copy of DPB of currently selected drive.

dpb_copy:
                    .word 0 ; sectors per track (unused)
block_shift:        .byte 0
block_mask:         .byte 0
extent_mask:        .byte 0
blocks_on_disk:     .word 0
directory_entries:  .word 0
bitmap_init:        .word 0
checksum_vector_size: .word 0
reserved_sectors:   .word 0
dpb_copy_end:

; vim: filetype=asm sw=4 ts=4 et

