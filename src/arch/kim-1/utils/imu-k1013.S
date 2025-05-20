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

DMA_BUFFER = $fd00          ; We are using the 256-byte page just below the disk
DMA_AREA = $f4              ; buffer ($fd00), which encodes to $f4. See K-1013 manual.

    .data

; Initialized variables

pk_flag:        .byte 0             ; Create packed image flag

    .text

zproc init

    lda #<DMA_BUFFER
    sta buffer1+0
    lda #>DMA_BUFFER
    sta buffer1+1

    ; Put the disk controller in a sane state
    ;
    lda HSRC                        ; Test if an interrupt is pending
    zif pl
        jsr fdc_exec_senseint
    zendif

    lda #0                          ; Set DMA read mode, unprotect SYSRAM
    sta HSRC

    ; Using a harmless command to check extended cmds support

    ldy #EXT_CMD_DIR
    jsr fdc_exec_extended           ; Get SD card directory listing
    zif cc
        ; Dig further for errors
        lda disk_status
        zif pl
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
    zif cs    
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
        zbreakif mi                 ; Safeguard, stop if len > 128 chars
    zuntil eq

    ; Check it is shorter that 64 chars, fail if not

    cpx #64
    zif cs
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
    zif cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Set buffer for receiving file names

    lda #DMA_AREA
    sta ADMA

    zloop
        ldy #EXT_CMD_NXT_MNT
        jsr fdc_exec_extended       ; Get SD card directory entry
        zif cs
            lda #<fdc_msg
            ldx #>fdc_msg
            jmp err_withmsg         ; Controller error
        zendif       

        ; Check status for errors

        lda disk_status
        and #ST4_NO_DATA
        zbreakif ne

        jsr print_mount

    zendloop
    rts
zendproc

