    .include "cpm65.inc"
    .include "zif.inc"

    .import __ZEROPAGE_SIZE__
    .import __CODE_RUN__
    .import __BSS_RUN__
    .import __BSS_SIZE__

    CPM_MACHINE_TYPE = $f ; 6502!
    CPM_SYSTEM_TYPE = 0
    CPM_VERSION = $22 ; CP/M 2.2 (compatible)

.macro debug s
    jsr pdebug
    .byte s
    .byte 13, 10, 0
.endmacro

    .zeropage

current_dirent: .word 0     ; current directory entry
param:          .word 0     ; current user input parameter
dph:            .word 0     ; currently selected DPH

directory_buffer:   .word 0 ; directory buffer from the DPH
current_dpb:        .word 0 ; currently selected DPB
checksum_buffer:    .word 0 ; checksum buffer from the DPH
bitmap:             .word 0 ; allocation bitmap from the DPH

temp:           .res 4      ; temporary storage
tempb:          .byte 0     ; more temporary storage
debugp1:        .word 0     ; used for debug strings
debugp2:        .word 0     ; used for debug strings

; --- Initialisation --------------------------------------------------------
; TODO: figure out how to discard this.

    .code
    CPM65_BARE_HEADER

    ; Store BIOS entrypoint pointer.

    sta bios+0
    stx bios+1

    ; Reset persistent state.

    lda #0
    sta current_user
    sta current_drive

    ; Update memory region.

    ldy #bios::getzp
    jsr callbios
    clc
    adc #<__ZEROPAGE_SIZE__
    ldy #bios::setzp
    jsr callbios
    
    jsr bios_GETTPA
    clc
    adc #>(__BSS_RUN__ + __BSS_SIZE__ - __CODE_RUN__ + 255)
    ldy #bios::settpa
    jsr callbios
    ; fall through to entry_EXIT

; --- Warm start ------------------------------------------------------------

entry_EXIT:
    ldx #$ff                ; reset stack point
    txs

    jsr bios_NEWLINE
    jsr entry_RESET

    ; Open the CCP.SYS file.

    lda #0
    sta ccp_fcb + fcb::ex
    sta ccp_fcb + fcb::s2
    sta ccp_fcb + fcb::cr
    lda #1
    sta ccp_fcb + fcb::dr

    lda #<ccp_fcb
    sta param+0
    lda #>ccp_fcb
    sta param+1
    jsr entry_OPENFILE
    zif_cs
        debug "Couldn't open CCP"
        jmp *
    zendif

    ; Read the first sector.

    lda directory_buffer+0
    sta user_dma+0
    lda directory_buffer+1
    sta user_dma+1
    jsr internal_READSEQUENTIAL ; load one record

    ; Compute the load address.

    jsr bios_GETZP          ; top of ZP in X
    txa
    sec
    ldy #comhdr::zp_usage
    sbc (directory_buffer), y
    pha
    
    jsr bios_GETTPA         ; top of TPA page number in X
    txa
    sec
    ldy #comhdr::tpa_usage
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
    
    ldy #comhdr::bdos
    lda #<ENTRY
    sta (temp), y
    iny
    lda #>ENTRY
    sta (temp), y

    ; Relocate.

    pla                     ; pop start zero page address, saved earlier
    tax
    lda temp+1              ; start of TPA, in pages
    ldy #bios::relocate
    jsr callbios

    ; Execute it.

    lda #comhdr::entry      ; start address is 256-byte aligned
    sta temp+0
calltemp:
    jmp (temp)

    .data
ccp_fcb:
    .byte 1                 ; drive A:
    .byte "CCP     SYS"     ; filename: CCP.SYS
    .byte 0, 0, 0, 0        ; EX, S1, S2, RC
    .res 16, 0              ; allocation block
    .byte 0

; --- BDOS entrypoint -------------------------------------------------------

    .code
.proc ENTRY
    sta param+0
    stx param+1

    lda #$ff
    sta old_fcb_drive       ; mark FCB as not fiddled with

    lda jumptable_lo, y
    sta temp+0
    lda jumptable_hi, y
    sta temp+1
    jsr calltemp            ; preserve carry from this!
    php
    pha
    txa
    pha
    tya
    pha

    lda old_fcb_drive
    zif_pl
        ldy #fcb::dr
        sta (param), y      ; restore user FCB
    zendif

    pla
    tay
    pla
    tax
    pla
    plp
    rts

