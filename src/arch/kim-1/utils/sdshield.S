;=====================================================
; This is a collection of functions for performing
; higher level disk functions.  This hides the nasty
; details of communications with the remote disk
; system.
;
; August 20, 2014 - Bob Applegate
;                   bob@corshamtech.com
;
; 06/14/2015 - Bob Applegate
;       Now that there is an official standard
;       for the protocol between the host (this
;       code) and the DCP (Arduino code), this
;       code has been updated to be compliant.
;
; 01/13/2025 - Eduardo Casino
;       Adapted some functions to the 6502.
;       Implemented DiskFormat, GetVersion, GetProtocol,
;       DiskErase, DiskCopy, DiskRename
;       Fixed error return for read/write
;

#include "zif.inc"
#include "parproto.inc"

.section .zp, "zax", @nobits

.global zp_sds_dpb, zp_sds_drive, zp_sds_track, zp_sds_sector
.global zp_sds_spt, zp_sds_buffer

; Disk parameter block

zp_sds_dpb:
zp_sds_drive:           .fill 1
zp_sds_track:           .fill 1
zp_sds_sector:          .fill 1
zp_sds_spt:             .fill 1     ; Sectors per track
zp_sds_buffer:          .fill 2     ; Pointer to data buffer

;=====================================================
; Unmount a filesystem.  On entry, A contains the
; zero-based drive number.
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc DiskUnmount, .text.DiskUnmount
    pha                     ;save drive
    lda #PC_UNMOUNT
    jsr xParWriteByte
    pla
    jsr xParWriteByte
zendproc
; Fall through
;
; Handy entry point.  This sets the mode to read, gets
; an ACK or NAK, and if a NAK, gets the error code
; and returns it in A.
;
zproc ComExit, .text.ComExit
    jsr xParSetRead         ;get ready for response
    jsr xParReadByte
    cmp #PR_ACK
    beq DiskCsuccess
zendproc
; Fall through
zproc DiskRetErrCode, .text.DiskRetErrCode
    ;
    ; Assume it's a NAK.
    ;
    jsr xParReadByte        ;get error code
    pha
    jsr xParSetWrite
    pla
    sec
    rts
zendproc

zproc DiskCerror, .text.DiskCerror
    jsr xParSetWrite
    sec
    rts
zendproc

zproc DiskCsuccess, .text.DiskCsuccess
    jsr xParSetWrite
    clc
    rts
zendproc

;=====================================================
; Mount a filesystem.  On entry, A contains a zero
; based drive number, X is the read-only flag (0 or
; non-zero), and zp_sds_buffer points to a filename to
; mount on that drive.  
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc DiskMount, .text.DiskMount
    pha                     ;save drive
    lda #PC_MOUNT
    jsr xParWriteByte       ;send the command
    pla
    jsr xParWriteByte       ;send drive number
    txa
    jsr xParWriteByte       ;send read-only flag
    ;
    ; Now send each byte of the filename until the end,
    ; which is a 0 byte.
    ;
    ldy #0
    zrepeat
        lda (zp_sds_buffer),y
        pha
        jsr xParWriteByte
        iny
        pla
    zuntil_eq
    jmp ComExit
zendproc

;=====================================================
; remove a file from the SD.  On entry, zp_sds_buffer
; points to a null-terminated file name
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc DiskErase, .text.DiskErase
    lda #PC_ERASE
    jsr xParWriteByte       ;send the command
    ;
    ; Now send the filename
    ;
    ldy #0
    jsr SendString
    jmp ComExit
zendproc

; Sends string to the SD shield
; Y = Start of string in buffer
; On exit, Y points to the first byte after the
; terminating null, so it can be chained
;
zproc SendString, .text.SendString
    zrepeat
        lda (zp_sds_buffer),y
        pha
        jsr xParWriteByte
        iny
        pla
    zuntil_eq
    rts
zendproc

;=====================================================
; Copy a file on the SD.  On entry, zp_sds_buffer
; points to a succession of two null-terminated file
; names
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc DiskCopy, .text.DiskCopy
    lda #PC_COPY
    jsr xParWriteByte       ;send the command

    ;
    ; Now send each byte of both filenames
    ;
    ldy #0
    jsr SendString
    jsr SendString
    jmp ComExit
zendproc

;=====================================================
; Rename a file on the SD.  On entry, zp_sds_buffer
; points to a succession of two null-terminated file
; names
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc DiskRename, .text.DiskRename
    lda #PC_RENAME
    jsr xParWriteByte       ;send the command

    ;
    ; Now send each byte of both filenames
    ;
    ldy #0
    jsr SendString
    jsr SendString
    jmp ComExit
