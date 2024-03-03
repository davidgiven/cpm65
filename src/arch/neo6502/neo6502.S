#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc"
#include "bdos.inc"

CP = 0xff00
CP_GROUP    = CP + 0
CP_FUNCTION = CP + 1
CP_ERRNO    = CP + 2
CP_INFO     = CP + 3
CP_PARAM    = CP + 4

GROUP_TTY              = 2
FUNC_TTY_READCH        = 1
FUNC_TTY_POLLCH        = 2
FUNC_TTY_WRITECH       = 6
FUNC_TTY_SETCURSOR     = 7
FUNC_TTY_GETSIZE       = 9
FUNC_TTY_INSERTLINE    = 10
FUNC_TTY_DELETELINE    = 11
FUNC_TTY_CLEAR         = 12
FUNC_TTY_GETCURSOR     = 13
FUNC_TTY_CLEARAREA     = 14
FUNC_TTY_SETCOLOURS    = 15
FUNC_TTY_REVERSECURSOR = 16

GROUP_FILE          = 3
FUNC_FILE_OPEN      = 4
FUNC_FILE_CLOSE     = 5
FUNC_FILE_SEEK      = 6
FUNC_FILE_TELL      = 7
FUNC_FILE_READH     = 8
FUNC_FILE_WRITEH    = 9
FUNC_FILE_GETSIZE   = 10
FUNC_FILE_SETSIZE   = 11
FUNC_FILE_RENAME    = 12
FUNC_FILE_DELETE    = 13
FUNC_FILE_CREATEDIR = 14
FUNC_FILE_STAT      = 16
FUNC_FILE_OPENDIR   = 17
FUNC_FILE_READDIR   = 18
FUNC_FILE_CLOSEDIR  = 19
FUNC_FILE_COPY      = 20
FUNC_FILE_SETATTRS  = 21

FIOMODE_RDONLY      = 0
FIOMODE_WRONLY      = 1
FIOMODE_RDWR        = 2
FIOMODE_RDWR_CREATE = 3

FIOATTR_DIR         = 1<<0
FIOATTR_SYSTEM      = 1<<1
FIOATTR_ARCHIVE     = 1<<2
FIOATTR_READONLY    = 1<<3
FIOATTR_HIDDEN      = 1<<4

; Filenames are of the form: "/A10/ABCDEFGH.XYZ"

FT_ATTRIBS        = 0 ; top bit indicate file is in use
FT_FILENAMELEN    = 1
FT_FILENAME       = 2
FT__SIZE          = 20

NUM_FILES         = 8

ZEROPAGE

.global ptr, ptr1

ptr:            .fill 2
ptr1:           .fill 2

; --- Initialisation code ---------------------------------------------------

; Boot sector and relocator. Loaded at 0x8000 when the system starts. Called
; once on startup and then never again.

.global _start
.section loader, "ax"
_start:
    ldx #0xff
    txs                 ; reset stack

    ; Relocate the BIOS to the top of memory.

    zloop
        load = .
        lda BIOS_LOAD_ADDR
        store = .
        sta BIOS_EXEC_ADDR

        inc load+1
        zif_eq
            inc load+2
        zendif

        inc store+1
        zif_eq
            inc store+2
            zbreakif_eq
        zendif
    zendloop

    jsr initdrivers

    jsr screen_clear
    jsr set_normal_text

    ldy #banner_end - banner
    zrepeat
        tya
        pha
        lda banner-1, y
        jsr tty_conout
        pla
        tay
        dey
    zuntil_eq

    jmp bdos_core

banner: ; reversed!
    .ascii "\rsuehproM/2056oen eht rof 56-M/PC"
banner_end:

; ===========================================================================
;                            BDOS IMPLEMENTATION
; ===========================================================================

.global internal_READSEQUENTIAL

zproc internal_RESETFILESYSTEM
    ; Close all files.

    lda #0xff
    sta CP_PARAM+0
    lda #FUNC_FILE_CLOSE
    jsr neo_file_func

    ; Clear the file allocation table.

    ldx #0
    zrepeat
        stz file_table+FT_ATTRIBS, x

        txa
        clc
        adc #FT__SIZE
        tax

        cpx #NUM_FILES*FT__SIZE
    zuntil_eq

    ; Initialise the LRU list.

    ldx #NUM_FILES-1
    zrepeat
        txa
        sta file_table_lru, x

        dex
    zuntil_mi

    rts
zendproc

zproc internal_BEGINSYS
zproc internal_ENDSYS
	rts
zendproc

zproc bdos_LOGINDRIVE
    lda param
    and #0x0f
	sta current_drive

	lda #0
	clc
    rts
