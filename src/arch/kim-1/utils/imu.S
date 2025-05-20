; ---------------------------------------------------------------------------
;
; Image Manipulation Utility
;
; Copyright © 2025 Eduardo Casino
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; ---------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"

ZEROPAGE

    .global string, buffer1, filename1, filename2

string:         .fill 2             ; Pointer for file name operations
buffer1:        .fill 2             ; Read/Write buffer for disk operations
filename1:      .fill 2             ; Pointer to 1st file name
filename2:      .fill 2             ; Pointer to 2nd file name

    .bss

; Uninitialized program variables

    .global drive, drive_letter, rn_flag

drive:          .fill 1             ; Zero-based drive number
drive_letter:   .fill 1
rn_flag:        .fill 1             ; non-zero if a move/rename operation

    .data

; Initialized variables

    .global cmdline_index, ro_flag, mn_flag

cmdline_index:  .byte 0
ro_flag:        .byte 0             ; Read-only flag
mn_flag:        .byte 0             ; Image mounted flag

    .text

; Program entry point
; 
zproc main
    jsr init
    zif_cs
        rts
    zendif

    ; Look for switches in command line

    lda cpm_cmdline                 ; Get first parameter
    zif_eq
        jmp list_mounts             ; Empty, list mounted drives and exit
    zendif
    jsr get_option                  ; Get option switch
    zif_cs
        jmp err_usage               ; Syntax error
    zendif
    cpx #'M'
    zif_eq
        jmp mount_drive
    zendif
    cpx #'U'
    zif_eq
        jmp unmount_drive
    zendif
    cpx #'N'
    zif_eq
        jmp create_image
    zendif
    cpx #'D'
    zif_eq
        jmp delete_file
    zendif
    cpx #'C'
    zif_eq
        lda #0
        sta rn_flag                 ; Unset the "rename" flag
        jmp copy_or_move_file
    zendif
    cpx #'R'
    zif_eq
        lda #1
        sta rn_flag                 ; Set the "rename" flag
        jmp copy_or_move_file
    zendif
    cpx #'S'
    zif_eq
        jmp save_config
    zendif
    cpx #'L'
    zif_eq
        jmp list_images
    zendif
    cpx #'H'
    zif_eq
        jmp err_usage
    zendif
    lda #<unknown_msg
    ldy #>unknown_msg
    jsr err_withchar
    jmp err_usage
zendproc

; Skip spaces until next non-blank
; Returns character in A
;
zproc skip_sp
    ldy cmdline_index
    zloop
        lda cpm_cmdline,y
        cmp #' '
        zbreakif_ne
        iny
    zendloop
    sty cmdline_index

    rts
zendproc

; Process an option switch. Return value in A
; and advances to next non-blank character in command line.
; C set if error
;
zproc get_option

    ldy cmdline_index
    lda cpm_cmdline,y
    cmp #'/'
    zif_eq
        iny
        ldx cpm_cmdline,y
        zif_ne
            iny
            sty cmdline_index
            jsr skip_sp
            clc
            rts
        zendif
    zendif
    sec
    rts
zendproc

; Get drive number in base 0 and drive letter and
; advances to the next non-blank character in command line
; C set if error
;
zproc get_drive
    ; Get drive number in base 0 and drive letter
    
    ldy cmdline_index
    lda cpm_cmdline,y
    sta drive_letter
    cmp #'A'
    bcc 1f
    cmp #'['                        ; Past 'Z'
    bcs 1f
    sec
    sbc #'A'
    sta drive

    iny
    lda cpm_cmdline,y
    cmp #':'
    bne 1f
    iny
    sty cmdline_index
    jsr skip_sp

    clc
    rts
1:  sec
    rts
zendproc

; Check that there is a valid image name in the current
; position of the command line.
;
; C set if error
;
zproc validate_image_name

    ldx cmdline_index
    lda cpm_cmdline,x

    ; Check if there is an image name

    zif_eq
        jsr err_usage               ; If none, bad syntax
        sec
        rts
    zendif

    ; Next in cpm_cmdline is the image name

    jsr check_valid_file            ; Check for valid name format

    rts
