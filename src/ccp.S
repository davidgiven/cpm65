; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65.inc"
#include "zif.inc"
#include "jumptables.inc"
#include "driver.inc"

ZEROPAGE

cmdoffset:  .byte 0 ; current offset into command line (including size bytes)
fcb:        .word 0 ; current FCB being worked on
temp:       .word 0
temp2:      .byte 0

zproc main
    tsx
    stx stackptr

    jsr bdos_GETDRIVE
    sta drive

    ; Try and open the $$$.SUB file.

    lda #<submit_fcb
    ldx #>submit_fcb
    jsr xfcb_open
    zif_cs
        lda #$ff
        sta submit_fcb+FCB_DR
    zendif

MAINLOOP:
    zloop
        ; Print prompt.

        lda #$ff
        jsr bdos_GETSETUSER
        tax
        zif_ne
            cmp #10
            zif_cs
                pha
                jsr printi
                .byte '1'|0x80
                pla
                ; carry left clear by printi
                adc #(-10) & 0xff
            zendif

            jsr print_hex4_number
        zendif

        lda drive
        clc
        adc #'A'
        jsr bdos_CONOUT

        lda #'>'
        jsr bdos_CONOUT

        ; Read command line.

        lda submit_fcb+FCB_DR
        zif_mi
            jsr read_command_from_keyboard
        zelse
            jsr read_command_from_submit_file
        zendif

        ; Zero terminate it.

        ldy cmdline+1
        lda #0
        sta cmdline+2, y

        ; Convert to uppercase.

        ldy #0
        zrepeat
            lda cmdline+2, y
            cmp #'a'
            zif_cs
                cmp #'z'+1
                zif_cc
                    and #$5f
                zendif
            zendif
            sta cmdline+2, y
            iny
            cpy cmdline+1
        zuntil_eq

        ; Empty command line?

        lda #2
        sta cmdoffset
        jsr skip_whitespace         ; leaves cmdoffset in X
        lda cmdline, x
        zcontinueif_eq

        ; Monitor command?

        cmp #'@'
        beq monitor_command

        ; Otherwise parse it as a normal command.

        lda #<cmdfcb
        ldx #>cmdfcb
        jsr parse_filename

        ; Decode.

        jsr decode_command
        jsr execute_command
    zendloop

    jmp bdos_EXIT

execute_command:
    tax
    lda commands_hi, x
    pha
    lda commands_lo, x
    pha
    rts
zendproc

commands_lo:
    jmptablo entry_DIR
    jmptablo entry_ERA
    jmptablo entry_TYPE
    jmptablo entry_FREE
    jmptablo entry_REN
    jmptablo entry_USER
    jmptablo entry_TRANSIENT
commands_hi:
    jmptabhi entry_DIR
    jmptabhi entry_ERA
    jmptabhi entry_TYPE
    jmptabhi entry_FREE
    jmptabhi entry_REN
    jmptabhi entry_USER
    jmptabhi entry_TRANSIENT

zproc monitor_command
    lda #0
    sta temp+0
    sta temp+1
    sta temp2
monitor_nextchar:
    zrepeat
        inc cmdoffset
        ldx cmdoffset
        lda cmdline, x
        zif_eq
            jmp MAINLOOP
        zendif

        cmp #' '
    zuntil_ne

    cmp #'A'
    zif_cs
        cmp #'F'+1
        zif_cc
            clc
            adc #(10 - 'A') & 0xff
            jmp monitor_digit
        zendif
    zendif

    cmp #'0'
    zif_cs
        cmp #'9'+1
        zif_cc
            sec
            sbc #'0'
            jmp monitor_digit
        zendif
    zendif

    cmp #'R'
    zif_eq
        jsr monitor_read
    monitor_exit:
        jsr newline
        jmp monitor_nextchar
    zendif

    cmp #'W'
    zif_eq
        jsr monitor_read
        jsr space
        ldy #0
        lda temp2
        sta (temp), y
        jsr print_hex_number
        jmp monitor_exit
    zendif

    cmp #'G'
    zif_eq
        jmp (temp)
    zendif
    
    jsr bdos_CONOUT
    lda #'?'
    jsr bdos_CONOUT
    jsr newline
    jmp MAINLOOP
        
monitor_read:
    lda temp+0
    ldx temp+1
    jsr print_hex16_number
    jsr space
    ldy #0
    lda (temp), y
    jsr print_hex_number
    rts

monitor_digit:
    ldx #3
    zrepeat
        asl temp+0
        rol temp+1
        rol temp2+2
        dex
    zuntil_mi
    ora temp+0
    sta temp+0
    jmp monitor_nextchar
