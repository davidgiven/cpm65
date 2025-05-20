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
#include "parproto.inc"
#include "sdshield.inc"

ZEROPAGE

buffer2:        .fill 2             ; Read/Write buffer for disk operations

    .bss

; Uninitialized program variables

version:        .fill 1             ; SD Shield protocol version

    .text


zproc init

    ; Check the firmware version to make sure which features
    ; are supported. Note: Version info in firmware <=1.4
    ; is broken. Also, calling unsupported commands generate
    ; a deadlock, so we are relying here in an undocumented
    ; feature to retrieve the protocol version. This will
    ; be 1 for firmware <=1.X and 2 or greater for >=2.0

    ; Get the first free full page in memory and set buffer1
    ; and buffer2

    ldy #>cpm_ram
    ldx #<cpm_ram
    beq 1f
    ldx #0
    iny
1:  stx buffer1+0
    stx buffer2+0
    sty buffer1+1
    iny
    sty buffer2+1

    jsr GetProtoVersion
    sta version
    clc
    rts
zendproc

; Check if drive exists. Returns C if not.
;
zproc drive_exists
    lda #PC_GET_MAX
    jsr DiskGetDrives
    
    cmp drive
    zif cs
        zif ne
            clc
            rts
        zendif
    zendif
    ldx drive_letter
    lda #<invalid_msg
    ldy #>invalid_msg
    jsr err_withchar
    sec
    rts
zendproc

; Checks that the image name is valid
; Y must point to the first character of the
; image name in the command line
; C set if invalid
;
; Checks that it is an 8.3 file.
;
zproc check_valid_file

    ; Find the dot (or blank or end of file)

    dey
    ldx #0xff
    zrepeat
        inx
        iny
        lda cpm_cmdline,y    
        zbreakif eq
        cmp #'.'
        zbreakif eq
        cmp #' '
    zuntil eq

    ; Check it is between positions 1 and 8, fail if not

    cpx #1
    bcc 1f                          ; Cant be at the beginning
    cpx #9
    bcs 1f                          ; Cant be past the 9th pos

    ; End of file?

    cmp #'.'
    zif ne
        clc
        rts
    zendif

    ; Check the extension length

    ldx #0xff
    zrepeat
        inx
        iny
        lda cpm_cmdline,y
        zbreakif eq
        cmp #' '
    zuntil eq
    cpx #4
    bcc 2f                          ; Can't be greater than 3
1:  lda #<imagerr_msg
    ldx #>imagerr_msg
    jsr err_withmsg
    sec
2:  rts
zendproc

; Produces a list on screen of drive mounts
;
zproc list_mounts
    jsr DiskGetMounted              ; Get mounted drives
    jsr set_buffer                  ; Output to buffer1
    zloop
        jsr DiskNextMountedDrv      ; Get entry
        zbreakif cs                 ; No more
        jsr print_mount             ; Print it
    zendloop
    rts
zendproc

; Produces a list on screen of available images
; 
zproc list_images
    jsr DiskDir                     ; Get SD card directory listing
    zloop
        jsr set_buffer              ; Output to buffer1
        jsr DiskDirNext             ; Get entry
        zbreakif cs                 ; No more
        lda buffer1+0               ; Print it
        ldx buffer1+1
        ldy #BDOS_WRITE_STRING
        jsr BDOS
        jsr pr_crlf
    zendloop
    rts
zendproc

; Sets the buffer for sending/receiving data
;
zproc set_buffer
    lda buffer1+0
    sta zp_sds_buffer
    lda buffer1+1
    sta zp_sds_buffer+1
    rts
zendproc

; Sets second buffer for receiving data at the second page
; of the free ram
;
zproc set_buffer_two
    lda buffer2+0
    sta zp_sds_buffer+0
    ldy buffer2+1
    sty zp_sds_buffer+1
    rts
zendproc

