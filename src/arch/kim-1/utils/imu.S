; ---------------------------------------------------------------------------
;
; Image Manipulation Utility
;
; Copyright (C) 2025 Eduardo Casino
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; ---------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"
#include "k-1013.inc"

ZEROPAGE

string:         .fill 2             ; Pointer for file name operations
buffer1:        .fill 2             ; Read/Write buffer for disk operations
filename1:      .fill 2             ; Pointer to 1st file name
filename2:      .fill 2             ; Pointer to 2nd file name

    .bss

; Uninitialized program variables

drive:          .fill 1             ; Zero-based drive number
drive_letter:   .fill 1
rn_flag:        .fill 1             ; non-zero if a move/rename operation

    .data

; Initialized variables

cmdline_index:  .byte 0
ro_flag:        .byte 0             ; Read-only flag
mn_flag:        .byte 0             ; Image mounted flag
pk_flag:        .byte 0             ; Create packed image flag
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
; At exit, Y points to the first position in DISK_BUFFER after
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

zproc init

    lda #<DISK_BUFFER
    sta buffer1+0
    lda #>DISK_BUFFER
    sta buffer1+1

    ; Put the disk controller in a sane state
    ;
    lda HSRC                        ; Test if an interrupt is pending
    zif_pl
        jsr fdc_exec_senseint
    zendif

    lda #0                          ; Set DMA read mode, unprotect SYSRAM
    sta HSRC

    ; Using a harmless command to check extended cmds support

    ldy #EXT_CMD_DIR
    jsr fdc_exec_extended           ; Get SD card directory listing
    zif_cc
        ; Dig further for errors
        lda disk_status
        zif_pl
            clc
            rts
        zendif
        lda #<real_msg              ; Extended commands not supported
        ldx #>real_msg
    zelse
        lda #<fdc_msg               ; Controller error
        ldx #>fdc_msg
    zendif

    jsr err_withmsg
    sec
    rts
zendproc

; Check if drive exists. Returns C if not.
;
zproc drive_exists
    lda drive
    cmp #4
    zif_cs    
        ldx drive_letter
        lda #<invalid_msg
        ldy #>invalid_msg
        jsr err_withchar
        sec
    zendif
    rts
zendproc

; Checks that the image name is valid
; Y must point to the first character of the
; image name in the command line
; C set if invalid
;
; Just checks that length < 64 chars, excluding
; terminating null. The firmware does proper
; validation
;
zproc check_valid_file

    ; Find end of file

    dey
    ldx #0xff
    zrepeat
        inx
        iny
        lda cpm_cmdline,y
        zbreakif_mi                 ; Safeguard, stop if len > 128 chars
    zuntil_eq

    ; Check it isG shorter that 64 chars, fail if not

    cpx #64
    zif_cs
        lda #<imagerr_msg           ; Cant be past the 64th pos
        ldx #>imagerr_msg
        jsr err_withmsg
        sec
    zendif
    rts
zendproc

; Produces a list on screen of available images
; 
zproc list_mounts

    ldy #EXT_CMD_MNTS
    jsr fdc_exec_extended           ; Get SD card directory listing
    zif_cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Set buffer for receiving file names

    lda #BUFFER_DMA
    sta ADMA

    zloop
        ldy #EXT_CMD_NXT_MNT
        jsr fdc_exec_extended       ; Get SD card directory entry
        zif_cs
            lda #<fdc_msg
            ldx #>fdc_msg
            jmp err_withmsg         ; Controller error
        zendif       

        ; Check status for errors

        lda disk_status
        and #ST4_NO_DATA
        zbreakif_ne

        jsr print_mount

    zendloop
    rts
zendproc

; Produces a list on screen of available images
; 
zproc list_images

    ; Set buffer for receiving file names

    lda #BUFFER_DMA
    sta ADMA

    zloop
        ldy #EXT_CMD_NXT
        jsr fdc_exec_extended       ; Get SD card directory entry
        zif_cs
            lda #<fdc_msg
            ldx #>fdc_msg
            jmp err_withmsg         ; Controller error
        zendif       

        ; No need to check for extended command support

        ; Check status for errors

        lda #ST4_NO_DATA
        bit disk_status
        ; Testing for ST4_NO_DATA
        zbreakif_ne
        ; Testing for ST4_ABNORMAL_TERM (0b0100000)
        zif_vs
            lda #<readdir_msg
            ldx #>readdir_msg
            jmp err_withmsg         ; Error reading directory
        zendif

        lda #<DISK_BUFFER           ; Print it
        ldx #>DISK_BUFFER
        ldy #BDOS_WRITE_STRING
        jsr BDOS
        jsr pr_crlf
    zendloop
    rts
zendproc