zendproc

zproc bdos_OPENFILE
    jsr get_opened_file_table_entry
    lda CP_ERRNO
    zif_ne
        sec
        rts
    zendif
zendproc
    ; falls through
zproc rewind_fcb
    ldy #FCB_EX
    lda #0
    sta (param), y
    iny
    sta (param), y
    iny
    sta (param), y
    iny
    sta (param), y

    jsr update_rc_field

    clc
    rts
zendproc

zproc bdos_CREATEFILE
	; See if the file itself exists.
	
    jsr convert_filename
    lda #<(temp_file_entry + FT_FILENAMELEN)
    sta CP_PARAM+0
    lda #>(temp_file_entry + FT_FILENAMELEN)
    sta CP_PARAM+1

    lda #FUNC_FILE_STAT
    jsr neo_file_func_blocking
    lda CP_ERRNO
    beq fail_read_write

    ; Create the directory for this drive/user.

    jsr truncate_filename_to_directory
	
    lda #<(temp_file_entry + FT_FILENAMELEN)
    sta CP_PARAM+0
    lda #>(temp_file_entry + FT_FILENAMELEN)
    sta CP_PARAM+1
    lda #FUNC_FILE_CREATEDIR
    jsr neo_file_func

	; Now create and open the file.

    jsr get_file_table_entry

    lda #FIOMODE_RDWR_CREATE
    jsr do_open_file_table_entry
    lda CP_ERRNO
    bne fail_read_write
    bra rewind_fcb
zendproc

zproc bdos_READRANDOM
    jsr update_fcb_to_current_random_record
zendproc
    ; fall through
.global internal_READSEQUENTIAL
internal_READSEQUENTIAL:
zproc bdos_READSEQUENTIAL
    jsr get_opened_file_table_entry
    lda CP_ERRNO
    bne fail_read_write

    jsr seek_to_fcb_location
    lda CP_ERRNO
    bne fail_read_write

    lda #FUNC_FILE_READH
    jsr do_read_write
    lda CP_ERRNO
    bne fail_read_write

    jsr increment_fcb_location
    clc
    rts
zendproc

.global bdos_WRITERANDOMFILLED
bdos_WRITERANDOMFILLED:
zproc bdos_WRITERANDOM
    jsr update_fcb_to_current_random_record
zendproc
    ; fall through
zproc bdos_WRITESEQUENTIAL
    jsr get_opened_file_table_entry
    lda CP_ERRNO
    bne fail_read_write

    jsr seek_to_fcb_location
    lda CP_ERRNO
    bne fail_read_write

    lda #FUNC_FILE_WRITEH
    jsr do_read_write
    lda CP_ERRNO
    bne fail_read_write

    jsr increment_fcb_location

    ; Ensure any new record is reflected in FCB_RC.

    ldy #FCB_CR
    lda (param), y
    ldy #FCB_RC
    cmp (param), y
    zif_cs
        sta (param), y
    zendif

    clc
    rts
zendproc

zproc fail_read_write
    sec
    rts
zendproc

zproc bdos_CLOSEFILE
    jsr get_opened_file_table_entry
    lda CP_ERRNO
    bne fail_read_write
    phx

    jsr flush_rc_count

    lda #FUNC_FILE_CLOSE
    jsr neo_file_func_blocking
    plx
    lda CP_ERRNO
    bne fail_read_write

    stz file_table+FT_ATTRIBS, x
    clc
    rts
zendproc

zproc bdos_DELETEFILE
    ; Save old user_dma.

    lda user_dma+0
    pha
    lda user_dma+1
    pha

    lda param+0
    sta delete_saved_param_lo
    lda param+1
    sta delete_saved_param_hi

    lda #<temp_fcb
    sta user_dma+0
    lda #>temp_fcb
    sta user_dma+1

    jsr bdos_FINDFIRST
    bcs delete_success
    zrepeat
        ; Found a matching file.

        lda user_dma+0
        sta param+0
        lda user_dma+1
        sta param+1

        jsr get_closed_file_table_entry

        lda #<(temp_file_entry + FT_FILENAMELEN)
        sta CP_PARAM+0
        lda #>(temp_file_entry + FT_FILENAMELEN)
        sta CP_PARAM+1

        lda #FUNC_FILE_DELETE
        jsr neo_file_func_blocking
        lda CP_ERRNO
        zbreakif_ne

        ; Find the next file.

    delete_saved_param_lo = . + 1
        lda #0
        sta param+0
    delete_saved_param_hi = . + 1
        lda #0
        sta param+1

        jsr bdos_FINDNEXT
    zuntil_cs
    
    ; Something went wrong.

    sec
    bra delete_exit