; Mount an SD image to a CPM drive
;
zproc mount_image

    ; Check if drive is already mounted

    lda drive
    jsr DiskStatus
    and #1                          ; Mounted flag
    zif ne
        ; Drive is mounted
        ldx drive_letter
        lda #<mountederr_msg
        ldy #>mountederr_msg
        jmp err_withchar
    zendif

    ; Prepare the mount info block for printing the mount and
    ; load X and A for calling DiskMount
    ;
    ;    drive     BYTE        ; Base 0
    ;    ro_flag   BYTE        ; Non-zero if RO
    ;    name      STRING      ; Null-terminated Image name

    lda #2                          ; We can do this because buffer1
    sta zp_sds_buffer+0             ; is page aligned
    lda buffer1+1
    sta zp_sds_buffer+1
    ldy #1
    lda ro_flag
    sta (buffer1),y
    tax
    dey
    lda drive
    sta (buffer1),y

    jsr DiskMount                   ; Mount image

    zif cc
        ; All went well
        jmp print_mount             ; Print the mount info
    zendif

    ; If we are here, there was an error

    cmp #ERR_NOT_FOUND              ; Image not found?
    zif ne
        ; No, print generic mount error and exit
        ldx drive_letter
        lda #<mounterr_msg
        ldy #>mounterr_msg
        jmp err_withchar
    zendif

    lda filename1+0
    ldx filename1+1
    jmp err_notfound                ; Yes, print not found error and exit
zendproc

; Unmount a drive.
;
zproc unmount_drive
    
    jsr get_drive
    zif cs
        jmp err_usage
    zendif

    jsr drive_exists
    zif cs
        rts
    zendif

    ; Check if drive is already unmounted

    lda drive
    jsr DiskStatus
    and #1                          ; Mounted flag
    zif eq
        ; Was not mounted
        ldx drive_letter
        lda #<notmntederr_msg
        ldy #>notmntederr_msg
        jmp err_withchar
    zendif

    lda drive
    jsr DiskUnmount
    zif cs
        ; There was an unexpected error
        ldx drive_letter
        lda #<unmnterr_msg
        ldy #>unmnterr_msg
        jmp err_withchar
    zendif
    jmp inf_done
zendproc

; Update the SD config file with the latest mounted drives
; situation. Issues warning if the file could not be
; updated.
;
; Only for firmware >=2.0, as save config is broken in 1.X
;
zproc save_config
    lda #1
    cmp version
    zif cs
        jsr err_firmware            ; Protocol < 2
        sec
    zendif

    jsr inf_working                 ; It is a slow operation

    jsr SaveConfig
    zif cs
        lda #<config_msg
        ldx #>config_msg
        jmp err_withmsg
    zendif
    jsr inf_done
    rts
zendproc

; Check if an image is mounted.
;
; On entry, XA is pointer to image name to check
;
; On exit, mn_flag != 0 if mounted.
;
zproc is_image_mounted
    sta string+0
    stx string+1

    lda #0
    sta mn_flag

    jsr DiskGetMounted              ; Get mounted drives
    jsr set_buffer_two              ; Output to buffer2
    zloop
        jsr DiskNextMountedDrv      ; Get entry
        zbreakif cs                 ; No more
        ldy #0
        zrepeat
            lda (string),y
            iny
            iny
            cmp (buffer2),y         ; If different, go check next file
            zbreakif ne
            cmp #0                  ; Equal. End of file name?
            zif eq
                inc mn_flag
            zendif
            dey
            cmp #0                  ; Check if end of file name again
        zuntil eq
    zendloop
    rts
zendproc

; Common preamble of file manipulation functions
; Returns Carry set on error
;
zproc file_common

    ; Check the firmware version to make sure
    ; it is supported.

    lda #1
    cmp version
    zif cs
        jsr err_firmware            ; Protocol < 2
        sec
        rts
    zendif

    ; Check if there is an image name

    jmp set_first_image_name

zendproc

; Create an empty image on the SD card.
;
zproc create_image

    jsr file_common
    zif cs
        rts
    zendif

    ldy cmdline_index
    lda cpm_cmdline,y
    zif ne
        jmp err_usage               ; No more parameters expected
    zendif

    jsr inf_working                 ; It is a slow operation

    ; Prepare the disk parameter block for format. Beware the fields
    ; in this file parameter block have different meaning for this
    ; command!

    lda #TRACKS
    sta zp_sds_track
    lda #SECTORS_PER_TRACK
    sta zp_sds_sector
    lda #0xe5
    sta zp_sds_spt 
    jsr set_buffer                  ; Set buffer for image name at buffer1

    jsr DiskFormat                  ; Create image

    zif cs
        cmp #ERR_FILE_EXISTS
        zif eq
            lda #<exists_msg
            ldx #>exists_msg
            jmp err_withmsg
        zendif

        ; Anything else, generic error

        lda #<generic_msg
        ldx #>generic_msg
        jmp err_withmsg
    zendif
    
    jsr inf_done

    rts
zendproc