; Mount an SD image to a CPM drive
;
zproc mount_image

    lda #$01                        ; Set DMA direction bit to write
    sta HSRC          

    ; Set buffer for sending mount info

    lda #BUFFER_DMA
    sta ADMA

    lda ro_flag
    sta DISK_BUFFER+1
    lda drive
    sta DISK_BUFFER+0
    ora #EXT_CMD_MNT
    tay
    jsr fdc_exec_extended           ; Mount image
    zif_cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    lda #ST4_NOT_FOUND
    bit disk_status
    ; Testing for ST4_NOT_FOUND
    zif_ne
        lda filename1+0
        ldx filename1+1
        jmp err_notfound
    zendif
    zif_vs
        lda disk_status+1
        and #ST5_DRV_MOUNTED
        zif_ne
            ; Was not mounted
            ldx drive_letter
            lda #<mountederr_msg
            ldy #>mountederr_msg
            jmp err_withchar
        zendif
        lda disk_status+1
        and #ST5_IMG_MOUNTED
        zif_ne
            ; Was not mounted
            lda filename1+0
            ldx filename1+1
            jmp err_imgmounted
        zendif
        lda disk_status+1
        and #ST5_IMG_INVALID
        zif_ne
            ; It is not a valid IMD file
            lda filename1+0
            ldx filename1+1
            jmp err_invalidimg
        zendif
        ; If we are here, there was an unexpected error

        ldx drive_letter
        lda #<mounterr_msg
        ldy #>mounterr_msg
        jmp err_withchar
    zendif

    jmp print_mount                 ; Print the mount info

zendproc

; Unmount a drive.
;
zproc unmount_drive

    jsr get_drive
    zif_cs
        jmp err_usage
    zendif

    jsr drive_exists
    zif_cs
        rts
    zendif

    lda drive
    ora #EXT_CMD_UMNT               ; Unmount drive
    tay
    jsr fdc_exec_extended 
    zif_cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    and #ST4_ABNORMAL_TERM
    zif_ne
        lda disk_status+1
        and #ST5_DRV_NOT_MOUNTED
        zif_ne
            ; Was not mounted
            ldx drive_letter
            lda #<notmntederr_msg
            ldy #>notmntederr_msg
            jmp err_withchar
        zendif

        ; If we are here, there was an unexpected error

        ldx drive_letter
        lda #<unmnterr_msg
        ldy #>unmnterr_msg
        jmp err_withchar
    zendif

    jmp inf_done
zendproc

; Update config to flash. Not yet supported
;
zproc save_config
    lda #<unknown_msg
    ldy #>unknown_msg
    jsr err_withchar
    jmp err_usage
zendproc


; Create an empty image on the SD card.
;
zproc create_image

    jsr validate_image_name
    zif_cs
        rts
    zendif
    
    ; Set filename1
    ;
    ; NOTE: We can do this because DISK_BUFFER is page aligned!
    ;
    ldy #4                          ; Skip image parameters
    lda #>DISK_BUFFER
    sty filename1+0
    sta filename1+1

    jsr set_image_name              ; Copy image name at DISK_BUFFER,Y
                                    ; On exit, Y points to the next char after
                                    ; image name in command line
    jsr skip_sp
 
    cmp #0                          ; End of command line?
    zif_ne
        jsr get_option              ; No, get option
        zif_cs
            jmp err_usage           ; Syntax error
        zendif
        cpx #'P'                    ; Create packaged image
        zif_eq
            ldx #PACKAGED_IMG
            stx pk_flag
        zelse
            lda #<unknown_msg
            ldy #>unknown_msg
            jsr err_withchar        ; No other switches are supported
            jmp err_usage
        zendif
    zendif    

    jsr skip_sp

    cmp #0
    zif_ne
        jmp err_usage               ; Nothing else expected
    zendif

    lda #$01                        ; Set DMA direction bit to write
    sta HSRC          

    ; Set buffer for sending mount info

    lda #BUFFER_DMA
    sta ADMA

    ; Prepare the command data

    lda #77                         ; Tracks
    sta DISK_BUFFER+0
    lda #26                         ; Sectors
    sta DISK_BUFFER+1
    lda #1                          ; Sector size ( 1 == 256bytes )
    ora pk_flag                     ; Whether or not is a packaged image
    sta DISK_BUFFER+2
    lda #0xe5                       ; Filler byte
    sta DISK_BUFFER+3
    ldy #EXT_CMD_NEW                ; Create image
    jsr fdc_exec_extended
    zif_cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    lda disk_status
    and #ST4_ABNORMAL_TERM
    zif_ne
        lda #ST5_IMG_NAME
        bit disk_status+1
        ; Testing for ST5_IMG_NAME
        zif_ne
            lda #<imagerr_msg
            ldx #>imagerr_msg
            jmp err_withmsg
        zendif
        ; Testing for ST5_DISK_FULL (0b10000000)
        zif_mi
            lda #<diskfull_msg
            ldx #>diskfull_msg
            jmp err_withmsg
        zendif
        ; Testing for ST5_IMG_EXISTS ( 0b0100000)
        zif_vs
            lda #<exists_msg
            ldx #>exists_msg
            jmp err_withmsg
        zendif
        ; If we are here, there was an unexpected error
        lda #<generic_msg
        ldy #>generic_msg
        jmp err_withmsg
    zendif

    jmp inf_done