zendproc

zproc read_command_from_keyboard
    ; Read from keyboard.

    lda #127
    sta cmdline
    lda #<cmdline
    ldx #>cmdline
    jsr bdos_READLINE
    jmp newline
zendproc

zproc read_command_from_submit_file
    ; Read from submit file.

    ldx submit_fcb+FCB_RC
    zif_eq
        ; File empty --- delete it.

        lda #<submit_fcb
        ldx #>submit_fcb
        jsr xfcb_erase

        ; Mark the submit file as not used.

        lda #$ff
        sta submit_fcb+FCB_DR

        jmp read_command_from_keyboard
    zendif

    ; Read the command.

    ; x = record count
    dex
    stx submit_fcb+FCB_CR

    lda #<cmdline
    ldx #>cmdline
    jsr bdos_SETDMA

    lda #<submit_fcb
    ldx #>submit_fcb
    jsr xfcb_readsequential

    ; Shorten the file.

    dec submit_fcb+FCB_RC     ; write back update record count
    lda submit_fcb+FCB_S2     ; mark FCB as modified
    and #$7f
    sta submit_fcb+FCB_S2

    lda #<submit_fcb
    ldx #>submit_fcb
    jsr xfcb_close

    ; Print the command.

    lda #0
    sta temp
    zloop
        ldx temp
        cpx cmdline+1
        zbreakif_eq

        lda cmdline+2, x
        jsr bdos_CONOUT

        inc temp
    zendloop
    jmp newline
zendproc

zproc parse_valid_userfcb
    lda #<userfcb
    ldx #>userfcb
    jsr parse_filename
    bcs invalid_filename
    rts
zendproc

zproc parse_valid_userfcb2
    lda #<(userfcb2)
    ldx #>(userfcb2)
    jsr parse_filename
    bcs invalid_filename
    rts
zendproc

zproc invalid_filename
    jsr printi
    .ascii "Invalid filenam"
    .byte 'e'|0x80
    bcc error           ; always taken
zendproc

zproc cannot_open
    jsr printi
    .ascii "Cannot open fil"
    .byte 'e'|0x80
    bcc error           ; always taken
zendproc

zproc bad_command
    jsr printi
    .ascii "Bad comman"
    .byte 'd'|0x80
    bcc error           ; always taken
zendproc

zproc no_room
    jsr printi
    .ascii "No roo"
    .byte 'm'|0x80
    bcc error           ; always taken
zendproc

; Prints the message in XA and returns to the main loop.

zproc error
    jsr newline
    ldx stackptr
    txs
    jmp MAINLOOP
zendproc

zproc entry_DIR
    file_counter = temp+2
    index = temp+3

    ; Parse the filename.

    jsr parse_valid_userfcb

    ; Just the drive?

    lda userfcb+FCB_F1
    cmp #' '
    zif_eq
        ; If empty FCB, fill with ????...

        ldx #10
        lda #'?'
        zrepeat
            sta userfcb+FCB_F1, x
            dex
        zuntil_mi
    zendif

    ; Set the drive.

    ldx userfcb+FCB_DR
    dex
    zif_mi
        ldx drive
    zendif
    txa
    jsr bdos_SELECTDISK

    ; Find number of files to print per line
    jsr set_dirlen

    ; Start iterating.

    lda #0
    sta file_counter

    lda #<cmdline
    ldx #>cmdline
    jsr bdos_SETDMA

    lda #<userfcb
    ldx #>userfcb
    jsr bdos_FINDFIRST
    zif_cs
        jmp newline
    zendif

    zrepeat
        ; Get the offset of the directory item.

        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<cmdline
        sta temp+0
        ldx #>cmdline
        zif_cs
            inx
        zendif
        stx temp+1

        ; Skip if this is a system file.

        ldy #FCB_T2
        lda (temp), y
        and #$80                ; check attribute bit
        zif_eq
            ; Line header.

            ldx file_counter
            txa
            inx
            stx file_counter
            cmp #$00
            zif_eq
                jsr bdos_GETDRIVE
                clc
                adc #'A'
                jsr bdos_CONOUT
            zendif

            lda #':'
            jsr bdos_CONOUT
            jsr space

            ; Print the filename.

            lda #8
            jsr print_filename_bytes

            ; Print the extension.

            lda #3
            jsr print_filename_bytes

            lda file_counter
            cmp dirlen
            zif_eq
                jsr newline
                lda #0 
                sta file_counter
            zendif
        zendif

        ; Get the next directory entry.

        lda #<userfcb
        ldx #>userfcb
        jsr bdos_FINDNEXT
    zuntil_cs
    jmp newline