delete_success:
    clc
delete_exit:
    pla
    sta user_dma+1
    pla
    sta user_dma+0
    rts
zendproc

zproc fail_find
    sec
    lda #0xff
    rts
zendproc

zproc bdos_FINDFIRST
    ; FCB contains a pattern:
    ;
    ;    ?:????????.???
    
    jsr convert_filename                ; Filename is '/A5/ABCDEFGH.IJK'
    jsr truncate_filename_to_directory  ; Filename should look like '/A5'

    lda #<(temp_file_entry+FT_FILENAMELEN)
    sta CP_PARAM+0
    lda #>(temp_file_entry+FT_FILENAMELEN)
    sta CP_PARAM+1
    lda #FUNC_FILE_OPENDIR
    jsr neo_file_func_blocking

    lda CP_ERRNO
    bne fail_find
zendproc
    ; fall through
zproc bdos_FINDNEXT
    lda #<temp_file_entry
    sta CP_PARAM+0
    lda #>temp_file_entry
    sta CP_PARAM+1
    lda #FT__SIZE-1
    sta temp_file_entry

    lda #FUNC_FILE_READDIR
    jsr neo_file_func_blocking
    lda CP_ERRNO
    bne fail_find

    ; Convert the DOS filename to an FCB in user_dma.

    ldx #0              ; offset into DOS filename
    ldy #FCB_F1         ; offset into FCB
    zrepeat
        lda #' '
        cpx temp_file_entry
        zif_ne
            lda temp_file_entry+1, x
            jsr uppercase
            cmp #'.'
            zif_eq
                cpy #FCB_T1
                zif_eq
                    inx
                    zcontinue
                zendif
                dex
                lda #' '
            zendif
        
            inx
        zendif
        sta (user_dma), y

        iny
        cpy #FCB_T3+1
    zuntil_eq

    ldy #FCB_DR
    lda (param), y
    sta (user_dma), y

    ; Set the M/E/R length.
    ;
    ;  +5        +4        +3        +2
    ;  --------- --------- --------- ---------
    ;  0000 0000 MMMM MEEE EERR RRRR RXXX XXXX

    ; Number of records in the last extent.
    
    lda CP_PARAM+2
    asl a
    lda CP_PARAM+3
    rol a
    and #0x7f
    tax
    lda CP_PARAM+2
    and #0x7f
    zif_ne
        inx
    zendif
    txa
    ldy #FCB_RC
    sta (user_dma), y

    ; Extent byte.

    lda CP_PARAM+3
    asl a
    sta temp+0
    lda CP_PARAM+4
    rol a
    asl temp+0
    rol a
    and #0b00011111
    ldy #FCB_EX
    sta (user_dma), y

    ; Module byte.

    lda CP_PARAM+3
    lsr a
    lsr a
    lsr a
    and #0b00011111
    ldy #FCB_S2
    sta (user_dma), y

    ldy #FCB_S1
    lda #0
    sta (user_dma), y

    ; Match against the pattern.

    ldy #FCB_F1
    zrepeat
        lda (param), y
        and #0x7f
        cmp #'?'
        zif_ne
            cmp (user_dma), y
            zif_ne
                ; Character is not a wildcard and does not match!
                ; Try the next file.

                jmp bdos_FINDNEXT
            zendif
        zendif
        iny
        cpy #FCB_T3+1
    zuntil_eq

    ; Success. But, remember to fill out the file attributes.

    lda user_dma+0
    sta param+0
    lda user_dma+1
    sta param+1

    lda CP_PARAM+6
    jsr update_fcb_attributes
    
    lda #0
    clc
    rts
zendproc

zproc truncate_filename_to_directory
    ldx #2
    lda temp_file_entry+FT_FILENAME, x
    cmp #'/'
    zif_ne
        ; Must have two digits for the user code
        inx
    zendif
    stx temp_file_entry+FT_FILENAMELEN
    rts
zendproc

zproc bdos_SETFILEATTRS
	jsr convert_filename
	lda #<temp_file_entry+FT_FILENAMELEN
	sta CP_PARAM+0
	lda #>temp_file_entry+FT_FILENAMELEN
	sta CP_PARAM+1
	
	; Compute the Morpheus file attributes.

	lda #0
	pha
	ldy #FCB_T1
	lda (param), y
	zif_mi
		pla
		lda #FIOATTR_READONLY
		pha
	zendif
	iny
	lda (param), y
	zif_mi
		pla
		ora #FIOATTR_SYSTEM
		pha
	zendif
	iny
	lda (param), y
	zif_mi
		pla
		ora #FIOATTR_ARCHIVE
		pha
	zendif
	pla

	; Update the file.

	sta CP_PARAM+2
	lda #FUNC_FILE_SETATTRS
	jsr neo_file_func_blocking
	
	; Check for errors.

	clc
	lda CP_ERRNO
	zif_ne
		sec
	zendif
	rts