zendproc

;=====================================================
; This starts a directory read of the raw drive, not
; the mounted drive.  No input parameters.  This simply
; sets up for reading the entries, then the user must
; read each entry.
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc DiskDir, .text.DiskDir
    lda #PC_GET_DIR         ;send command
    jmp xParWriteByte
    clc                     ;assume it works
    rts
zendproc

;=====================================================
; Read the next directory entry.  On input, zp_sds_buffer
; points to a 13 byte area to receive the drive data.
;
; Returns C set if end of directory (ie, attempt to
; read and there are none left).  Else, C is clear
; and zp_sds_buffer point to the null at end of filename.
;
zproc DiskDirNext, .text.DiskDirNext
    jsr xParSetRead         ;read results
    jsr xParReadByte        ;get response code
    cmp #PR_NAK             ;error?
    beq DiskRetErrCode
    cmp #PR_DIR_END         ;end?
    ;
    ; Error.  Set C and return.  This is not really
    ; proper, since this implies a simple end of the
    ; directory rather than an error.
    ;
    beq DiskCerror
    ;
    ; This contains a directory entry.
    ;
    ldy #0
    zloop
        jsr xParReadByte
        sta (zp_sds_buffer),y
        zbreakif_eq
        inc zp_sds_buffer
        zcontinueif_ne
        inc zp_sds_buffer+1
    zendloop
        jmp DiskCsuccess     
zendproc

;=====================================================
; Get list of mounted drives.  This starts the
; process, then each call to DiskNextMountedDrv will
; return the next drive in sequence.
;
zproc DiskGetMounted, .text.DiskGetMounted
    lda #PC_GET_MOUNTED     ;start command
    jmp xParWriteByte
zendproc

;=====================================================
; Get next mounted drive.  On entry, zp_sds_buffer points
; to a XXX byte area to receive the data.  Each call
; loads the area with:
;
; Drive number - 1 byte
; Read-only flag.  0 = read/write, non-zero = read-only
; File name    - X bytes of filename (xxxxxxxx.xxx)
; null         - 1 byte ($00)
;
; If C is clear, then the data area is populated with
; data.  If C is set, then there are no more entries.
;
zproc DiskNextMountedDrv, .text.DiskNextMountedDrv
    jsr xParSetRead
    jsr xParReadByte
    cmp #PR_DIR_END         ;end?
    zif_eq
        jmp DiskCerror
    zendif
    cmp #PR_NAK             ;NAK?
    zif_eq
        jmp DiskRetErrCode
    zendif
;
; Get drive number, then read-only flag
;
    jsr xParReadByte        ;drive
    ldy #0
    sta (zp_sds_buffer),y
    iny
    jsr xParReadByte        ;read-only flag
    sta (zp_sds_buffer),y
    zrepeat
        iny
        jsr xParReadByte
        sta (zp_sds_buffer),y
    zuntil_eq
    jmp DiskCsuccess
zendproc

;=====================================================
; Gets status of a specific drive.  The drive number
; (0-3) is in A on entry.
;
; Returns a bitmapped value in A:
;
;    P0000ERU
;
;  U: 0 = not present, 1 = Mounted
;  R: 0 = Read only, 1 = Read/write
;  E: 0 = no error, 1 = access error (bad sector?)
;
; The E bit will never be set for status.
;
zproc DiskStatus, .text.DiskStatus
    pha
    lda #PC_GET_STATUS      ;get status command
    jsr xParWriteByte       ;send request for data
    pla
    jsr xParWriteByte
    jsr xParSetRead
    jsr xParReadByte        ;get result code
    cmp #PR_STATUS          ;status
    zif_ne
        jmp DiskCerror      ;can't be anything else
    zendif
    jsr xParReadByte
zendproc
; Fall through
zproc DiskRetSt, .text.DiskRetSt
    pha
    jsr xParSetWrite
    pla
    clc
    rts
zendproc

;=====================================================
; This opens a file on the SD for writing.  On entry,
; zp_sds_buffer points to a null-terminated
; filename to open.  On return, C is clear if the file
; is open, or C set if an error.
;
; Assumes write mode has been set.  Returns with it set.
;
zproc DiskOpenWrite, .text.DiskOpenWrite
    lda #PC_WRITE_FILE