; Prints A bytes at 'temp', followed by a space.
print_filename_bytes:
    sta index
    zrepeat
        inc temp+0
        zif_eq
            inc temp+1
        zendif

        ldy #0
        lda (temp), y
        and #$7f            ; mask off file status bits
        jsr bdos_CONOUT

        dec index
    zuntil_eq
    jmp space
zendproc

zproc entry_ERA
    jsr parse_valid_userfcb

    ; Just delete everything which matches.

    lda #<userfcb
    ldx #>userfcb
    jmp xfcb_erase
zendproc

zproc entry_TYPE
    jsr parse_valid_userfcb

    ; Open the FCB.

    lda #<userfcb
    ldx #>userfcb
    jsr xfcb_open
    zif_cs
        jmp cannot_open
    zendif

    ; Read and print it.

    zloop
        lda #<cmdline
        ldx #>cmdline
        jsr bdos_SETDMA

        lda #<userfcb
        ldx #>userfcb
        jsr xfcb_readsequential
        zbreakif_cs

        ldy #128
        sty temp
        zrepeat
            ldy temp
            lda cmdline-128, y
            cmp #26
            beq type_exit
            jsr bdos_CONOUT

            inc temp
        zuntil_eq
    zendloop
type_exit:
    jmp newline
zendproc

zproc entry_FREE
    jsr printi
    .ascii "MAIN: \xa0"

    lda #BANK_MAIN
    jsr bios_SETBANK

    jsr printsizes

    jsr printi
    .ascii "EXTRA:\xa0"

    lda #BANK_EXTRA
    jsr bios_SETBANK

    jsr printsizes

    jsr printi
    .ascii "BIOS\xa0"

    lda BIOS+1
    ldx BIOS+2
    jsr print_hex16_number

    jsr printi
    .ascii ", BDOS\xa0"

    lda BDOS+1
    ldx BDOS+2
    jsr print_hex16_number

    jsr printi
    .ascii ", CCP\xa0"

    lda #<(BDOS-4)
    ldx #>(BDOS-4)
    jsr print_hex16_number

    jsr printi
    .ascii ".\r\x8a"

    lda #BANK_MAIN
    jsr bios_SETBANK
    rts

printsizes:
    jsr printi
    .ascii "ZP\xa0"

    jsr bios_GETZP
    jsr print_zp_range

    jsr printi
    .ascii ". TPA\xa0"

    jsr bios_GETTPA
    jsr print_tpa_range

    jsr printi
    .ascii ". Free:\xa0"

    lda temp+1
    sec
    sbc temp+0
    jsr print_hex_number
    jsr print_00
    jmp newline

print_zp_range:
    sta temp+0
    stx temp+1
    jsr print_hex_number

    jsr printi
    .byte '-'|0x80

    lda temp+1
    jmp print_hex_number

print_tpa_range:
    sta temp+0
    stx temp+1
    jsr print_hex_number

    jsr printi
    .ascii "00"
    .byte '-'|0x80

    lda temp+1
    jsr print_hex_number
print_00:
    jsr printi
    .byte '0', '0'|0x80
    rts
zendproc

zproc entry_REN
    jsr parse_valid_userfcb2
    jsr parse_valid_userfcb

    lda userfcb+FCB_F1
    cmp #' '
    zif_ne
        lda userfcb2+FCB_F1
        cmp #' '
        zif_ne
            lda #<userfcb
            ldx #>userfcb
            jmp bdos_RENAME
        zendif
    zendif

    jsr printi
    .ascii "Bad filename"
    .byte 13, 10|0x80
    rts
zendproc

zproc entry_USER
    jsr parse_number
    zif_cc
        cmp #16
        zif_cc
            jmp bdos_GETSETUSER
        zendif
    zendif

    jsr printi
    .ascii "Bad number"
    .byte 13, 10|0x80
    rts
zendproc