zendproc

zproc bdos_GETLOGINBITMAP
    lda #0xff
    ldx #0xff
zendproc
    ; fall through
zproc bdos_RESETDISK
    clc
    rts
zendproc

zproc bdos_SETDRIVEREADONLY
zproc bdos_UNIMPLEMENTED
zproc bdos_GETALLOCATIONBITMAP
zproc bdos_GETREADONLYBITMAP
zproc bdos_GETDPB
    lda #<unimplemented_string
    ldx #>unimplemented_string
    jmp harderror
unimplemented_string:
    .ascii "Unimplemented"
    .byte 0
zendproc

zproc bdos_GETBIOS
    lda #<biosentry
    sta param+0
    ldx #>biosentry
    stx param+1
    rts
zendproc

zproc bdos_COMPUTEFILESIZE
    jsr get_opened_file_table_entry
    lda CP_ERRNO
    zif_ne
        clc
        rts
    zendif

    lda #FUNC_FILE_GETSIZE
    jsr neo_file_func_blocking

    ; Place the file size (in records) into FCB_Rx.
    ;
    ; The file size in the CP_PARAM block is:

    ;  +4        +3        +2        +1
    ;  --------- --------- --------- ---------
    ;  0000 0000 MMMM MEEE EERR RRRR RXXX XXXX

    lda CP_PARAM+1
    asl a
    lda CP_PARAM+2
    rol a
    ldy #FCB_R0
    sta (param), y
    lda CP_PARAM+3
    rol a
    iny
    sta (param), y      ; R1
    lda CP_PARAM+4
    rol a
    iny
    sta (param), y      ; R2

    ; Round up the last record.

    lda CP_PARAM+1
    and #0x7f
    zif_ne
        ldy #FCB_R0
        lda (param), y
        inc a
        sta (param), y
        zif_eq
            iny
            lda (param), y
            inc a
            sta (param), y
            zif_eq
                iny
                lda (param), y
                inc a
                sta (param), y
            zendif
        zendif
    zendif
    clc
    rts
zendproc

zproc bdos_RENAMEFILE
    ; Old name: param+0
    ; New name: param+16

    jsr get_closed_file_table_entry
    phx

    clc
    lda param+0
    adc #16
    sta param+0
    zif_eq
        inc param+1
    zendif

    jsr get_closed_file_table_entry

    pla
    inc a
    clc
    adc #<file_table
    sta CP_PARAM+0
    lda #>file_table
    adc #0
    sta CP_PARAM+1

    lda #<(temp_file_entry+FT_FILENAMELEN)
    sta CP_PARAM+2
    lda #>(temp_file_entry+FT_FILENAMELEN)
    sta CP_PARAM+3

    lda #FUNC_FILE_RENAME
    jsr neo_file_func_blocking
    clc
    lda CP_ERRNO
    zif_ne
        sec
    zendif
    rts
zendproc

; Seeks the file whose handle is in CP_PARAM+0 to the location
; pointed at by the FCB in (param).

zproc seek_to_fcb_location
    ldy #FCB_CR
    jsr compute_seek_location

    ; Do the seek.

    lda #FUNC_FILE_SEEK
    jmp neo_file_func_blocking
zendproc

; Computes the seek location (into CP_PARAM+1) of an FCB.
; On entry, Y is the offset of the FCB field to use to get
; the record count (normally, FCB_CR).

zproc compute_seek_location
    ; Convert the file position to an absolute location.
    ; There are:
    ;   128 bytes per record
    ;   32 records per extent
    ;   32 extents per module (S2)
    ; So, the final location is:
    ;
    ;  +4        +3        +2        +1
    ;  --------- --------- --------- ---------
    ;  0000 0000 MMMM MEEE EERR RRRR R000 0000

    stz CP_PARAM+1
    lda (param), y
    lsr a               ; puts the low bit into C
    sta CP_PARAM+2
    ror CP_PARAM+1      ; 0x00 or 0x80

    ldy #FCB_EX
    lda (param), y
    ror a
    ror a
    ror a               ; bottom two bits rotated to the top
    pha
    and #0xc0           ; discard everything else
    ora CP_PARAM+2
    sta CP_PARAM+2
    pla
    and #0x07           ; top three bits of extent
    sta CP_PARAM+3

    ldy #FCB_S2
    lda (param), y
    lsr a
    lsr a
    lsr a
    and #0x1f
    sta CP_PARAM+3
    stz CP_PARAM+4
    rts