zendproc

; Copies the image name from the command line into
; the mount info block (see print_mount below)
;
; At exit, cmdline_index points to the first character
; in cpm_cmdline after the image name
;
zproc set_image_name_for_mount

    ; Set filename1

    ldy #2                          ; Offset of file name in mount info block
    sty filename1+0
    lda buffer1+1
    sta filename1+1
zendproc
;
; Fall through
;
; Copies the image name from the command line into
; (buffer1),Y
;
; At exit, Y points to the first position in buffer1 after
; the null character.
;
zproc set_image_name
    ldx cmdline_index
    dey
    dex
    zrepeat
        inx
        iny
        lda cpm_cmdline,x
        sta (buffer1),y
        zbreakif_eq                 ; Stop when null or blank
        cmp #' '
    zuntil_eq
    lda #0                          ; null-terminate the string
    sta (buffer1),y
    stx cmdline_index
    iny
    rts
zendproc

; Validates and copies first image name from command line
; to buffer1. Sets filename1 and filename2
;
; Returns Carry set on error
;
zproc set_first_image_name
    jsr validate_image_name
    zif_cc
        ldy #0                      ; Offset of first file name in buffer
        sty filename1+0
        lda buffer1+1
        sta filename1+1
        sta filename2+1
        
        jsr set_image_name          ; Copy image name at (buffer1) 
                                    ; and sets filename1 and filename2        
        
        sty filename2+0

        jsr skip_sp
        clc
    zendif
    rts
zendproc

; Validates and copies second image name from command line
; to buffer1.
;
; Returns Carry set on error
;
zproc set_second_image_name
    jsr validate_image_name
    zif_cc
        ldy filename2
        jsr set_image_name          ; Copy second image name at (buffer1),y
        jsr skip_sp
        clc
    zendif
    rts
zendproc

; Prints info of a mounted drive. On entry, it
; expects the following info starting at buffer1:
;
;    drive     BYTE        ; Base 0
;    ro_flag   BYTE        ; Non-zero if RO
;    name      STRING      ; Null-terminated Image name
;
zproc print_mount
    ldy #0
    lda (buffer1),y
    clc
    adc #'A'                        ; Get drive letter
    sta mount_msg
    lda #<mount_msg                 ; And print it
    ldx #>mount_msg
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    lda #2                          ; Print image name. We can do this because
    ldx buffer1+1                   ; buffer1 is page aligned
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    ldy #1
    lda (buffer1),y                 ; Get RO flag
    zif_ne
        lda #<ro_msg                ; Print RO indicator
        ldx #>ro_msg
    zelse
        lda #<crlf
        ldx #>crlf
    zendif
    ldy #BDOS_WRITE_STRING
    jmp BDOS
zendproc

; Assign an image to a drive letter.
;
zproc mount_drive
    jsr get_drive
    zif_cs
        jmp err_usage
    zendif

    jsr drive_exists
    zif_cs
        rts
    zendif

    ; Check if there is an image name

    jsr validate_image_name
    zif_cs
        rts
    zendif

    ; Sets filename1 and copies the image name
    ; into the read/write buffer
    ;
    jsr set_image_name_for_mount

    jsr skip_sp

    ; Get options, if any

    cmp #0                          ; End of command line?
    zif_ne
        jsr get_option              ; No, get option
        zif_cs
            jmp err_usage           ; Syntax error
        zendif
        cpx #'O'                    ; Read-only switch
        zif_eq
            stx ro_flag             ; Any non-zero value is OK
        zelse
            lda #<unknown_msg
            ldy #>unknown_msg
            jsr err_withchar        ; No other switches are supported
            jmp err_usage
        zendif
    zendif    

    ldy cmdline_index
    lda cpm_cmdline,y
    zif_ne
        jmp err_usage               ; Nothing else expected
    zendif

    jmp mount_image                 ; Mount image on drive with enabled switches