; Delete file on the SD card
;
zproc delete_file

    jsr file_common
    zif cs
        rts
    zendif

    ldy cmdline_index
    lda cpm_cmdline,y
    zif ne
        jmp err_usage               ; No more parameters expected
    zendif

    lda filename1+0
    ldx filename1+1
    jsr is_image_mounted            ; Check if file is a mounted image
    lda mn_flag
    zif ne
        lda filename1+0
        ldx filename1+1
        jmp err_imgmounted
    zendif

    ; Warn user and get confirmation

    lda filename1+0
    ldx filename1+1
    jsr wrn_delete
    ldy #BDOS_CONSOLE_INPUT
    jsr BDOS
    cmp #'y'
    zif ne
        jmp inf_usrabort
    zendif
    jsr pr_crlf

    jsr set_buffer                  ; Set buffer for image name at buffer1
    jsr DiskErase                   ; Delete file

    zif cs
        cmp #ERR_FEATURE_DISABLED   ; Disabled by hardware switch?
        zif eq
            lda #<disabled_msg
            ldx #>disabled_msg
            jmp err_withmsg
        zendif
        cmp #ERR_NOT_FOUND
        zif eq
            lda filename1+0
            ldx filename1+1
            jmp err_notfound
        zendif

        ; Anything else, generic error msg

        lda #<generic_msg
        ldx #>generic_msg
        jmp err_withmsg
    zendif
    jsr inf_done
    rts
zendproc

; Copy or rename src file to dst file on the SD card
;
zproc copy_or_move_file

    jsr file_common 
    zif cs
        rts
    zendif

    ; Set second file name into buffer

    jsr set_second_image_name
    zif cs
        rts
    zendif

    ldy cmdline_index
    lda cpm_cmdline,y
    zif ne
        jmp err_usage               ; Should be 0 (no more parameters)
    zendif

    ; Check if destination is a mounted image

    lda filename2+0
    ldx filename2+1
    jsr is_image_mounted
    lda mn_flag
    zif ne
        lda filename2+0
        ldx filename2+1
        jmp err_imgmounted
    zendif

    lda rn_flag
    zif eq
        jsr inf_working             ; It is a slow operation
        jsr set_buffer              ; Set buffer for image name at buffer1
        jsr DiskCopy                ; Copy file
    zelse
        ; Check if origin is a mounted drive
        lda filename1+0
        ldx filename1+1
        jsr is_image_mounted        ; Check if file is a mounted image
        lda mn_flag
        zif ne
            lda filename1+0
            ldx filename1+1
            jmp err_imgmounted
        zendif
        jsr inf_working             ; It is a slow operation
        jsr set_buffer              ; Set buffer for image name at buffer1
        jsr DiskRename              ; Move/rename
    zendif

    zif cs
        cmp #ERR_FEATURE_DISABLED   ; Disabled by hardware switch?
        zif eq
            lda #<disabled_msg
            ldx #>disabled_msg
            jmp err_withmsg
        zendif
        cmp #ERR_NOT_FOUND
        zif eq
            lda filename1+0
            ldx filename1+1
            jmp err_notfound
        zendif
        cmp #ERR_FILE_EXISTS
        zif eq
            lda #<exists_msg
            ldx #>exists_msg
            jmp err_withmsg
        zendif

        ; Anything else, generic error msg

        lda #<generic_msg
        ldx #>generic_msg
        jmp err_withmsg
    zendif

    jsr inf_done

    rts
zendproc

; Error/Info message routines
;
zproc err_firmware
    stx firmware_opt
    lda #<firmware_msg
    ldx #>firmware_msg
    jmp pr_str
zendproc

zproc inf_working
    lda #<working_msg
    ldx #>working_msg
    jmp pr_str
zendproc

    .data

; Messages

    .global usage_msg

usage_msg:      .ascii "Usage: imu [{/L | /S}]\r\n"
                .ascii "       imu /M <drive> [/O]\r\n"
                .ascii "       imu /U <drive>\r\n"
                .ascii "       imu {/N | /D} <image>\r\n"
                .ascii "       imu {/C | /R} <src image> <dst image>\r\n\r\n"
                .byte 0

firmware_msg:   .ascii "Error: '/"
firmware_opt:   .byte 0
                .ascii "' unsupported.\r\n"
firmware_msg2:  .ascii "Please upgrade the SD Shield firmware to version >= 2.0\r\n"
                .byte 0

imagerr_msg:    .ascii "Image name must be in 8.3 format.\r\n"
                .byte 0

disabled_msg:   .ascii "Disabled by hardware. Please flip option switch 2.\r\n"
                .byte 0

config_msg:     .ascii "Can't update the SD config file.\r\n"
                .byte 0

working_msg:    .ascii "On it. May take a while...\r\n"
                .byte 0