zendproc

; Changes the FCB to point at the current random record.

zproc update_fcb_to_current_random_record
    ldy #FCB_RC
    lda (param), y
    cmp #0x80
    zif_ne
        ; If RC is not 0x80, then this is must be the last extent
        ; in the file; we need to set the file length appropriately
        ; in case we move to a new extent.

        jsr flush_rc_count
    zendif

    ; Convert random access record number to M/E/R.

    ldy #FCB_EX
    lda (param), y
    sta temp+0              ; old extent
    ldy #FCB_S2
    lda (param), y
    sta temp+1              ; old module

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
    ldy #FCB_EX
    sta (param), y

    ldy #FCB_R1
    lda (param), y          ; get high byte
    lsr a
    lsr a
    lsr a
    lsr a
    ldy #FCB_S2
    sta (param), y

    cmp temp+1              ; is the module different?
    zif_eq
        ldy #FCB_EX
        lda (param), y
        cmp temp+0          ; is the extent different?
        zif_eq
            rts             ; neither is different
        zendif
    zendif
zendproc
    ; fall through
zproc update_rc_field
    ; Get the current extent number into temp.
    ;
    ; 0000 00MM MMME EEEE

    ldy #FCB_S2
    lda (param), y
    lsr a
    lsr a
    lsr a
    and #0x03
    sta temp+1

    ldy #FCB_S2
    lda (param), y
    and #0x07
    asl a
    asl a
    asl a
    asl a
    asl a
    ldy #FCB_EX
    ora (param), y
    sta temp+0

    ; Fetch the real length of the file into ptr. We can't use stat for this
    ; because it might not be correct if the file is already open.
    ;
    ;  +4        +3        +2        +1
    ;  --------- --------- --------- ---------
    ;  0000 0000 MMMM MEEE EERR RRRR RXXX XXXX

    lda #FUNC_FILE_GETSIZE
    jsr neo_file_func_blocking

    ; Get the extent count.

    lda CP_PARAM+2
    sta ptr+0
    lda CP_PARAM+3
    ldx #6
    zrepeat
        lsr a
        ror ptr+0
        dex
    zuntil_eq

    ; If we're looking at the last extent, compute the number of records.
    ; Otherwise, it's 128.

    tax
    lda #0x80
    cpx temp+1
    zif_eq
        ldx ptr+0
        cpx temp+0
        zif_eq
            lda CP_PARAM+1
            asl a
            lda CP_PARAM+2
            rol a
            and #0x7f

            tay
            lda CP_PARAM+1
            and #0x7f
            zif_ne
                iny
            zendif
            tya
        zendif
    zendif

    ldy #FCB_RC
    sta (param), y
    rts
zendproc

; If we are on the last extent of the file, update the file's size to match the
; current record count.

zproc flush_rc_count
    ldy #FCB_RC
    lda (param), y
    cmp #0x80
    zif_eq
        rts
    zendif

    jsr compute_seek_location

    lda #FUNC_FILE_SETSIZE
    jmp neo_file_func_blocking
zendproc

; Increments the FCB file location to the next record.

zproc increment_fcb_location
    ldy #FCB_CR
    lda (param), y
    inc a
    sta (param), y
    cmp #128
    zif_eq
        lda #0
        sta (param), y
        ldy #FCB_EX
        lda (param), y
        inc a
        sta (param), y
        cmp #32
        zif_eq
            lda #0
            sta (param), y
            ldy #FCB_S2
            lda (param), y
            inc a
            sta (param), y
        zendif

        ; Update the RC field with the number of records in the
        ; current extent.

        jsr update_rc_field
    zendif
    rts
zendproc

; Perform a read or write to the file handle in CP_PARAM+0.
; The function code is in A.

zproc do_read_write
    pha

    lda user_dma+0
    sta CP_PARAM+1
    lda user_dma+1
    sta CP_PARAM+2

    lda #0x80
    sta CP_PARAM+3
    stz CP_PARAM+4

    pla
    jmp neo_file_func_blocking
zendproc

; Converts the current FCB filename into a Pascal string filename
; in temp_file_entry.