unimplemented:
    debug "unimplemented"
    jmp *

jumptable_lo:
    .lobytes entry_EXIT ; exit_program = 0
    .lobytes entry_CONIN ; console_input = 1
    .lobytes entry_CONOUT ; console_output = 2
    .lobytes entry_UNIMPLEMENTED ; aux_input = 3 UNSUPPORTED
    .lobytes entry_UNIMPLEMENTED ; aux_output = 4 UNSUPPORTED
    .lobytes entry_UNIMPLEMENTED ; printer_output = 5 UNSUPPORTED
    .lobytes entry_DIRECTIO ; direct_io = 6
    .lobytes entry_GETIOBYTE ; get_io_byte = 7 UNSUPPORTED
    .lobytes entry_UNIMPLEMENTED ; set_io_byte = 8 UNSUPPORTED
    .lobytes entry_WRITESTRING ; write_string = 9
    .lobytes entry_READLINE ; read_line = 10
    .lobytes entry_GETCONSOLESTATUS ; console_status = 11
    .lobytes entry_GETVERSION ; get_version = 12
    .lobytes entry_RESET ; reset_disks = 13
    .lobytes entry_LOGINDRIVE ; select_disk = 14
    .lobytes entry_OPENFILE ; open_file = 15
    .lobytes entry_CLOSEFILE ; close_file = 16
    .lobytes entry_FINDFIRST ; find_first = 17
    .lobytes entry_FINDNEXT ; find_next = 18
    .lobytes entry_DELETEFILE ; delete_file = 19
    .lobytes entry_READSEQUENTIAL ; read_sequential = 20
    .lobytes entry_WRITESEQUENTIAL ; write_sequential = 21
    .lobytes entry_CREATEFILE ; create_file = 22
    .lobytes entry_RENAMEFILE ; rename_file = 23
    .lobytes entry_GETLOGINBITMAP ; get_login_bitmap = 24
    .lobytes entry_GETDRIVE ; get_current_drive = 25
    .lobytes entry_SETDMAADDRESS ; set_dma_address = 26
    .lobytes entry_GETALLOCATIONBITMAP ; get_allocation_bitmap = 27
    .lobytes entry_SETDRIVEREADONLY ; set_drive_readonly = 28
    .lobytes entry_GETREADONLYBITMAP ; get_readonly_bitmap = 29
    .lobytes unimplemented ; set_file_attributes = 30
    .lobytes entry_GETDPB ; get_DPB = 31
    .lobytes entry_GETSETUSER ; get_set_user_number = 32
    .lobytes unimplemented ; read_random = 33
    .lobytes unimplemented ; write_random = 34
    .lobytes unimplemented ; compute_file_size = 35
    .lobytes unimplemented ; compute_random_pointer = 36
    .lobytes entry_RESETDISK ; reset_disk = 37
    .lobytes entry_GETBIOS ; get_bios = 38
    .lobytes unimplemented ; 39
    .lobytes unimplemented ; write_random_filled = 40
