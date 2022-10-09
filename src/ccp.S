; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "cpm65_llvm.inc"
#include "zif_llvm.inc"

ZEROPAGE

cmdoffset:  .byte 0 ; current offset into command line (not including size byte)
fcb:        .word 0 ; current FCB being worked on
temp:       .word 0

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
        cmp #0
        zif_ne
            jsr print_dec_number
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

        ldy cmdline
        lda #0
        sta cmdline+1, y

        ; Convert to uppercase.

        ldy #0
        zrepeat
            lda cmdline+1, y
            cmp #'a'
            zif_cs
                cmp #'z'+1
                zif_cc
                    and #$5f
                zendif
            zendif
            sta cmdline+1, y
            iny
            cpy cmdline
        zuntil_eq

        ; Empty command line?

        lda #0
        sta cmdoffset
        jsr skip_whitespace         ; leaves cmdoffset in X
        lda cmdline+1, x
        zcontinueif_eq
    
        ; Parse it.

        lda #<cmdfcb
        ldx #>cmdfcb
        jsr parse_fcb

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
    .byte (entry_DIR - 1)@mos16lo
    .byte (entry_ERA - 1)@mos16lo
    .byte (entry_TYPE - 1)@mos16lo
    .byte (entry_FREE - 1)@mos16lo
    .byte (entry_REN - 1)@mos16lo
    .byte (entry_USER - 1)@mos16lo
    .byte (entry_TRANSIENT - 1)@mos16lo
commands_hi:
    .byte (entry_DIR - 1)@mos16hi
    .byte (entry_ERA - 1)@mos16hi
    .byte (entry_TYPE - 1)@mos16hi
    .byte (entry_FREE - 1)@mos16hi
    .byte (entry_REN - 1)@mos16hi
    .byte (entry_USER - 1)@mos16hi
    .byte (entry_TRANSIENT - 1)@mos16hi

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

        jsr remove_sub_file

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

    ldx submit_fcb+FCB_RC     ; write back update record count
    dex
    stx submit_fcb+FCB_RC
    lda submit_fcb+FCB_S2     ; mark FCB as modified
    and #$7f
    sta submit_fcb+FCB_S2

    lda #<cmdline
    ldx #>cmdline
    jsr xfcb_close

    ; Print the command.

    lda #0
    sta temp
    zloop
        ldx temp
        cpx cmdline+0
        zbreakif_eq

        lda cmdline+1, x
        jsr bdos_CONOUT

        inc temp
    zendloop
    jmp newline
zendproc

zproc remove_sub_file
    lda #<submit_fcb
    ldx #>submit_fcb
    jmp xfcb_erase
zendproc

zproc parse_valid_userfcb
    lda #<userfcb
    ldx #>userfcb
    jsr parse_fcb
    bcs invalid_filename
    rts
zendproc

zproc parse_valid_userfcb2
    lda #<(userfcb2)
    ldx #>(userfcb2)
    jsr parse_fcb
    bcs invalid_filename
    rts
zendproc

zproc invalid_filename
    lda #<1f
    ldx #>1f
    jmp error
1:
    .asciz "Invalid filename"
zendproc

zproc cannot_open
    lda #<1f
    ldx #>1f
    jmp error
1:
    .asciz "Cannot open file"
zendproc

; Prints the message in XA and returns to the main loop.

zproc error
    jsr bdos_WRITESTRING
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
            and #$01
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
            and #$01
            zif_eq
                jsr newline
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
    lda #<msg_zp
    ldx #>msg_zp
    jsr bdos_WRITESTRING

    jsr bios_GETZP
    sta temp+0
    stx temp+1
    jsr print_hex_number
    jsr print_to
    lda temp+1
    jsr print_hex_number
    jsr print_free
    lda temp+1
    sec
    sbc temp+0
    jsr print_hex_number
    jsr newline

    lda #<msg_tpa
    ldx #>msg_tpa
    jsr bdos_WRITESTRING

    jsr bios_GETTPA
    sta temp+0
    stx temp+1
    jsr print_hex_number
    jsr print_zero
    jsr print_to
    lda temp+1
    jsr print_hex_number
    jsr print_zero
    jsr print_free
    lda temp+1
    sec
    sbc temp+0
    jsr print_hex_number
    jsr print_zero
    jsr newline

    lda #<msg_ccp
    ldx #>msg_ccp
    jsr bdos_WRITESTRING

    lda #>BDOS
    jsr print_hex_number
    jsr print_zero
    jmp newline