zendproc

; Delete file on the SD card
;
zproc delete_file
    jsr set_first_image_name
    zif_cs
        rts
    zendif

    cmp #0
    zif_ne
        jmp err_usage               ; Nothing else expected
    zendif

    lda #$01                        ; Set DMA direction bit to write
    sta HSRC          

    ; Set buffer for sending mount info

    lda #BUFFER_DMA
    sta ADMA

    ; Prepare the command data

    ldy #EXT_CMD_ERA                ; Delete image
    jsr fdc_exec_extended
    zif_cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    lda #ST4_NOT_FOUND
    bit disk_status
    ; Testing for ST4_NOT_FOUND
    zif_ne
        lda filename1+0
        ldx filename1+1
        jmp err_notfound
    zendif
    ; Testing for ST4_ABNORMAL_TERM (0b01000000)
    zif_vs
        lda disk_status+1
        and #ST5_IMG_NAME
        zif_ne
            ; Invalid image name
            lda #<imagerr_msg
            ldx #>imagerr_msg
            jmp err_withmsg
        zendif
        lda disk_status+1
        and #ST5_IMG_MOUNTED
        zif_ne
            ; Was not mounted
            lda filename1+0
            ldx filename1+1
            jmp err_imgmounted
        zendif
        ; If we are here, there was an unexpected error
        lda #<generic_msg
        ldy #>generic_msg
        jmp err_withmsg
    zendif

    jmp inf_done
zendproc

; Copy or rename src file to dst file on the SD card
;
zproc copy_or_move_file
    jsr set_first_image_name
    zif_cs
        rts
    zendif

    ; Set second file name into buffer

    jsr set_second_image_name
    zif_cs
        rts
    zendif

    cmp #0
    zif_ne
        jmp err_usage               ; Nothing else expected
    zendif

    lda #$01                        ; Set DMA direction bit to write
    sta HSRC          

    ; Set buffer for sending mount info

    lda #BUFFER_DMA
    sta ADMA

    ; Prepare the command data

    lda rn_flag
    zif_ne
        ldy #EXT_CMD_MOV            ; Move/rename image
    zelse
        ldy #EXT_CMD_CPY            ; Copy image
    zendif

    jsr fdc_exec_extended
    zif_cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    lda #ST4_NOT_FOUND
    bit disk_status
    ; Testing for ST4_NOT_FOUND
    zif_ne
        lda filename1+0
        ldx filename1+1
        jmp err_notfound
    zendif
    ; Testing for ST4_ABNORMAL_TERM (0b01000000)
    zif_vs
        lda #ST5_IMG_NAME
        bit disk_status+1
        ; Testing for ST5_IMG_NAME
        zif_ne
            lda #<imagerr_msg
            ldx #>imagerr_msg
            jmp err_withmsg
        zendif
        ; Testing for ST5_DISK_FULL (0b10000000)
        zif_mi
            lda #<diskfull_msg
            ldx #>diskfull_msg
            jmp err_withmsg
        zendif
        ; Testing for ST5_IMG_EXISTS ( 0b0100000)
        zif_vs
            lda #<exists_msg
            ldx #>exists_msg
            jmp err_withmsg
        zendif
        lda disk_status+1
        and #ST5_IMG_MOUNTED
        zif_ne
            ; Was not mounted
            lda filename1+0
            ldx filename1+1
            jmp err_imgmounted
        zendif
        lda disk_status+1
        and #ST5_IMG2_MOUNTED
        zif_ne
            ; Was not mounted
            lda filename2+0
            ldx filename2+1
            jmp err_imgmounted
        zendif
        ; If we are here, there was an unexpected error
        lda #<generic_msg
        ldy #>generic_msg
        jmp err_withmsg
    zendif

    jmp inf_done
zendproc

; Execute extended command
; Command number in Y

zproc fdc_exec_extended

    sty fdc_extended+2              ; Set command number 

    ldx #fdc_extended-fdc_commands  ; Command index into X
    jsr fdc_exec_command
    zif_cc
        zrepeat
            lda HSRC                ; Wait for interrupt
        zuntil_pl
    zendif
    ; Read results into memory even if it failed (should be
    ; unsupported command)
    ;
    jsr fdc_read_result
    rts