jumptable_hi:
    .hibytes entry_EXIT ;exit_program = 0
    .hibytes entry_CONIN ; console_input = 1
    .hibytes entry_CONOUT ; console_output = 2
    .hibytes entry_UNIMPLEMENTED ; aux_input = 3 UNSUPPORTED
    .hibytes entry_UNIMPLEMENTED ; aux_output = 4 UNSUPPORTED
    .hibytes entry_UNIMPLEMENTED ; printer_output = 5 UNSUPPORTED
    .hibytes entry_DIRECTIO ; direct_console_io = 6
    .hibytes entry_GETIOBYTE ; get_io_byte = 7 UNSUPPORTED
    .hibytes entry_UNIMPLEMENTED ; set_io_byte = 8 UNSUPPORTED
    .hibytes entry_WRITESTRING ; write_string = 9
    .hibytes entry_READLINE ; read_line = 10
    .hibytes entry_GETCONSOLESTATUS ; console_status = 11
    .hibytes entry_GETVERSION ; get_version = 12
    .hibytes entry_RESET ; reset_disks = 13
    .hibytes entry_LOGINDRIVE ; select_disk = 14
    .hibytes entry_OPENFILE ; open_file = 15
    .hibytes entry_CLOSEFILE ; close_file = 16
    .hibytes entry_FINDFIRST ; find_first = 17
    .hibytes entry_FINDNEXT ; find_next = 18
    .hibytes entry_DELETEFILE ; delete_file = 19
    .hibytes entry_READSEQUENTIAL ; read_sequential = 20
    .hibytes entry_WRITESEQUENTIAL ; write_sequential = 21
    .hibytes entry_CREATEFILE ; create_file = 22
    .hibytes entry_RENAMEFILE ; rename_file = 23
    .hibytes entry_GETLOGINBITMAP ; get_login_bitmap = 24
    .hibytes entry_GETDRIVE ; get_current_drive = 25
    .hibytes entry_SETDMAADDRESS ; set_dma_address = 26
    .hibytes entry_GETALLOCATIONBITMAP ; get_allocation_bitmap = 27
    .hibytes entry_SETDRIVEREADONLY ; set_drive_readonly = 28
    .hibytes entry_GETREADONLYBITMAP ; get_readonly_bitmap = 29
    .hibytes unimplemented ; set_file_attributes = 30
    .hibytes entry_GETDPB ; get_dpb = 31
    .hibytes entry_GETSETUSER ; get_set_user_number = 32
    .hibytes unimplemented ; read_random = 33
    .hibytes unimplemented ; write_random = 34
    .hibytes unimplemented ; compute_file_size = 35
    .hibytes unimplemented ; compute_random_pointer = 36
    .hibytes entry_RESETDISK ; reset_disk = 37
    .hibytes entry_GETBIOS ; 38
    .hibytes unimplemented ; 39
    .hibytes unimplemented ; write_random_filled = 40
.endproc

; --- Misc ------------------------------------------------------------------

    .code
.proc entry_GETBIOS
    lda bios+0
    sta param+0
    ldx bios+1
    stx param+1
    rts
.endproc

.proc entry_GETVERSION
    lda #CPM_VERSION
    ldx #(CPM_MACHINE_TYPE<<4) | CPM_SYSTEM_TYPE
    rts
.endproc

.proc entry_GETIOBYTE
    lda #%10010100
    clc
    rts
.endproc

.proc entry_UNIMPLEMENTED
    sec
    rts
.endproc

; --- Console ---------------------------------------------------------------

    .code
.proc entry_CONIN
    lda buffered_key
    zif_eq
        jsr bios_CONIN
        tax
        jmp exit
    zendif
    ldx #0
    stx buffered_key
exit:
    txa
    pha
    cmp #31
    zif_cs
        jsr entry_CONOUT
    zendif
    rts
.endproc

    .code
; Prints the character in param+0.
.proc entry_CONOUT
    lda param+0
    ; fall through
.endproc
.proc internal_CONOUT
    pha
    jsr bios_CONST
    cmp #0
    zif_ne                  ; is there a key pending?
        jsr bios_CONIN      ; read it
        cmp #19             ; was it ^S?
        zif_eq
            jsr bios_CONIN  ; wait for another key press
            cmp #3
            beq reboot
            jmp continue
        zendif
        cmp #3              ; was it ^C?
        beq reboot
        sta buffered_key
    zendif
continue:
    pla
        
    ; Actually print it.

    jsr bios_CONOUT

    ; Compute column position?

    ldx column_position
    cmp #8
    beq backspace
    cmp #127
    beq backspace
    cmp #9
    zif_eq
        inx
        tax
        and #<~7
        sta column_position
        rts
    zendif
    cmp #32
    bcc zero_column
    inx
    jmp exit

backspace:
    dex
    bpl exit
zero_column:
    ldx #0
exit:
    stx column_position
    rts
reboot:
    jmp entry_EXIT
.endproc

.proc entry_GETCONSOLESTATUS
    lda buffered_key
    zif_eq
        jsr bios_CONST
    zendif
    clc
    rts
.endproc

; If param+0 == $ff, returns a character without waiting and without echo.
; If param+0 != $ff, prints it.

.proc entry_DIRECTIO
    lda param+0
    cmp #$ff
    zif_ne
        jsr bios_CONOUT
        clc
        rts
    zendif

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
.endproc

.proc entry_WRITESTRING
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
.endproc

