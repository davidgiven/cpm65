    .include "cpm65.inc"
    .include "zif.inc"

    .import __ZEROPAGE_SIZE__
    .import __CODE_RUN__
    .import __BSS_RUN__
    .import __BSS_SIZE__

.macro debug s
    jsr pdebug
    .byte s
    .byte 13, 10, 0
.endmacro

    .zeropage

current_dirent: .word 0     ; current directory entry
current_fcb:    .word 0     ; current FCB being worked on
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

    ; Update memory region.

    ldy #bios::getzp
    jsr callbios
    clc
    adc #<__ZEROPAGE_SIZE__
    ldy #bios::setzp
    jsr callbios
    
    ldy #bios::gettpa
    jsr callbios
    clc
    adc #>(__BSS_RUN__ + __BSS_SIZE__ - __CODE_RUN__ + 255)
    ldy #bios::settpa
    jsr callbios
    ; fall through to entry_EXIT

; --- Warm start ------------------------------------------------------------

entry_EXIT:
    ldx #$ff                ; reset stack point
    txs

    jsr entry_RESETDISK

    ; Open the CCP.SYS file.

    lda #<ccp_fcb
    ldx #>ccp_fcb
    jsr entry_OPENFILE
    bcs @noccp

    debug "CCP file opened"

    jmp *
    ; TODO: load CCP off disk, run it
@noccp:
    ; TODO: no CCP!
    jmp *

    .data
ccp_fcb:
    .byte 0                 ; drive
    .byte "CCP     SYS"     ; filename: CCP.SYS
    .byte 0, 0, 0, 0        ; EX, S1, S2, RC
    .res 16, 0              ; allocation block
    .byte 0

; --- Reset disk system -----------------------------------------------------

    .code
.proc entry_RESETDISK
    ; Reset transient BDOS state.

    ldy #(bdos_state_end - bdos_state_start - 1)
    lda #0
    zrepeat
        sta bdos_state_start, y
        dey
    zuntil_mi
    
    ; Log in drive A.

    ; A is 0
    jmp entry_LOGINDRIVE
.endproc

; --- Open a file -----------------------------------------------------------

; Opens a file; the FCB is in XA.
; Returns C is error; the code is in A.

entry_OPENFILE:
    jsr new_user_fcb
    jmp open_fcb
    
; Sets up a user-supplied FCB.

new_user_fcb:
    sta current_fcb+0
    stx current_fcb+1
    
    ldy #fcb::s2
    lda #0
    sta (current_fcb), y

    jsr select_fcb_drive

; Selects the drive referred to in the FCB.

.proc select_fcb_drive
    ldy #0
    lda (current_fcb), y        ; get drive byte
    zif_ne
        sec
        sbc #1
        jmp set_active
    zendif
    lda current_drive
set_active:
    sta active_drive
    jmp select_active_drive
.endproc

.proc open_fcb
    lda #15                     ; match 15 bytes of FCB
    jsr find_first
    zif_cc
        ; We have a matching dirent!

        ldy #fcb::ex
        lda (current_fcb), y        ; fetch user extent byte
        sta tempb

        ; Copy the dirent to FCB.

        ldy #31
        zrepeat
            lda (current_dirent), y
            sta (current_fcb), y
            dey
        zuntil_mi

        ; Set bit 7 of S2 to indicate that this file hasn't been modified.

        ldy #fcb::s2
        lda (current_fcb), y
        ora #$80
        sta (current_fcb), y

        ; Compare the user extent byte with the dirent.

        ldy #fcb::ex
        lda (current_fcb), y
        cmp tempb
        beq @setrc
        bcs @user_extent_larger
        ; user extent smaller
        lda #$80                    ; middle of the file, record count full
        jmp @setrc
    @user_extent_larger:
        lda #$00                    ; after the end of the file, record count empty
    @setrc:
        ldy #fcb::rc
        sta (current_fcb), y        ; set extent record count

        clc
    zendif
    rts