print_zero:
    lda #0
    jmp print_hex_number

print_free:
    lda #<msg_free
    ldx #>msg_free
    jmp bdos_WRITESTRING

print_to:
    lda #<msg_to
    ldx #>msg_to
    jmp bdos_WRITESTRING

msg_zp:
    .asciz "ZP: "
msg_tpa:
    .asciz "TPA: "
msg_to:
    .asciz " to "
msg_free:
    .asciz ". Free: "
msg_ccp:
    .asciz "CCP at: "
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

    lda #<1f
    ldx #>1f
    jmp bdos_WRITESTRING
1:
    .ascii "Bad filename"
    .byte 13, 10, 0
zendproc

zproc entry_USER
    jsr parse_number
    zif_cc
        cmp #16
        zif_cc
            jmp bdos_GETSETUSER
        zendif
    zendif

    lda #<1f
    ldx #>1f
    jmp bdos_WRITESTRING
1:
    .ascii "Bad number"
    .byte 13, 10, 0
zendproc

zproc entry_TRANSIENT
    ; Check for drive changes.

    lda cmdfcb + FCB_F1
    cmp #' '
    zif_eq
        lda cmdfcb + FCB_DR
        zif_eq
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

    ; Read the file.

    zloop
        lda temp+0
        ldx temp+1
        jsr bdos_SETDMA
        lda #<cmdfcb
        ldx #>cmdfcb
        jsr bdos_READSEQUENTIAL
        zbreakif_cs

        lda temp+0
        eor #$80
        sta temp+0
        zif_eq
            inc temp+1
        zendif
    zendloop

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
    jsr parse_fcb           ; first parameter
    zif_cc
        lda temp+0
        clc
        adc #16
        ldx temp+1
        zif_cs
            inx
        zendif
        jsr parse_fcb       ; second parameter
    zendif

    ; Copy the command line into the program's PBLOCK.

    pla                     ; get save command line position
    sta cmdoffset
    tax
    ldy #XFCB__SIZE + 1
    zloop
        lda cmdline+1, x
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
        lda cmdline+1, x
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
zproc parse_fcb
    sta fcb+0
    stx fcb+1
    jsr skip_whitespace

    ; Set the user number field in the XFCB.

    lda #$ff
    jsr bdos_GETSETUSER
    ldy #XFCB_US
    sta (fcb), y

    ; Wipe FCB.

    ldy #FCB_DR
    tya
    sta (fcb), y                ; drive
    lda #' '
    zrepeat                     ; 11 bytes of filename
        iny
        sta (fcb), y
        cpy #FCB_T3
    zuntil_eq
    lda #0
    zrepeat                     ; 4 bytes of metadata
        iny
        sta (fcb), y
        cpy #FCB_RC+1
    zuntil_eq

    ; Check for drive.

    ldx cmdoffset
    lda cmdline+1, x            ; drive letter
    zif_eq
        clc
        rts
    zendif
    ldy cmdline+2, x
    cpy #':'                    ; colon?
    zif_eq
        sec
        sbc #'A'-1              ; to 1-based drive
        cmp #16
        zif_cs                  ; out of range drive
            rts
        zendif
        ldy #FCB_DR
        sta (fcb), y            ; store

        inx
        inx
    zendif

    ; Read the filename.

    ; x = cmdoffset
    ldy #FCB_F1
    zloop
        lda cmdline+1, x        ; get a character
        beq parse_fcb_exit      ; end of line
        cpy #FCB_F8+1
        zbreakif_eq
        jsr is_terminator_char
        bcs parse_fcb_exit
        cmp #'.'
        zbreakif_eq
        cmp #'*'
        zif_eq
            ; Turn "ABC*.X" -> "ABC?????.X"
            lda #'?'
            dex                 ; reread the * again next time
        zendif
        jsr is_valid_filename_char
        bcs return_with_carry
        sta (fcb), y
        iny
        inx
    zendloop
    ; A is the character just read
    ; X is cmdoffset

    ; Skip non-dot filename characters.

    zrepeat
        cmp #'.'
        zbreakif_eq
        jsr is_terminator_char
        bcs parse_fcb_exit
        jsr is_valid_filename_char
        bcs return_with_carry

        inx
        lda cmdline+1, x
    zuntil_eq
    ; A is the character just read
    ; X is cmdoffset

    ; Read the extension

    inx                         ; skip dot
    ldy #FCB_T1
    zloop
        lda cmdline+1, x        ; get a character
        beq parse_fcb_exit      ; end of line
        cpy #FCB_T3+1
        zbreakif_eq
        jsr is_terminator_char
        bcs parse_fcb_exit
        cmp #'*'
        zif_eq
            ; Turn "ABC.X*" -> "ABC.X*"
            lda #'?'
            dex                 ; reread the * again next time
        zendif
        jsr is_valid_filename_char
        bcs return_with_carry
        sta (fcb), y
        iny
        inx
    zendloop
        
    ; Discard any remaining filename characters.

    zrepeat
        jsr is_terminator_char
        zbreakif_cs
        jsr is_valid_filename_char
        bcs return_with_carry

        inx
        lda cmdline+1, x
    zuntil_eq

    ; Now A contains the terminating character --- either a space or \0.  We
    ; have a valid FCB!