; Produces a list on screen of available images
; 
zproc list_images

    ; Set buffer for receiving file names

    lda #DMA_AREA
    sta ADMA

    zloop
        ldy #EXT_CMD_NXT
        jsr fdc_exec_extended       ; Get SD card directory entry
        zif cs
            lda #<fdc_msg
            ldx #>fdc_msg
            jmp err_withmsg         ; Controller error
        zendif       

        ; No need to check for extended command support

        ; Check status for errors

        lda #ST4_NO_DATA
        bit disk_status
        ; Testing for ST4_NO_DATA
        zbreakif ne
        ; Testing for ST4_ABNORMAL_TERM (0b0100000)
        zif vs
            lda #<readdir_msg
            ldx #>readdir_msg
            jmp err_withmsg         ; Error reading directory
        zendif

        lda #<DMA_BUFFER            ; Print it
        ldx #>DMA_BUFFER
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

    lda #DMA_AREA
    sta ADMA

    lda ro_flag
    sta DMA_BUFFER+1
    lda drive
    sta DMA_BUFFER+0
    ora #EXT_CMD_MNT
    tay
    jsr fdc_exec_extended           ; Mount image
    zif cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    lda #ST4_NOT_FOUND
    bit disk_status
    ; Testing for ST4_NOT_FOUND
    zif ne
        lda filename1+0
        ldx filename1+1
        jmp err_notfound
    zendif
    zif vs
        lda disk_status+1
        and #ST5_DRV_MOUNTED
        zif ne
            ; Was not mounted
            ldx drive_letter
            lda #<mountederr_msg
            ldy #>mountederr_msg
            jmp err_withchar
        zendif
        lda disk_status+1
        and #ST5_IMG_MOUNTED
        zif ne
            ; Was not mounted
            lda filename1+0
            ldx filename1+1
            jmp err_imgmounted
        zendif
        lda disk_status+1
        and #ST5_IMG_INVALID
        zif ne
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
    zif cs
        jmp err_usage
    zendif

    jsr drive_exists
    zif cs
        rts
    zendif

    lda drive
    ora #EXT_CMD_UMNT               ; Unmount drive
    tay
    jsr fdc_exec_extended 
    zif cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    and #ST4_ABNORMAL_TERM
    zif ne
        lda disk_status+1
        and #ST5_DRV_NOT_MOUNTED
        zif ne
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
    zif cs
        rts
    zendif
    
    ; Set filename1
    ;
    ; NOTE: We can do this because DMA_BUFFER is page aligned!
    ;
    ldy #4                          ; Skip image parameters
    lda #>DMA_BUFFER
    sty filename1+0
    sta filename1+1

    jsr set_image_name              ; Copy image name at DMA_BUFFER,Y
                                    ; On exit, Y points to the next char after
                                    ; image name in command line
    jsr skip_sp
 
    cmp #0                          ; End of command line?
    zif ne
        jsr get_option              ; No, get option
        zif cs
            jmp err_usage           ; Syntax error
        zendif
        cpx #'P'                    ; Create packaged image
        zif eq
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
    zif ne
        jmp err_usage               ; Nothing else expected
    zendif

    lda #$01                        ; Set DMA direction bit to write
    sta HSRC          

    ; Set buffer for sending mount info

    lda #BUFFER_DMA
    sta ADMA

    ; Prepare the command data

    lda #77                         ; Tracks
    sta DMA_BUFFER+0
    lda #26                         ; Sectors
    sta DMA_BUFFER+1
    lda #1                          ; Sector size ( 1 == 256bytes )
    ora pk_flag                     ; Whether or not is a packaged image
    sta DMA_BUFFER+2
    lda #0xe5                       ; Filler byte
    sta DMA_BUFFER+3
    ldy #EXT_CMD_NEW                ; Create image
    jsr fdc_exec_extended
    zif cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    lda disk_status
    and #ST4_ABNORMAL_TERM
    zif ne
        lda #ST5_IMG_NAME
        bit disk_status+1
        ; Testing for ST5_IMG_NAME
        zif ne
            lda #<imagerr_msg
            ldx #>imagerr_msg
            jmp err_withmsg
        zendif
        ; Testing for ST5_DISK_FULL (0b10000000)
        zif mi
            lda #<diskfull_msg
            ldx #>diskfull_msg
            jmp err_withmsg
        zendif
        ; Testing for ST5_IMG_EXISTS ( 0b0100000)
        zif vs
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
    zif cs
        rts
    zendif

    cmp #0
    zif ne
        jmp err_usage               ; Nothing else expected
    zendif

    lda #$01                        ; Set DMA direction bit to write
    sta HSRC          

    ; Set buffer for sending mount info

    lda #DMA_AREA
    sta ADMA

    ; Prepare the command data

    ldy #EXT_CMD_ERA                ; Delete image
    jsr fdc_exec_extended
    zif cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    lda #ST4_NOT_FOUND
    bit disk_status
    ; Testing for ST4_NOT_FOUND
    zif ne
        lda filename1+0
        ldx filename1+1
        jmp err_notfound
    zendif
    ; Testing for ST4_ABNORMAL_TERM (0b01000000)
    zif vs
        lda disk_status+1
        and #ST5_IMG_NAME
        zif ne
            ; Invalid image name
            lda #<imagerr_msg
            ldx #>imagerr_msg
            jmp err_withmsg
        zendif
        lda disk_status+1
        and #ST5_IMG_MOUNTED
        zif ne
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
    zif cs
        rts
    zendif

    ; Set second file name into buffer

    jsr set_second_image_name
    zif cs
        rts
    zendif

    cmp #0
    zif ne
        jmp err_usage               ; Nothing else expected
    zendif

    lda #$01                        ; Set DMA direction bit to write
    sta HSRC          

    ; Set buffer for sending mount info

    lda #DMA_AREA
    sta ADMA

    ; Prepare the command data

    lda rn_flag
    zif ne
        ldy #EXT_CMD_MOV            ; Move/rename image
    zelse
        ldy #EXT_CMD_CPY            ; Copy image
    zendif

    jsr fdc_exec_extended
    zif cs
        lda #<fdc_msg
        ldx #>fdc_msg
        jmp err_withmsg             ; Controller error
    zendif
    
    ; Dig further for errors

    lda #ST4_NOT_FOUND
    bit disk_status
    ; Testing for ST4_NOT_FOUND
    zif ne
        lda filename1+0
        ldx filename1+1
        jmp err_notfound
    zendif
    ; Testing for ST4_ABNORMAL_TERM (0b01000000)
    zif vs
        lda #ST5_IMG_NAME
        bit disk_status+1
        ; Testing for ST5_IMG_NAME
        zif ne
            lda #<imagerr_msg
            ldx #>imagerr_msg
            jmp err_withmsg
        zendif
        ; Testing for ST5_DISK_FULL (0b10000000)
        zif mi
            lda #<diskfull_msg
            ldx #>diskfull_msg
            jmp err_withmsg
        zendif
        ; Testing for ST5_IMG_EXISTS ( 0b0100000)
        zif vs
            lda #<exists_msg
            ldx #>exists_msg
            jmp err_withmsg
        zendif
        lda disk_status+1
        and #ST5_IMG_MOUNTED
        zif ne
            ; Was not mounted
            lda filename1+0
            ldx filename1+1
            jmp err_imgmounted
        zendif
        lda disk_status+1
        and #ST5_IMG2_MOUNTED
        zif ne
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
    zif cc
        zrepeat
            lda HSRC                ; Wait for interrupt
        zuntil pl
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
    zuntil pl

    ; Execute Sense Interrupt command

    ldx #fdc_senseint-fdc_commands
    jsr fdc_exec_command
    zif cc
        ; Read results into memory

        jsr fdc_read_result
        zif cc

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
        zuntil mi
        and #0x40                   ; Test data direction bit
        bne fdc_fail                ; Error if controller wants to talk

        lda fdc_commands, x         ; Get command byte
        sta DATR                    ; Store into FDC data register
        inx                         ; Next command byte
        dey
    zuntil eq

    clc
    rts