; Read a line from the keyboard. Buffer is at param, size at param+0.
.proc entry_READLINE
    start_column_position = temp+0
    buffer_pos = temp+1
    buffer_max = temp+2
    count = temp+3
    current_column_position = temp+4

    lda column_position
    sta start_column_position
    sta current_column_position
    lda #1
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
            cpy #1
            zif_ne
                dec z:buffer_pos
                dec current_column_position
                jsr bios_CONOUT
            zendif
            zcontinue
        zendif
        
        ; Reboot?

        cmp #3
        zif_eq
            ldy buffer_pos
            cpy #1
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

            lda #1
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
                ldy z:buffer_pos
                sta (param), y
                jsr bios_CONOUT
                inc z:buffer_pos
                inc current_column_position
            zendif
        zendif
    zendloop

    lda #13
    jsr internal_CONOUT
    ldy #0
    ldx buffer_pos
    dex
    txa
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
.endproc

; --- Reset disk system -----------------------------------------------------

    .code
.proc entry_RESET
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
.endproc

; Reset the write-protect bits for the drives the user asked for.

.proc entry_RESETDISK
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
.endproc

.proc entry_GETDRIVE
    lda current_drive
    sta param+0
    rts
.endproc

.proc entry_GETSETUSER
    clc
    lda param+0
    zif_mi
        lda current_user
        rts
    zendif
    sta current_user
    rts
.endproc

.proc entry_SETDMAADDRESS
    lda param+0
    sta user_dma+0
    lda param+1
    sta user_dma+1
    rts
.endproc

; --- Open a file -----------------------------------------------------------

; Opens a file; the FCB is in param.
; Returns C is error; the code is in A.

entry_OPENFILE:
    jsr new_user_fcb
.proc internal_OPENFILE
    lda #fcb::s2+1              ; match 15 bytes of FCB
    jsr find_first
    zif_cc
        ; We have a matching dirent!

        ldy #fcb::ex
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

        ; Compare the user extent byte with the dirent.

        ldy #fcb::ex
        lda (param), y
        cmp tempb                   ; C if ex >= tempb
        zif_ne
            lda #$00                ; after the end of the file, record count empty
            zif_cs
                ; user extent is smaller
                lda #$80            ; middle of the file, record count full
            zendif
            ldy #fcb::rc
            sta (param), y            ; set extent record count
        zendif

        ; Set the FCB extent to what the user originally asked for,
        ; and not the value in the dirent.

        lda tempb
        ldy #fcb::ex
        sta (param), y

        clc
    zendif
    rts
.endproc
    
; Creates a file; the FCB is in param.
; Returns C is error; the code is in A.

entry_CREATEFILE:
    jsr new_user_fcb
.proc internal_CREATEFILE
    jsr check_disk_writable

    ; Check to see if the file exists.

    lda #fcb::s2+1
    jsr find_first
    bcc error

    ; Clear the allocation buffer in the FCB.

    lda #0
    ldy #fcb::al
    zrepeat
        sta (param), y
        iny
        cpy #fcb::al+16
    zuntil_eq

    ; Search for an empty dirent.

    lda #$e5
    ldy #fcb::dr
    sta (param), y
    lda #fcb::dr+1
    jsr find_first
    bcs error

    ; We found an empty dirent! Copy the user's FCB into it.

    ldy #1
    zrepeat
        lda (param), y
        sta (current_dirent), y
        iny
        cpy #fcb::al+16
    zuntil_eq
    
    ; Set the user code correctly.

    lda current_user
    ldy #fcb::dr
    sta (current_dirent), y
    
    ; We might have extended the directory, so make sure
    ; the count is updated.

    jsr update_cdrmax

    ; Write the update directory buffer back to disk. find_next left all
    ; the pointers set correctly for this to work.

    jsr write_sector

    ; Set bit 7 of S2 in the FCB to indicate that this file hasn't been
    ; modified.

    jsr fcb_is_not_modified

    clc
    rts

error:
    lda #$ff                ; only defined error code
    sec
    rts
.endproc

; Sets up a user-supplied FCB.

.proc new_user_fcb
    ldy #fcb::s2
    lda #0
    sta (param), y
.endproc
    ; falls through

; Selects the drive referred to in the FCB.

.proc convert_user_fcb
    ldy #fcb::dr
    lda (param), y              ; get drive byte
    sta old_fcb_drive           ; to restore on exit
    and #%00011111              ; extract drive
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
.endproc

