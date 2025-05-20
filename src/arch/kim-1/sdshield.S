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
; 12/26/2024 - Eduardo Casino
;       Adapted to the 6502
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
; This is a low level disk function for a real OS to
; perform a disk sector read.  On entry, zp_sds_dpb
; is a disk parameter block with the following fields:
;
;    drive             DS   1
;    track             DS   1
;    sector            DS   1
;    sectors per track DS   1
;    ptr to data       DS   2   must be 256 bytes long!
;
; The first three fields are zero based.  Sectors per
; track is a one based value.
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc DiskReadSector, .text.DiskReadSector
    lda #PC_RD_SECTOR       ;sector read command
    jsr Dsendinfo
;
; Now get the response.  Will be either a NAK followed
; by an error code, or a 97 followed by 256 bytes of
; data.
;
    jsr xParSetRead
    jsr xParReadByte        ;response
    cmp #PR_SECTOR_DATA     ;data?
    bne DiskRetErrCode      ;no

; Read 256 bytes to the address at zp_sd_address

    ldy #0
    zrepeat
        jsr xParReadByte
        sta (zp_sds_buffer),y
        iny
    zuntil_eq
;
; All done
;
zendproc
; Fall through
zproc DiskCsuccess, .text.DiskCsuccess
    jsr xParSetWrite
    clc
    rts
zendproc

;=====================================================
; This is a low level disk function for a real OS to
; perform a disk sector write.  On entry, zp_sds_dpb is
; a disk parameter block with the following fields:
;
;    drive             DS   1
;    track             DS   1
;    sector            DS   1
;    sectors per track DS   1
;    ptr to data       DS   2   must be 256 bytes long!
;
; The first three fields are zero based.  Sectors per
; track is one based.
;
; Returns with C clear on success.  If error, C is set
; and A contains the error code.
;
zproc DiskWriteSector, .text.DiskWriteSector
    lda #PC_WR_SECTOR       ;write sector command
    jsr Dsendinfo
    ldy #0
    zrepeat
        lda (zp_sds_buffer),y
        jsr xParWriteByte
        iny
    zuntil_eq
;
; Now get response.
;
    jsr xParSetRead
    jsr xParReadByte
    cmp #PR_NAK             ;NAK?
    bne DiskCsuccess
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
;
;=====================================================
; This is a helper function for the read and write
; functions.  Enter with A containing the command to
; be sent, X pointing to the data area.  This sends
; the command, then the drive, track, sector and
; sectors per track from the data area.
;
; This must not modify the FCB!  The caller might
; depend on the values in it.
;
; This also de-Flexes the sector number.  Ie, any
; track other than 0 and any sector on track zero
; greater than one has one subtraced from it.
;
zproc Dsendinfo, .text.Dsendinfo
    jsr xParWriteByte           ;command
    lda zp_sds_drive            ;get drive
    jsr xParWriteByte           ;drive
    lda #2                      ;256 byte sectors
    jsr xParWriteByte
    lda zp_sds_track            ;get track
    jsr xParWriteByte           ;track
    lda zp_sds_sector           ;get sector
    jsr xParWriteByte           ;sector
    lda zp_sds_spt              ;get tracks/sector
    jmp xParWriteByte
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
    jsr xParReadByte        ;get result code (always PR_STATUS)
    jsr xParReadByte        ;get status byte
    pha
    jsr xParSetWrite
    pla
    clc
    rts
zendproc