zendproc

zproc fdc_read_result
    ldx #0
    zloop
        zrepeat
            lda MSTR                ; Wait until RQM from controller
        zuntil mi
        and #0x40                   ; Test data direction bit
        beq fdc_fail                ; Error if controller wants to listen

        lda DATR                    ; Get status byte from data register
        sta disk_status, x          ; Put it into memory
        inx                         ; Next byte
        nop                         ; Give the controller time to update
        nop                         ; the MSTR with a valid busy status
        lda #0x10                   ; Check if busy and go get another
        and MSTR                    ; byte while so
    zuntil eq

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

    .global usage_msg

usage_msg:      .ascii "Usage: imu [/L]\r\n"
                .ascii "       imu /M <drive> [/O]\r\n"
                .ascii "       imu /U <drive>\r\n"
                .ascii "       imu /N <image> [/P]\r\n"
                .ascii "       imu /D <image>\r\n"
                .ascii "       imu {/C | /R} <src image> <dst image>\r\n\r\n"
                .byte 0

fdc_msg:        .ascii "Unexpected floppy controller failure.\r\n"
                .byte 0

real_msg:       .ascii "Not supported. Old firmware or real hardware.\r\n"
                .byte 0

diskfull_msg:   .ascii "SD card is full!\r\n"
                .byte 0

imagerr_msg:    .ascii "Image name invalid or longer than 63 chars.\r\n"
                .byte 0

open_msg:       .ascii "Failed to open directory.\r\n"
                .byte 0

readdir_msg:    .ascii "Failed to read directory.\r\n"
                .byte 0

invalidimg_msg: .ascii "Error: File '"
                .byte 0
invalidimg_msg2:.ascii "' is not a valid IMD image.\r\n"
                .byte 0