zproc convert_filename
    stz temp_file_entry+FT_ATTRIBS

    lda #'/'
    sta temp_file_entry+FT_FILENAME+0

    lda (param)     ; drive
    dec
    zif_mi          ; no drive specified?
        lda current_drive
    zendif
    clc
    adc #'A'
    sta temp_file_entry+FT_FILENAME+1

    ldx #2
    lda current_user
    zif_ne
        cmp #9
        zif_cs
            lda #'1'
            sta temp_file_entry+FT_FILENAME, x
            inx
            sec
            sbc #10
        zendif

        clc
        adc #'0'
        sta temp_file_entry+FT_FILENAME, x
        inx
    zendif

    lda #'/'
    sta temp_file_entry+FT_FILENAME, x
    inx

    ; Copy filename

    ldy #FCB_F1
    zrepeat
        lda (param), y
        and #0x7f

        cmp #' '
        zif_ne
            cpy #FCB_T1
            zif_eq
                pha
                lda #'.'
                sta temp_file_entry+FT_FILENAME, x
                pla
                inx
            zendif

            sta temp_file_entry+FT_FILENAME, x
            inx
        zendif

        iny
        cpy #FCB_T3+1
    zuntil_eq

    stx temp_file_entry+FT_FILENAMELEN
    rts
zendproc

; Finds an existing file table slot for the FCB in param.
; On exit:
; A = index of entry (i.e. file handle)
; X = offset into file_table
; C if no file table slot was found

zproc convert_and_find_file_table_entry
    jsr convert_filename

    ; Look for a matching slot.

    ldx #0              ; offset to FT being considered
    stz ptr+0           ; file handle
    zrepeat
        phx
        lda file_table+FT_ATTRIBS, x
        zif_ne          ; skip empty slots
            ldy #FT_FILENAMELEN-1
            zrepeat
                inx
                iny

                lda file_table, x
                cmp temp_file_entry, y
                zbreakif_ne

                cpy temp_file_entry+FT_FILENAMELEN
            zuntil_eq
            zif_eq
                plx
                clc
                rts
            zendif
        zendif
        pla
        clc
        adc #FT__SIZE
        tax

        inc ptr+0
        cpx #FT__SIZE*NUM_FILES
    zuntil_eq
    sec
    rts
zendproc

; Finds or allocates a new file table slot
; A = index of entry (i.e. file handle)
; X = offset into file_table

zproc get_file_table_entry
    jsr convert_and_find_file_table_entry
    zif_cs
        ; No slots match. Find an empty slot.

        ldx #0
        stx ptr+0
        zrepeat
            lda file_table+FT_ATTRIBS, x
            beq found_empty_slot

            inc ptr+0

            txa
            clc
            adc #FT__SIZE
            tax

            cmp #FT__SIZE * NUM_FILES
        zuntil_eq

        ; A file needs to be evicted.

        lda file_table_lru+NUM_FILES-1
        sta ptr+0
        tay
        lda file_table_offsets, y
        tax

        lda file_table+FT_ATTRIBS, x
        zif_ne
            ; Yes; it needs closing.

            lda ptr+0
            sta CP_PARAM+0

            lda #FUNC_FILE_CLOSE
            jsr neo_file_func_blocking
            lda CP_ERRNO
            zif_ne
                rts
            zendif
        zendif

    found_empty_slot:
        ; X is the offset, ptr+0 is the handle.

        lda temp_file_entry+FT_FILENAMELEN
        inc a
        inc a
        sta ptr+1

        phx
        ldy #0
        zrepeat
            lda temp_file_entry, y
            sta file_table, x
            inx
            iny
            cpy ptr+1
        zuntil_eq
        plx
    zendif

    lda ptr+0
    sta CP_PARAM+0
    rts
zendproc

file_table_offsets:
    offset = 0
    .rept NUM_FILES
        .byte offset * FT__SIZE
        offset = offset + 1
    .endr

zproc get_closed_file_table_entry
    jsr get_file_table_entry

    lda file_table+FT_ATTRIBS, x
    zif_ne
        ; This table entry is open.

        lda #FUNC_FILE_CLOSE
        jsr neo_file_func

        stz file_table+FT_ATTRIBS
    zendif
    rts
zendproc
        
zproc get_opened_file_table_entry
    jsr get_file_table_entry
zendproc
    ; fall through
zproc open_file_table_entry
    phx

    stz CP_ERRNO
    lda file_table+FT_ATTRIBS, x
    zif_eq
        ; This file has not been opened.

        lda #FIOMODE_RDWR
        jsr do_open_file_table_entry
    zendif

    ; Update the LRU list.

update_lru_list_debug:
    ldx #NUM_FILES-1
    ldy #NUM_FILES-1
    zrepeat
        lda file_table_lru, x
        cmp ptr+0
        zif_ne
            sta file_table_lru, y
            dey
        zendif
        dex
    zuntil_mi
    lda ptr+0
    sta file_table_lru

    plx
    rts
zendproc

; On entry:
;   X = offset to file table entry
;   A = mode