.endproc

; --- Directory scanning ----------------------------------------------------

; Find a dirent matching the user FCB.
; On entry, A is the number of significant bytes in the FCB to use when
; searching.
; Returns C on error.

find_first:
    sta find_first_count
    jsr home_drive
    jsr reset_dir_pos
    ; fall through

.proc find_next
    jsr read_dir_entry
    jsr check_dir_pos
    zif_eq                      ; no more files?
        jsr reset_dir_pos
        sec
        rts
    zendif

    ; Does the user actually want to see deleted files?

    lda #$e5
    ldy #0
    cmp (current_fcb), y
    zif_ne
        ; If not, optimise by checking to see if there are no more
        ; files in the directory.
        ; TODO: not done yet
    zendif

    ldy #0
    zrepeat
        lda (current_fcb), y
        cmp #'?'                ; wildcard
        beq @same_characters    ; ...skip comparing this byte
        cpy #fcb::s1            ; don't care about byte 13
        beq @same_characters
        cpy #fcb::ex
        bne @compare_chars

        ; Special logic for comparing extents.

        lda extent_mask
        eor #$ff                ; inverted extent mask
        pha
        and (current_fcb), y    ; mask FCB extent
        sta tempb
        pla
        and (current_dirent),y  ; mask dirent extent
        cmp tempb
        and #$1f                ; only check bits 0..4
        bne find_next           ; not the same? give up
    @compare_chars:
        sec
        sbc (current_dirent), y ; compare the two characters
        and #$7f                ; ignore top bit
        bne find_next           ; not the same? give up
    @same_characters:
        iny
        cpy find_first_count    ; reached the end of the string?
    zuntil_eq

    ; We found a file!

    clc
    rts
    
.endproc
    
    .bss
find_first_count: .byte 0
    .code
; --- Login drive -----------------------------------------------------------

; Logs in active_drive. If the drive was not already logged in, the bitmap
; is recomputed. In all cases the drive is selected.

.proc entry_LOGINDRIVE
    ; Select the drive.

    jsr select_active_drive

    ; Decide if the drive was already logged in.

    lda login_vector+0
    ldx login_vector+1
    ldy active_drive
    jsr shiftr              ; flag at bottom of temp+0

    ror temp+0
    bcs exit

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
    zif_cs
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
    zendif
    
    clc
    adc directory_buffer+0
    sta current_dirent+0
    lda directory_buffer+1
    adc #0
    sta current_dirent+1
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

; --- Drive management ------------------------------------------------------

reset_user_dma:
    lda user_dma+0
    ldx user_dma+1
    ldy #bios::setdma
    jmp callbios

read_sector:
    lda #<current_sector
    ldx #>current_sector
    ldy #bios::setsec
    jsr callbios

    ldy #bios::read
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
    ldy #3
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

        sta temp+0
        stx temp+1
        ldy #dph_copy_end - dph_copy - 1
        zrepeat
            lda (temp), y
            sta dph_copy, y
            dey
        zuntil_mi

        ; Copy DPB into local storage.

        lda dpb+0
        sta temp+0
        lda dpb+1
        sta temp+1
        ldy #dpb_copy_end - dpb_copy - 1
        zrepeat
            lda (temp), y
            sta dpb_copy, y
            dey
        zuntil_mi
    zendif
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

bios_conout:
    ldy #bios::conout
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

    jsr bios_conout
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
active_drive:           .byte 0 ; drive current being worked on
write_protect_vector:   .word 0
login_vector:           .word 0
directory_pos:          .word 0
current_block:          .word 0
user_dma:               .word 0
bdos_state_end:

; Copy of DPH of currently selected drive.

dph_copy:
                    .word 0 ; sector translation table (unused)
scratch1:           .word 0
current_sector:     .res 4  ; scratch2 / scratch3
directory_buffer:   .word 0
dpb:                .word 0
checksum_buffer:    .word 0
bitmap:             .word 0
dph_copy_end:

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