; --- Close a file (flush the FCB to disk) ----------------------------------

entry_CLOSEFILE:
    jsr convert_user_fcb
.proc internal_CLOSEFILE
    jsr check_disk_writable

    ; Check that this FCB has actually changed.

    ldy #fcb::s2
    lda (param), y
    zif_mi
        clc                     ; just return if not
        rts
    zendif

    ; Find the directory entry for this extent.

    lda #fcb::s2+1
    jsr find_first
    bcs exit

    ; Update the directory entry from the FCB.

    ldy #fcb::rc
    lda (param), y
    sta (current_dirent), y

    ; Merge the allocation maps.

    jsr merge_fcb_into_dirent
    bcs exit

    ; Write the dirent back to disk.

    jsr write_sector            ; sector number remains set up from find_first
    
    ; Mark the FCB as modified and exit.
    
    jsr fcb_is_not_modified
    clc
exit:
    rts
.endproc

; --- Other file manipulation -----------------------------------------------

.proc entry_DELETEFILE
    jsr convert_user_fcb

    ; Search for and destroy all files matching the filename.

    lda #fcb::t3+1
    jsr find_first
    zif_cc
        zrepeat
            ; Free all the blocks in the matching dirent.

            ldx #0
            jsr update_bitmap_for_dirent

            ; Now mark the dirent as deleted.

            lda #$e5
            ldy #fcb::dr
            sta (current_dirent), y
            jsr write_sector

            ; Get the next matching dirent.

            lda #fcb::t3+1
            jsr find_next
        zuntil_cs
    zendif

    rts
.endproc

.proc entry_RENAMEFILE
    jsr convert_user_fcb

    ; Rename all files matching the filename.

    lda #fcb::t3+1
    jsr find_first
    zif_cc
        zrepeat
            ; Replace the filename in the dirent with the new one.

            lda #fcb::f1
            sta temp+0      ; dirent index
            lda #16+fcb::f1
            sta temp+1      ; filename index
            zrepeat
                ldy temp+1
                lda (param), y

                ldy temp+0
                sta (current_dirent), y

                inc temp+0
                inc temp+1
                lda temp+0
                cmp #fcb::t3+1
            zuntil_eq

            ; Write back to disk.

            jsr write_sector

            ; Get the next matching dirent.

            lda #fcb::t3+1
            jsr find_next
        zuntil_cs
    zendif

    rts
.endproc

; --- Read next sequential record -------------------------------------------

.proc entry_READSEQUENTIAL
    jsr convert_user_fcb
.endproc
.proc internal_READSEQUENTIAL
    ldy #fcb::cr
    lda (param), y
    ldy #fcb::rc
    cmp (param), y
    zif_eq
        cmp #$80                ; is this extent full?
        bne eof                 ; no, we've reached the end of the file
            
        ; Move to the next extent.

        jsr close_extent_and_move_to_next_one
        bcs eof

        ; Open it.

        jsr internal_OPENFILE
        bcs eof
    zendif
    
    jsr get_fcb_block           ; get disk block value in XA
    beq eof
    jsr get_sequential_sector_number

    ; Move the FCB on to the next record, for next time.

    ; ldy #fcb::cr              ; still set from last time
    lda (param), y
    clc
    adc #1
    sta (param), y

    ; Actually do the read!

    jsr reset_user_dma
    jsr read_sector
    clc
    rts

eof:
    lda #1                      ; = EOF
    sec
    rts
.endproc

; Closes the current extent, and move to the next one, but doesn't open it.
; Sets C on error (like maximum file size).
.proc close_extent_and_move_to_next_one
    jsr internal_CLOSEFILE

    ldy #fcb::ex
    lda (param), y
    clc
    adc #1
    and #$1f
    sta (param), y
    zif_eq
        ldy #fcb::s2
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
    ldy #fcb::cr
    sta (param), y
    clc
    rts

eof:
    sec
    rts
.endproc