zproc do_open_file_table_entry
    sta CP_PARAM+3

    clc
    txa
    adc #<(file_table + FT_FILENAMELEN)
    sta CP_PARAM+1
    lda #>(file_table + FT_FILENAMELEN)
    adc #0
    sta CP_PARAM+2

    lda #FUNC_FILE_OPEN
    jsr neo_file_func_blocking

    lda CP_ERRNO
    zif_eq
        lda CP_PARAM+0
        pha

        lda CP_PARAM+1
        sta CP_PARAM+0
        lda CP_PARAM+2
        sta CP_PARAM+1

        lda #FUNC_FILE_STAT
        jsr neo_file_func_blocking
        lda CP_PARAM+4
        ora #0x80
        sta file_table+FT_ATTRIBS, x
        jsr update_fcb_attributes

        pla
        sta CP_PARAM+0
    zendif

    jmp update_rc_field
zendproc

; Updates the file attribute bits in the current FCB to the value in A.

zproc update_fcb_attributes
    ror a           ; discard FIOATTR_DIR
    sta temp+0

    ldy #FCB_T2
    lda (param), y
    asl a
    ror temp+0      ; SYSTEM -> C
    ror a
    sta (param), y

    iny             ; -> FCB_T3
    lda (param), y
    asl a
    ror temp+0      ; ARCHIVE -> C
    ror a
    sta (param), y

    ldy #FCB_T1
    lda (param), y
    asl a
    ror temp+0      ; READONLY -> C
    ror a
    sta (param), y
    
    rts
zendproc

; Execute RP2040 operation in A. Don't wait.

zproc neo_file_func
    jsr wait_for_command

    sta CP_FUNCTION
    lda #GROUP_FILE
    sta CP_GROUP
    rts
zendproc

; Execute RP2040 operation in A. Do wait.

zproc neo_file_func_blocking
    jsr neo_file_func
    jmp wait_for_command
zendproc

; ===========================================================================
;                            BIOS IMPLEMENTATION
; ===========================================================================

.data
.global drvtop
; This must point at the _last_ driver.
drvtop: .word drv_TTY

; --- SCREEN driver ---------------------------------------------------------

defdriver SCREEN, DRVID_SCREEN, drvstrat_SCREEN, 0

; SCREEN driver strategy routine.
; Y=SCREEN opcode.
zproc drvstrat_SCREEN
    jmpdispatch screen_jmptable_lo, screen_jmptable_hi

screen_jmptable_lo:
    jmptablo screen_version
    jmptablo screen_getsize
    jmptablo screen_clear
    jmptablo screen_setcursor
    jmptablo screen_getcursor
    jmptablo screen_putchar
    jmptablo screen_putstring
    jmptablo screen_getchar
    jmptablo fail_read_write
    jmptablo screen_scrollup
    jmptablo screen_scrolldown
    jmptablo screen_cleartoeol
    jmptablo screen_setstyle
screen_jmptable_hi:
    jmptabhi screen_version
    jmptabhi screen_getsize
    jmptabhi screen_clear
    jmptabhi screen_setcursor
    jmptabhi screen_getcursor
    jmptabhi screen_putchar
    jmptabhi screen_putstring
    jmptabhi screen_getchar
    jmptabhi fail_read_write
    jmptabhi screen_scrollup
    jmptabhi screen_scrolldown
    jmptabhi screen_cleartoeol
    jmptabhi screen_setstyle
zendproc

zproc screen_version
    lda #0
    rts
zendproc

zproc screen_getsize
    lda #FUNC_TTY_GETSIZE
    jsr neo_tty_func_blocking
    lda CP_PARAM+0
    dec a
    ldx CP_PARAM+1
    dex
    rts
zendproc

zproc screen_clear
    lda #FUNC_TTY_CLEAR
    jmp neo_tty_func
zendproc

zproc screen_setcursor
    sta CP_PARAM+0
    stx CP_PARAM+1
    lda #FUNC_TTY_SETCURSOR
    jmp neo_tty_func
zendproc

zproc screen_getcursor
    lda #FUNC_TTY_GETCURSOR
    jsr neo_tty_func_blocking
    lda CP_PARAM+0
    ldx CP_PARAM+1
    rts
zendproc

zproc screen_getchar
    lda #FUNC_TTY_REVERSECURSOR
    jsr neo_tty_func

    zrepeat
        lda #FUNC_TTY_READCH
        jsr neo_tty_func_blocking
        lda CP_PARAM + 0
    zuntil_ne
    
    cmp #8
    zif_eq
        lda #127
    zendif

    pha
    lda #FUNC_TTY_REVERSECURSOR
    jsr neo_tty_func
    pla
    
    clc
    rts