zendproc

zproc fdc_exec_senseint
    ; Wait until FDC interrupt

    zrepeat
        lda HSRC
    zuntil_pl

    ; Execute Sense Interrupt command

    ldx #fdc_senseint-fdc_commands
    jsr fdc_exec_command
    zif_cc
        ; Read results into memory

        jsr fdc_read_result
        zif_cc

            ; Look for error in the status registers

            lda disk_status         ; Check ST0
            and #0xf8               ; Delete don't care bits
            cmp #0x20               ; Result must be "Seek Completed"
            bne fdc_fail
            clc
        zendif
    zendif
    rts
zendproc

zproc fdc_fail
    sec
    rts
zendproc

zproc fdc_exec_command

    lda MSTR                        ; Load Main Status Register
    and #0x10                       ; Check if busy
    bne fdc_fail

    ldy fdc_commands, x             ; Load command length
    inx

    zloop
        zrepeat
            lda MSTR                ; Wait until RQM from controller
        zuntil_mi
        and #0x40                   ; Test data direction bit
        bne fdc_fail                ; Error if controller wants to talk

        lda fdc_commands, x         ; Get command byte
        sta DATR                    ; Store into FDC data register
        inx                         ; Next command byte
        dey
    zuntil_eq

    clc
    rts
zendproc

zproc fdc_read_result
    ldx #0
    zloop
        zrepeat
            lda MSTR                ; Wait until RQM from controller
        zuntil_mi
        and #0x40                   ; Test data direction bit
        beq fdc_fail                ; Error if controller wants to listen

        lda DATR                    ; Get status byte from data register
        sta disk_status, x          ; Put it into memory
        inx                         ; Next byte
        nop                         ; Give the controller time to update
        nop                         ; the MSTR with a valid busy status
        lda #0x10                   ; Check if busy and go get another
        and MSTR                    ; byte while so
    zuntil_eq

    clc
    rts
zendproc

; Error/Info message routines
;
zproc err_invalidimg
    sta string+0
    stx string+1
    lda #<invalidimg_msg
    ldx #>invalidimg_msg
    jsr pr_str
    lda string+0
    ldx string+1
    jsr pr_str
    lda #<invalidimg_msg2
    ldx #>invalidimg_msg2
    jmp pr_str
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

; FDC extended command

fdc_commands:

fdc_senseint:
    .byte 1                         ; Command length
    .byte 8                         ; Sense Interrupt Status

fdc_extended:
    .byte 2                         ; Command length
    .byte 0x1f                      ; Extended command
    .byte 0                         ; Command number

disk_status:    .fill 8             ; Result phase readouts from NEC-765

; Messages

usage_msg:      .ascii "Usage: imu [/L]\n\r"
                .ascii "       imu /M <drive> <image>[/O]\n\r"
                .ascii "       imu /U <drive>\n\r"
                .ascii "       imu /N <image> [/P]\n\r"
                .ascii "       imu /D <image>\n\r"
                .ascii "       imu {/C | /R} <src image> <dst image>\n\r\n\r"
                .byte 0

fdc_msg:        .ascii "Unexpected floppy controller failure.\n\r"
                .byte 0

real_msg:       .ascii "Not supported. Old firmware or real hardware.\n\r"
                .byte 0

diskfull_msg:   .ascii "SD card is full!\n\r"
                .byte 0

imagerr_msg:    .ascii "Image name invalid or longer than 63 chars.\n\r"
                .byte 0

open_msg:       .ascii "Failed to open directory.\n\r"
                .byte 0

readdir_msg:    .ascii "Failed to read directory.\n\r"
                .byte 0

invalidimg_msg: .ascii "Error: File '"
                .byte 0
invalidimg_msg2:.ascii "' is not a valid IMD image.\n\r"
                .byte 0

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

ro_msg:         .ascii "  (RO)\n\r"
                .byte 0

notfound_msg:   .ascii "Error: File '"
                .byte 0
notfound2_msg:  .ascii "' not found.\n\r"
                .byte 0

generic_msg:    .ascii "Can't complete operation.\n\r"
                .byte 0
                
exists_msg:     .ascii "File already exists.\n\r"
                .byte 0

imgmounted_msg: .ascii "Error: Image file '"
                .byte 0
imgmounted_msg2:.ascii "' already mounted.\n\r"
                .byte 0

warning_msg:    .ascii "Warning: About to delete file '"
                .byte 0
warning_msg2:   .ascii "'.\n"
                .ascii "Press Y to proceed, anything else to cancel: "
                .byte 0

abort_msg:      .byte 13,10
                .ascii "Aborted by user.\n\r"
                .byte 10

done_msg:       .ascii "Done.\n\r"
                .byte 0