zproc entry_TRANSIENT
    ; Check for drive changes.

    lda cmdfcb + FCB_F1
    cmp #' '
    zif_eq
        lda cmdfcb + FCB_DR
        zif_ne
            sec
            sbc #1
            sta drive

            jmp bdos_SELECTDISK
        zendif
    zendif

    ; If there's no .COM extension, add one.

    lda cmdfcb + FCB_T1
    cmp #' '
    zif_eq
        ldy #2
        zrepeat
            lda com, y
            sta cmdfcb + FCB_T1, y
            dey
        zuntil_mi
    zendif

    ; Open the command.

    lda #<cmdfcb
    ldx #>cmdfcb
    jsr xfcb_open
    zif_cs
        ldy #0
        zrepeat
            lda cmdfcb + FCB_F1, y
            cmp #' '
            zbreakif_eq
            iny
            cpy #8
        zuntil_eq

        lda #0
        sta cmdfcb + FCB_F1, y
        lda #<(cmdfcb + FCB_F1)
        ldx #>(cmdfcb + FCB_F1)
        jsr bdos_WRITESTRING
        lda #'?'
        jsr bdos_CONOUT
        jmp newline
    zendif

    ; Compute the start address.

    jsr bios_GETTPA         ; leaves page number in A
    sta temp+1
    lda #0
    sta temp+0

    ; Read the first sector to get the header.

    jsr read_command_sector
    zif_cs
        jmp bad_command
    zendif
    lda #0
    sta temp+0              ; set pointer to beginning of file

    ; Check that there's room.

    jsr bios_GETTPA
    stx temp2
    ldy #COMHDR_TPA_USAGE
    clc
    adc (temp), y
    cmp temp2
    zif_cs
        jmp no_room
    zendif

    jsr bios_GETZP
    stx temp2
    ldy #COMHDR_ZP_USAGE
    clc
    adc (temp), y
    cmp temp2
    zif_cs
        jmp no_room
    zendif

    ; Read the file.

    lda #$80                ; this is always true
    sta temp+0
    zrepeat
        jsr read_command_sector
    zuntil_cs

    ; Relocate the file.

    jsr bios_GETTPA
    tax
    lda #0
    stx temp+1
    sta temp+0
    jsr bdos_SETDMA
    jsr bios_GETZP
    tax                     ; ZP base
    lda temp+1              ; memory page number
    jsr bios_RELOCATE

    ; Patch the BDOS jump instruction.

    ldy #COMHDR_BDOS+0
    lda BDOS+1
    sta (temp), y
    iny
    lda BDOS+2
    sta (temp), y

    ; Calculate address of the program's PBLOCK.

    lda #0
    sta temp+0              ; restore temp to beginning of program

    ldy #COMHDR_REL_OFFSET+1
    lda (temp), y
    tax
    dey
    lda (temp), y           ; XA = offset to PBLOCK

    sta temp+0
    stx temp+1

    ; Save command line position.

    jsr skip_whitespace
    lda cmdoffset
    pha

    ; Parse the command line into an FCB, if present.

    lda temp+0
    ldx temp+1
    jsr parse_filename           ; first parameter
    zif_cc
        lda temp+0
        clc
        adc #16
        ldx temp+1
        zif_cs
            inx
        zendif
        jsr parse_filename       ; second parameter
    zendif

    ; Copy the command line into the program's PBLOCK.

    pla                     ; get saved command line position
    sta cmdoffset
    tax
    ldy #XFCB__SIZE + 1
    zloop
        lda cmdline, x
        sta (temp), y
        zbreakif_eq
        inx
        iny
    zendloop

    txa                     ; set length of command line
    sec
    sbc cmdoffset
    ldy #XFCB__SIZE
    sta (temp), y

    ; Run.

    jsr bios_GETTPA         ; base address in A
    sta temp+1
    lda #COMHDR_ENTRY
    sta temp+0
    jsr calltemp

    ; Reload disk.

    jsr bdos_GETDRIVE
    sta drive
    rts

calltemp:
    jmp (temp)

read_command_sector:
    lda temp+0
    ldx temp+1
    jsr bdos_SETDMA
    lda #<cmdfcb
    ldx #>cmdfcb
    jsr bdos_READSEQUENTIAL
    bcs 1f

    lda temp+0
    eor #$80
    sta temp+0
    zif_eq
        inc temp+1
    zendif
    clc
1:
    rts

com:
    .ascii "COM"
zendproc

; Decodes the cmdfcb, checking for one of the intrinsic commands.
zproc decode_command
    ldx #0                  ; cmdtable index
    zrepeat
        ldy #0              ; FCB index
        zrepeat
            lda cmdtable, x
            cmp cmdfcb+FCB_F1, y
            bne next_command
            inx
            iny
            cpy #4
        zuntil_eq
        dex                 ; compensate for next_command
        lda cmdfcb+FCB_F5
        cmp #' '
        beq decode_command_exit
    next_command:
        txa
        and #<~3
        clc
        adc #4
        tax

        lda cmdtable, x
    zuntil_eq
decode_command_exit:
    txa
    lsr a
    lsr a
    rts