zendproc
zproc DiskOpen, .text.DiskOpen
    jsr xParWriteByte
    ldy #0xff
    zrepeat
        iny
        lda (zp_sds_buffer),y
        pha
        jsr xParWriteByte
        pla
    zuntil_eq
    jmp ComExit
zendproc

;=====================================================
; On entry, A contains the number of bytes to write
; to the file, zp_sds_buffer points to the
; buffer where to get the data.  On return, C will
; be set if an error was detected, or C will be clear
; if no error.  Note that if A contains 0 on entry,
; no bytes are written.
;
; 
; Modifies A, X and Y.
;
zproc DiskWrite, .text.DiskWrite
    zif_eq
        clc
        rts
    zendif
    pha                     ; Save number of bytes to write
    lda #PC_WRITE_BYTES
    jsr xParWriteByte       ;command
    pla                     ;number of bytes to write
    pha                     ;save again
    jsr xParWriteByte
    pla
    tax                     ;count
    ldy #0                  ;offset
    zrepeat
        lda (zp_sds_buffer),y ;get next byte
        jsr xParWriteByte
        iny                 ;next offset
        dex
    zuntil_eq
    jmp ComExit
zendproc

;=====================================================
; Call this to close any open file.  No parameters
; and no return status.
;
zproc DiskClose, .text.DiskClose
    lda #PC_DONE
    jmp xParWriteByte
zendproc

;=====================================================
; This formats a drive.  On entry, zp_sds_dpb is a disk
; parameter block with the following data fields:
;
;                      DS   1   ;unused
;    number of tracks  DS   1
;    number of sectors DS   1   ;sectors per track
;    sector fill value DS   1
;    ptr to filename   DS   2
;
; If the number of tracks or number of sectors is
; zero, then that indicates a value of 256.
;
; This only creates an empty file of the appropriate
; size; it does not initialize any data structures.
;
zproc DiskFormat, .text.DiskFormat
    lda #PC_FORMAT          ;format sector command
    jsr xParWriteByte
    lda zp_sds_track        ;get number of tracks
    jsr xParWriteByte
    lda zp_sds_sector       ;get sectors per track (beware the fields in
    jsr xParWriteByte       ;this file parameter block have different meaning!)
    lda zp_sds_spt          ;get filler byte
    jsr xParWriteByte
    ldy #0xff               ;get null-terminated file name
    zrepeat             
        iny
        lda (zp_sds_buffer),y
        pha
        jsr xParWriteByte
        pla
    zuntil_eq
    jmp ComExit
zendproc

;=====================================================
; Gets protocol version information from the SD Shield.
;
; Returns C clear and proto version in A on success,
; C set if failure
;
zproc GetProtoVersion .text.GetProtoVersion
    lda #PR_VERSION_INFO    ; Get protocol version information
    jsr xParWriteByte
;
; Now get response.
;
    jsr xParSetRead
    jsr xParReadByte
    cmp #PR_VERSION_INFO
    zif_eq
        jsr xParReadByte    ; Get protocol version
        jmp DiskRetSt       ; Return preserving A
    zendif
    jmp DiskCerror          ; Should not happen

;=====================================================
; Gets version information from the SD Shield.
;
; WARNING: Works with protocol version 2
;
; Returns C clear and major/minor in XA on success,
; C set if failure
;
zproc GetVersion, .text.GetVersion
    lda #PC_GET_VERSION     ; Get version information
    jsr xParWriteByte
;
; Now get response.
;
    jsr xParSetRead
    jsr xParReadByte
    cmp #PR_VERSION_INFO
    zif_eq
        jsr xParReadByte    ; Get major
        tax
        jsr xParReadByte    ; Get minor
        jmp DiskRetSt       ; Return preserving A
    zendif
    jmp DiskCerror
zendproc

;=====================================================
; Save current configuration in the SD card config file
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc SaveConfig, .text.SaveConfig
    lda #PC_SAVE_CONFIG
    jsr xParWriteByte       ;send the command
    jmp ComExit
zendproc

;=====================================================
; Get the maximum number of drives supported.  This
; takes no input parameters.  Returns a value in A
; that is the number of drives supported.  This is a
; one based value, so a return of 4 indicates that four
; drives are supported, 0 to 3.
;
; NOTE: Eduardo: May implement the real function in the
;       future. Now, just return 4, which are the drives
;       supported by current firmware
;
zproc DiskGetDrives, .text.DiskGetDrives
    lda	#4
    clc
	rts
zendproc