; Fetch the current block number in the FCB in XA.
; Returns Z if the block number is zero (i.e., there isn't one).
.proc get_fcb_block
    jsr get_fcb_block_index     ; gets index in Y
    ldx blocks_on_disk+1        ; are we a big disk?
    zif_ne                      ; yes
        lda (param), y
        iny
        ora (param), y          ; check for zero
        beq exit

        lda (param), y          ; high byte!
        tax
        dey
        lda (param), y          ; low byte
        rts
    zendif

exit:
    ldx #0
    lda (param), y              ; sets Z if zero
    rts
.endproc

; Set the current block number in the FCB to XA.
.proc set_fcb_block
    sta temp+0
    stx temp+1

    jsr get_fcb_block_index     ; gets index in Y
    lda temp+0                  ; store low byte
    sta (param), y
    ldx blocks_on_disk+1        ; are we a big disk?
    zif_ne                      ; yes
        iny
        lda temp+1
        sta (param), y
        rts
    zendif

    rts
.endproc

; Return offset to the current block in the FCB in Y.
.proc get_fcb_block_index
    ldy #fcb::cr                ; get current record
    lda (param), y

    ldx block_shift             ; get block index
    zrepeat
        lsr a
        dex
    zuntil_eq                   ; A = block index

    ldx blocks_on_disk+1        ; are we a big disk?
    zif_ne                      ; yes
        asl a                   ; blocks occupy two bytes
    zendif

    clc
    adc #fcb::al                ; get offset into allocation map
    tay
    rts
.endproc

; When closing the file, we want to merge the allocation map in the
; FCB with the one in the dirent.
.proc merge_fcb_into_dirent
    ldy #fcb::al                ; index into FCB/dirent
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
            cpy #fcb::al+16
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
        cpy #fcb::al+16
    zuntil_eq
    clc
    rts

merge_error:
    sec
    rts
.endproc

; Computes the sector number of the block in XA.  XA must not be zero.
.proc get_sequential_sector_number
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

    ldy #fcb::cr
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

    rts
.endproc

; --- Write the next sequential record --------------------------------------

.proc entry_WRITESEQUENTIAL
    jsr convert_user_fcb

    ldy #fcb::cr
    lda (param), y
    cmp #$80
    zif_eq                      ; is this extent full?
        ; Move to the next extent.

        jsr close_extent_and_move_to_next_one
        lda #2                  ; disk full
        bcs error

        ; Open it.

        ldy #fcb::rc            ; clear record count
        lda #0
        sta (param), y

        jsr internal_OPENFILE
        zif_cs
            ; Could not open new extent --- it must not exist.

            jsr internal_CREATEFILE
            lda #1              ; directory full
            bcs error
        zendif
    zendif
    
    jsr get_fcb_block           ; get disk block value in XA
    zif_eq
        jsr fcb_is_modified
        jsr allocate_unused_block
        jsr set_fcb_block
    zendif
    jsr get_sequential_sector_number

    ; Move the FCB on to the next record, for next time.

    ldy #fcb::cr
    lda (param), y
    clc
    adc #1
    sta (param), y

    ; If CR > RC, update RC.

    ldy #fcb::rc
    cmp (param), y
    zif_cs
        sta (param), y
        jsr fcb_is_modified
    zendif

    ; Actually do the write!

    jsr reset_user_dma
    jsr write_sector
    lda #0
    clc
    rts

error:
    sec
exit:
    rts
.endproc

.proc fcb_is_not_modified
    ldy #fcb::s2
    lda (param), y
    ora #$80
    sta (param), y
    rts
.endproc

.proc fcb_is_modified
    ldy #fcb::s2
    lda (param), y
    and #$7f
    sta (param), y
    rts
.endproc

; --- Directory scanning ----------------------------------------------------

; Find a dirent matching the user FCB.
; On entry, A is the number of significant bytes in the FCB to use when
; searching.
; Returns C on error.

.scope
::entry_FINDFIRST:
    jsr setup_fcb_for_find
    bcs find_error
    ; A = number of bytes to search
    jsr find_first
    jmp copy_result_of_find

::entry_FINDNEXT:
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
.endscope


; Returns the number of bytes to search.
.proc setup_fcb_for_find
    ldy #fcb::dr
    lda (param), y
    cmp #'?'
    zif_eq
        lda #fcb::dr+1          ; number of bytes to search
    zelse
        jsr convert_user_fcb
        bcs error

        ldy #fcb::ex
        lda (param), y
        cmp #'?'
        zif_eq                  ; get all extents?
            lda #0
            ldy #fcb::s2
            sta (param), y      ; clear module byte in FCB
        zendif

        lda #fcb::s2+1          ; number of bytes to search
    zendif
    clc
error:
    rts
.endproc

; This is used twice, so factor it out. That's not a lot, but it's strange it's
; happened twice.
.proc copy_directory_buffer_to_dma
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
.endproc

find_first:
    sta find_first_count
    jsr home_drive
    jsr reset_dir_pos
    ; fall through
.proc find_next
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
        ldy #dph::cdrmax
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
        cpy #fcb::s1            ; don't care about byte 13
        beq same_characters
        cpy #fcb::ex
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
.endproc
    
    .bss
find_first_count: .byte 0
    .code

; --- Login drive -----------------------------------------------------------

; Logs in active_drive. If the drive was not already logged in, the bitmap
; is recomputed. In all cases the drive is selected.

.proc entry_LOGINDRIVE
    lda param+0
.endproc
.proc internal_LOGINDRIVE
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

    lda bitmap+0
    sta temp+2
    lda bitmap+1
    sta temp+3

    ldy #0
    zrepeat
        tya
        sta (temp+2), y         ; zero a byte

        inc temp+2              ; advance pointer
        zif_eq
            inc temp+3
        zendif

        lda temp+0              ; decrement count
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

    lda bitmap+0
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
    ldy #dph::cdrmax+0
    sta (dph), y
    iny
    sta (dph), y

    ; Actually read the disk.

    jsr home_drive
    jsr reset_dir_pos
    zloop
        jsr read_dir_entry
        jsr check_dir_pos
        beq exit

        ldy #0
        lda (current_dirent), y
        cmp #$e5                    ; is this directory entry in use?
        zbreakif_eq

        ldx #1
        jsr update_bitmap_for_dirent
        jsr update_cdrmax
    zendloop

exit:
    rts
.endproc

; Reads the next directory entry.

.proc read_dir_entry
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
        ldy #bios::setdma
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
.endproc

; Updates the cdrmax field in the DPH to mark the maximum directory
; entry for a drive (from directory_pos).
.proc update_cdrmax
    ldy #dph::cdrmax
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
.endproc

; Marks a dirent's blocks as either used or free in the bitmap.
; X=1 to mark as used, X=0 to mark as free.
.proc update_bitmap_for_dirent
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
.endproc

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

get_bitmap_status:
    jsr get_bitmap_location
    tax
    ldy #0
    lda (temp+0), y
    jmp rotater8

; Given a block number in temp+0 and a single-bit block status in A,
; sets it.

update_bitmap_status:
    sta @value
    jsr get_bitmap_location
    sta @bitpos
    tax

    ldy #0
    lda (temp+0), y
    jsr rotater8            ; get rotated status
    and #$fe                ; mask off bit we care about
@value = *+1
    ora #$00                ; or in the new status
@bitpos = *+1
    ldx #$00
    jsr rotatel8            ; unrotate
    ldy #0
    sta (temp+0), y         ; update bitmap
    rts

; Finds an unused block from the bitmap and allocates it. Returns it in XA.

.proc allocate_unused_block
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
.endproc

; Sets a drive as being readonly.

.proc entry_SETDRIVEREADONLY
    lda #<write_protect_vector
    ldx #>write_protect_vector
    ldy current_drive
    jsr setbit
    clc
    rts
.endproc

; Returns the login bitmap in XA.

.proc entry_GETLOGINBITMAP
    lda login_vector+0
    ldx login_vector+1
    clc
    rts
.endproc

; Returns the readonly bitmap in XA.

.proc entry_GETREADONLYBITMAP
    lda write_protect_vector+0
    ldx write_protect_vector+1
    rts
.endproc

; Returns a pointer to the allocation bitmap in XA.

.proc entry_GETALLOCATIONBITMAP
    lda bitmap+0
    ldx bitmap+1
    clc
    rts
.endproc

; Returns a pointer to the current drive's DPB.

.proc entry_GETDPB
    lda current_dpb+0
    ldx current_dpb+1
    clc
    rts
.endproc

; --- Drive management ------------------------------------------------------

reset_user_dma:
    lda user_dma+0
    ldx user_dma+1
    ldy #bios::setdma
    jmp callbios

set_current_sector:
    lda #<current_sector
    ldx #>current_sector
    ldy #bios::setsec
    jmp callbios

read_sector:
    jsr set_current_sector
    ldy #bios::read
    jmp callbios

write_sector:
    jsr set_current_sector
    ldy #bios::write
    jmp callbios

; Calculates the block and sector addresses of the dirent in
; directory_pos.

calculate_dirent_sector:
    lda directory_pos+0
    ldx directory_pos+1
    ldy #2
    jsr shiftr                  ; 4 dirents per sector
    sta current_sector+0
    stx current_sector+1
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
    beq @yes                ; bytes are the same
    ldx #1
    rts
@yes:
    inx
    rts

.proc home_drive
    lda #0
    ldy #2
    zrepeat
        sta current_sector, y
        dey
    zuntil_mi
    rts
.endproc

.proc select_active_drive
    lda active_drive
    ldy #bios::seldsk
    jsr callbios
    zif_cc
        ; Copy DPH into local storage.

        sta dph+0
        stx dph+1

        ldy #dph::dirbuf
        ldx #0
        zloop
            lda (dph), y
            sta directory_buffer, x
            iny
            inx
            cpy #dph::alv+2
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
.endproc
    
.proc check_disk_writable
    rts
.endproc

; --- Utilities -------------------------------------------------------------

; Shifts XA right Y bits.
; Uses temp. Leaves the shifted value in temp+0.

shiftr:
    sta temp+0
    stx temp+1
shiftr_temp0:
    iny
@loop:
    dey
    beq shift_exit
    clc
    ror temp+1
    ror temp+0
    jmp @loop
shift_exit:
    lda temp+0
    ldx temp+1
    rts
    
; Shifts XA left Y bits.
; Uses temp. Leaves the shifted value in temp+0.

shiftl:
    sta temp+0
    stx temp+1
    iny
@loop:
    dey
    beq shift_exit
    clc
    rol temp+0
    rol temp+1
    jmp @loop

; Sets bit Y of (XA).
; Uses temp.

setbit:
    sta temp+2
    stx temp+3

    lda #1
    ldx #0
    jsr shiftl      ; shift it left by Y

    ldy #1
:
    lda (temp+2), y
    ora temp+0, y
    sta (temp+2), y
    dey
    bpl :-

    rts

; Rotate A right X times.
rotater8:
    inx
@loop:
    dex
    beq @exit
    lsr a
    bcc :+
    ora #$80
:
    jmp @loop
@exit:
    rts

; Rotate A left X times.
rotatel8:
    inx
@loop:
    dex
    beq @exit
    asl a
    adc #0
    jmp @loop
@exit:
    rts
    
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
    ldy #bios::conout
    jmp callbios

bios_CONIN:
    ldy #bios::conin
    jmp callbios

bios_CONST:
    ldy #bios::const
    jmp callbios

bios_GETTPA:
    ldy #bios::gettpa
    jmp callbios

bios_GETZP:
    ldy #bios::getzp
    jmp callbios

bios_SETDMA:
    ldy #bios::setdma
    jmp callbios

; Prints a string.

pdebug:
    sta debuga
    stx debugx
    sty debugy

    tsx
    lda $101, x
    sta debugp1+0
    lda $102, x
    sta debugp1+1

@loop:
    inc debugp1+0
    bne :+
    inc debugp1+1
:
    ldy #0
    lda (debugp1), y
    beq @exit

    jsr bios_CONOUT
    jmp @loop

@exit:
    pla
    pla

    lda debugp1+1
    pha
    lda debugp1+0
    pha

    lda debuga
    ldx debugx
    ldy debugy
    rts

    .bss

; State preserved between BDOS invocations.

current_drive:  .byte 0     ; current working drive
current_user:   .byte 0     ; current working user

; State used by BDOS invocation. Reset to zero every time the BDOS
; is initialised.

bdos_state_start:
active_drive:           .byte 0 ; drive currently being worked on
old_drive:              .byte 0 ; if the drive has been overridden by the FCB
old_fcb_drive:          .byte 0 ; drive in user FCB on entry
write_protect_vector:   .word 0
login_vector:           .word 0
directory_pos:          .word 0
user_dma:               .word 0
current_sector:         .res 3  ; 24-bit sector number

buffered_key:           .byte 0
output_paused:          .byte 0 ; top bit set if paused
column_position:        .byte 0
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

debuga:             .byte 0
debugx:             .byte 0
debugy:             .byte 0

; vim: filetype=asm sw=4 ts=4 et