parse_fcb_exit:
    stx cmdoffset               ; update cmdoffset
    clc
    rts

return_with_carry:
    sec
    rts

return_without_carry:
    clc
    rts

zproc is_terminator_char
    cmp #' '
    beq return_with_carry
    cmp #'='
    beq return_with_carry
    clc
    rts
zendproc

is_valid_filename_char:
    cmp #32
    bcc return_with_carry
    cmp #127
    bcs return_with_carry
    cmp #':'
    beq return_with_carry
    cmp #';'
    beq return_with_carry
    cmp #'<'
    beq return_with_carry
    cmp #'>'
    beq return_with_carry
    clc
    rts
zendproc

; Leaves the updated cmdoffset in X.
zproc skip_whitespace
    ldx cmdoffset
    zloop
        lda cmdline+1, x
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

; Prints an 8-bit decimal number in A.
zproc print_dec_number
    ldy #0
    sty zflag
    ldx #$ff
    sec
    zrepeat
        inx
        sbc #100
    zuntil_cc
    adc #100
    jsr digit

    ldx #$ff
    sec
    zrepeat
        inx
        sbc #10
    zuntil_cc
    adc #10
    jsr digit
    
    tax
digit:
    pha
    txa
    zflag = . + 1
    ora #0
    zif_ne
        txa
        ora #'0'
        jsr bdos_CONOUT
        inc zflag
    zendif
    pla
    rts
zendproc

; Prints an 8-bit hex number in A.
zproc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr h4
    pla
h4:
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

space:
    lda #' '
    jmp bdos_CONOUT

newline:
    lda #13
    jsr bdos_CONOUT
    lda #10
    jmp bdos_CONOUT

    .data

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
cmdline:  .fill 128         ; command line buffer
cmdfcb:   .fill XFCB__SIZE  ; FCB of command
userfcb:  .fill XFCB__SIZE  ; parameter FCB
userfcb2 = userfcb + 16

; vim: ts=4 sw=4 et filetype=asm