cmdtable:
    .ascii "DIR "
    .ascii "ERA "
    .ascii "TYPE"
    .ascii "FREE"
    .ascii "REN "
    .ascii "USER"
    .byte 0
zendproc

; Parses an 8-bit decimal number from the command line.
zproc parse_number
    jsr skip_whitespace

    lda #0
    sta temp+0

    ldx cmdoffset
    zloop
        lda cmdline, x
        beq parse_number_exit
        cmp #' '
        beq parse_number_exit

        cmp #'0'
        bcc parse_number_error
        cmp #'9'+1
        bcs parse_number_error

        sec
        sbc #'0'
        tay

        lda temp+0
        asl a
        sta temp+0
        asl a
        asl a
        clc
        adc temp+0
        sta temp+0

        tya
        clc
        adc temp+0
        sta temp+0

        inx
    zendloop

parse_number_exit:
    lda temp+0
    clc
    rts
parse_number_error:
    sec
    rts
zendproc

; Parses text at cmdoffset into the xfcb at XA, which becomes the
; current one.
zproc parse_filename
    sta fcb+0
    stx fcb+1
    jsr skip_whitespace

    ; Call the BDOS to actually parse it.

    lda fcb+0
    ldx fcb+1
    jsr bdos_SETDMA

    lda #<cmdline
    ldx #>cmdline
    clc
    adc cmdoffset
    zif_cs
        inx
    zendif
    ldy #BDOS_PARSEFILENAME
    jsr BDOS

    zif_cs
        rts
    zendif

    ; Update cmdoffset.

    sec
    sbc #<cmdline
    sta cmdoffset

    ; Set the user number field in the XFCB.

    lda #$ff
    jsr bdos_GETSETUSER
    ldy #XFCB_US
    sta (fcb), y

    clc
    rts
zendproc

; Leaves the updated cmdoffset in X.
zproc skip_whitespace
    ldx cmdoffset
    zloop
        lda cmdline, x
        cmp #' '
        zif_ne
            cmp #'='
            zbreakif_ne
        zendif
        inx
    zendloop
    stx cmdoffset
    rts
zendproc

; Prints a 16-bit hex number in XA.
zproc print_hex16_number
    pha
    txa
    jsr print_hex_number
    pla
    jmp print_hex_number
zendproc

; Prints an 8-bit hex number in A.
zproc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_hex4_number
    pla
print_hex4_number:
    and #$0f
    ora #'0'
    cmp #'9'+1
    zif_cs
        adc #6
    zendif
    pha
    jsr bdos_CONOUT
    pla
    rts
zendproc

; Prints an inline string terminated by a high bit.
; Leaves C clear (for convenience when doing branches).
zproc printi
    pla
    sta temp2+0
    pla
    sta temp2+1

    zrepeat
        ldy #1
        lda (temp2), y
        pha
        and #0x7f
        jsr bdos_CONOUT

        inc temp2+0
        zif_eq
            inc temp2+1
        zendif

        pla
    zuntil_mi

    lda temp2+1
    pha
    lda temp2+0
    pha
    clc
    rts
zendproc

; Sets number of files to print per line
; Defaults to 2 if no screen driver is available
zproc set_dirlen
    ; Find screen driver
    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV 
    jsr BIOS    

    ; Defailt to 2 files per line if no driver is found
    zif_cs
        lda #2
        sta dirlen
        rts
    zendif
    
    ; Get screen width and calculate number of files per line
    sta SCREEN+1
    stx SCREEN+2

    ldy #SCREEN_GETSIZE
    jsr SCREEN
    tax
    inx
    txa 
    lsr
    lsr
    lsr
    lsr
    sta dirlen
    rts 
zendproc

space:
    lda #' '
    jmp bdos_CONOUT

newline:
    lda #13
    jsr bdos_CONOUT
    lda #10
    jmp bdos_CONOUT

    .data

SCREEN:
    jmp 0

; Submit file FCB.
submit_fcb:
    .byte 1             ; A:
    .ascii "$$$     SUB" ; filename
    .byte 0, 0, 0, 0    ; metadata
    .fill 16            ; allocation map
    .byte 0             ; cr
    .byte 0, 0, 0       ; r
    .byte 0             ; user

NOINIT

stackptr: .fill 1           ; stack pointer on startup
drive:    .fill 1           ; current drive, 0-based
dirlen:   .fill 1           ; number of files to list per line
cmdline:  .fill 128         ; command line buffer
cmdfcb:   .fill XFCB__SIZE  ; FCB of command
userfcb:  .fill XFCB__SIZE  ; parameter FCB
userfcb2 = userfcb + 16

; vim: ts=4 sw=4 et filetype=asm