zendproc

zproc screen_putchar
    sta CP_PARAM+0
    lda #FUNC_TTY_WRITECH
    jmp neo_tty_func
zendproc

zproc screen_putstring
    sta ptr+0
    stx ptr+1
    ldy #0
    zrepeat
        lda (ptr), y
        zbreakif_eq
        jsr screen_putchar
        iny
    zuntil_eq ; never 0
    clc
    rts
zendproc

zproc screen_scrollup
    stz CP_PARAM+0
    lda #FUNC_TTY_DELETELINE
    jmp neo_tty_func
zendproc

zproc screen_scrolldown
    stz CP_PARAM+0
    lda #FUNC_TTY_INSERTLINE
    jmp neo_tty_func
zendproc

zproc screen_cleartoeol
    jsr screen_getsize
    pha                 ; ...width

    jsr screen_getcursor ; leaves cursor position in params 0/a and 1/x
    pla
    sta CP_PARAM+2
    stx CP_PARAM+3

    lda #FUNC_TTY_CLEARAREA
    jmp neo_tty_func
zendproc

zproc set_normal_text
    lda #0x0f
    sta CP_PARAM+0
    stz CP_PARAM+1
    lda #FUNC_TTY_SETCOLOURS
    jmp neo_tty_func
zendproc

zproc screen_setstyle
    and #STYLE_REVERSE
    beq set_normal_text
zendproc
    ; fall through
zproc set_reverse_text
    stz CP_PARAM+0
    lda #0x0f
    sta CP_PARAM+1
    lda #FUNC_TTY_SETCOLOURS
    jmp neo_tty_func
zendproc

; --- TTY driver ------------------------------------------------------------

defdriver TTY, DRVID_TTY, drvstrat_TTY, drv_SCREEN

; TTY driver strategy routine.
; Y=TTY opcode.
zproc drvstrat_TTY
    jmpdispatch jmptable_lo, jmptable_hi

jmptable_lo:
    jmptablo tty_const
    jmptablo screen_getchar
    jmptablo tty_conout
jmptable_hi:
    jmptabhi tty_const
    jmptabhi screen_getchar
    jmptabhi tty_conout
zendproc

; Returns 0xff if no key is pending, 0 if one is.

zproc tty_const
    lda #FUNC_TTY_POLLCH
    jsr neo_tty_func_blocking
    lda CP_PARAM+0
    clc
    rts
zendproc

; Writes the character in A.

zproc tty_conout
    cmp #'\n'
    zif_ne
        cmp #127
        zif_eq
            lda #8
        zendif
        sta CP_PARAM + 0
        lda #FUNC_TTY_WRITECH
        jsr neo_tty_func
    zendif
    clc
    rts
zendproc

; Execute RP2040 operation in A. Don't wait.

zproc neo_tty_func
    jsr wait_for_command

    sta CP_FUNCTION
    lda #GROUP_TTY
    sta CP_GROUP
    rts
zendproc

; Execute RP2040 operation in A. Do wait.

zproc neo_tty_func_blocking
    jsr neo_tty_func
    jmp wait_for_command
zendproc

.global bios_SELDSK, bios_SETSEC, bios_SETDMA, bios_READ, bios_WRITE

.text
bios_SELDSK:
bios_SETSEC:
bios_SETDMA:
bios_READ:
bios_WRITE:
    sec
    rts

zproc bios_NEWLINE
    lda #13
    jmp bios_CONOUT
zendproc

; --- BIOS entrypoints ------------------------------------------------------

zproc bios_GETTPA
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc bios_SETTPA
    sta mem_base
    stx mem_end
    clc
    rts
zendproc

zproc bios_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc

zproc bios_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc bios_SETBANK
    rts
zendproc

; --- Utilities -------------------------------------------------------------

; Waits for the previous command to complete, if any.

zproc wait_for_command
    pha
    zrepeat
        lda CP_GROUP
    zuntil_eq
    pla
    rts
zendproc

; --- Data ------------------------------------------------------------------

.data

zp_base:    .byte __ZEROPAGE_START__
zp_end:     .byte __ZEROPAGE_END__
mem_base:   .byte __TPA0_START__@mos16hi, __TPA0_START__@mos16hi
mem_end:    .byte __TPA0_END__@mos16hi,   __TPA0_END__@mos16hi

file_table_lru: .fill NUM_FILES

NOINIT

; Currently used only by bdos_DELETE, which is a bit of a waste.
temp_fcb:        .fill FCB__SIZE

; Used everywhere.
temp_file_entry: .fill FT__SIZE
file_table:      .fill FT__SIZE * NUM_FILES