zendproc

zproc pr_str
    ldy #BDOS_WRITE_STRING
    jmp BDOS
zendproc

zproc pr_crlf
    lda #<crlf
    ldx #>crlf
    jmp pr_str
zendproc

zproc err_withmsg
    sta string+0
    stx string+1
    lda #<error_msg
    ldx #>error_msg
    jsr pr_str
    lda string+0
    ldx string+1
    jmp pr_str
zendproc

zproc err_withchar
    sta string+0
    sty string+1
    stx errchar
    lda #<error_msg
    ldx #>error_msg
    jsr pr_str
    lda string+0
    ldx string+1
    jsr pr_str
    lda #<errchar_msg
    ldx #>errchar_msg
    jmp pr_str
zendproc

zproc err_usage
    lda #<usage_msg
    ldx #>usage_msg
    jmp pr_str
zendproc

zproc err_notfound
    sta string+0
    stx string+1
    lda #<notfound_msg
    ldx #>notfound_msg
    jsr pr_str
    lda string+0
    ldx string+1
    jsr pr_str
    lda #<notfound2_msg
    ldx #>notfound2_msg
    jmp pr_str
zendproc

zproc err_imgmounted
    sta string+0
    stx string+1
    lda #<imgmounted_msg
    ldx #>imgmounted_msg
    jsr pr_str
    lda string+0
    ldx string+1
    jsr pr_str
    lda #<imgmounted_msg2
    ldx #>imgmounted_msg2
    jmp pr_str
zendproc

zproc wrn_delete
    sta string+0
    stx string+1

    lda #<warning_msg
    ldx #>warning_msg
    jsr pr_str
    lda string+0
    ldx string+1
    jsr pr_str
    lda #<warning_msg2
    ldx #>warning_msg2
    jmp pr_str
zendproc

zproc inf_usrabort
    lda #<abort_msg
    ldx #>abort_msg
    jmp pr_str
zendproc

zproc inf_done
    lda #<done_msg
    ldx #>done_msg
    jmp pr_str
zendproc

    .data

; Messages

    .global unknown_msg, invalid_msg, mounterr_msg, mountederr_msg
    .global unmnterr_msg, notmntederr_msg, generic_msg, exists_msg

error_msg:      .ascii "Error: "
                .byte 0

errchar_msg:    .ascii " '"
errchar:        .byte 0
                .ascii "'."
crlf:           .byte 13,10,0

unknown_msg:    .ascii "Invalid option"
                .byte 0

invalid_msg:    .ascii "Invalid drive"
                .byte 0

mounterr_msg:   .ascii "Failed to mount drive"
                .byte 0

mountederr_msg: .ascii "Drive already mounted:"
                .byte 0

unmnterr_msg:   .ascii "Failed to unmount drive"
                .byte 0

notmntederr_msg:.ascii "Drive wasn't mounted:"
                .byte 0

mount_msg:      .byte 0
                .ascii ": -> "
                .byte 0

ro_msg:         .ascii "  (RO)\r\n"
                .byte 0

notfound_msg:   .ascii "Error: File '"
                .byte 0
notfound2_msg:  .ascii "' not found.\r\n"
                .byte 0

generic_msg:    .ascii "Can't complete operation.\r\n"
                .byte 0
                
exists_msg:     .ascii "File already exists.\r\n"
                .byte 0

imgmounted_msg: .ascii "Error: Image file '"
                .byte 0
imgmounted_msg2:.ascii "' already mounted.\r\n"
                .byte 0

warning_msg:    .ascii "Warning: About to delete file '"
                .byte 0
warning_msg2:   .ascii "'.\r\n"
                .ascii "Press Y to proceed, anything else to cancel: "
                .byte 0

abort_msg:      .byte 13,10
                .ascii "Aborted by user.\r\n"
                .byte 10

done_msg:       .ascii "Done.\r\n"
                .byte 0