; CP/M-65 Copyright © 2024 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "jumptables.inc"
#include "bdos.inc"

ZEROPAGE

current_dirent:   .word 0 ; current directory entry
dph:              .word 0 ; currently selected DPH

; This is a copy of the DPH, and must be in this order.
directory_buffer: .word 0 ; directory buffer from the DPH
current_dpb:      .word 0 ; currently selected DPB
checksum_buffer:  .word 0 ; checksum buffer from the DPH
bitmap:           .word 0 ; allocation bitmap from the DPH

zproc internal_RESETFILESYSTEM
    ; Reset transient BDOS state.

    ldy #(filesystem_state_end - filesystem_state_start - 1)
    lda #0
    zrepeat
        sta filesystem_state_start, y
        dey
    zuntil_mi

    ; Log in drive A.

    ; A is 0
    jmp internal_LOGINDRIVE
zendproc

; Called before system call processing happens.

zproc internal_BEGINSYS
    lda #$ff
    sta old_fcb_drive       ; mark FCB as not fiddled with

    ; Reset per-system-call state

    lda #0
    sta block_needs_clearing
    rts
zendproc

; Called after system call processing happens.
; Must preserve all registers and P.

zproc internal_ENDSYS
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
zendproc

; Reset the write-protect bits for the drives the user asked for.

zproc bdos_RESETDISK
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

; --- Open a file -----------------------------------------------------------

; Opens a file; the FCB is in param.
; Returns C is error; the code is in A.

zproc bdos_OPENFILE
    jsr new_user_fcb
zendproc
    ; fall through
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

zproc bdos_CREATEFILE
    jsr new_user_fcb
zendproc
    ; fall through
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

zproc bdos_CLOSEFILE
    jsr convert_user_fcb
zendproc
    ; fall through
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

zproc bdos_DELETEFILE
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

zproc bdos_RENAMEFILE
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

zproc bdos_SETFILEATTRS
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

zproc bdos_READSEQUENTIAL
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

zproc bdos_WRITESEQUENTIAL
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
            jsr bios_SETDMA

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

zproc bdos_WRITERANDOM
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

zproc bdos_WRITERANDOMFILLED
    lda #1
    sta block_needs_clearing
    jmp bdos_WRITERANDOM
zendproc

zproc bdos_READRANDOM
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

; Determines the size of a file and seeks to the end.

zproc bdos_COMPUTEFILESIZE
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

zproc bdos_FINDFIRST
    jsr setup_fcb_for_find
    bcs find_error
    ; A = number of bytes to search
    jsr find_first
    jmp copy_result_of_find
zendproc

zproc bdos_FINDNEXT
    jsr setup_fcb_for_find
    bcs find_error
    ; A = number of bytes to search
    jsr find_next
    ; fall through
copy_result_of_find:
    zif_cc
        ; Copy the directory buffer into the DMA buffer.

        ldy #127
        zrepeat
            lda (directory_buffer), y
            sta (user_dma), y
            dey
        zuntil_mi

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

zproc bdos_LOGINDRIVE
    lda param+0
    sta current_drive       ; Set the current drive variable
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
        jsr bios_SETDMA

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

zproc bdos_SETDRIVEREADONLY
    lda #<write_protect_vector
    ldx #>write_protect_vector
    ldy current_drive
    jsr setbit
    clc
    rts
zendproc

; Returns the login bitmap in XA.

zproc bdos_GETLOGINBITMAP
    lda login_vector+0
    ldx login_vector+1
    clc
    rts
zendproc

; Returns the readonly bitmap in XA.

zproc bdos_GETREADONLYBITMAP
    lda write_protect_vector+0
    ldx write_protect_vector+1
    rts
zendproc

; Returns a pointer to the allocation bitmap in XA.

zproc bdos_GETALLOCATIONBITMAP
    lda bitmap+0
    ldx bitmap+1
    clc
    rts
zendproc

; Returns a pointer to the current drive's DPB.

zproc bdos_GETDPB
    lda current_dpb+0
    ldx current_dpb+1
    clc
    rts
zendproc

; --- Drive management ------------------------------------------------------

reset_user_dma:
    lda user_dma+0
    ldx user_dma+1
    jmp bios_SETDMA

set_current_sector:
    lda #<current_sector
    ldx #>current_sector
    jmp bios_SETSEC

read_sector:
    jsr set_current_sector
    jmp bios_READ

; A=0, 1 or 2 as for BIOS_WRITE on entry.

write_sector:
    pha
    jsr set_current_sector
    pla
    jmp bios_WRITE

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
    jsr bios_SELDSK
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

NOINIT

; State used by the filesystem. Cleared whenever the filesystem is reset.

filesystem_state_start:
find_first_count:       .byte 0
active_drive:           .byte 0 ; drive currently being worked on
old_drive:              .byte 0 ; if the drive has been overridden by the FCB
old_fcb_drive:          .byte 0 ; drive in user FCB on entry
write_protect_vector:   .word 0
login_vector:           .word 0
directory_pos:          .word 0
current_sector:         .fill 3  ; 24-bit sector number
block_needs_clearing:   .byte 0 ; if set, any new block that's created will be zeroed
filesystem_state_end:

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

