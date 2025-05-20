;*****************************************************
; Parallel port protocol
;
; This is the header file for making applications
; compliant with The Remote Disk Protocol Guide which
; is on the Corsham Technologies web page somewhere:
;
;    www.corshamtech.com
;
; This was updated 06/13/2015 to be compliant with the
; official specification, so the opcode values changed.
;
; Another update on 02/10/2019
;
;=====================================================
; Commands from host to Arduino
;
PC_GET_VERSION  = $01
PC_PING         = $05       ;ping Arduino
PC_LED_CONTROL  = $06       ;LED control
PC_GET_CLOCK    = $07       ;get clock data
PC_SET_CLOCK    = $08       ;set clock
PC_GET_DIR      = $10       ;Get directory
PC_GET_MOUNTED  = $11       ;Get mounted drive list
PC_MOUNT        = $12       ;Mount drive
PC_UNMOUNT      = $13       ;Unmount drive
PC_GET_STATUS   = $14       ;Get status for one drive
PC_DONE         = $15       ;Stop data
PC_ABORT        = PC_DONE
PC_READ_FILE    = $16       ;Read regular file (non-DSK)
PC_READ_BYTES   = $17       ;Read s=ential bytes
PC_RD_SECTOR    = $18       ;Read FLEX sector
PC_WR_SECTOR    = $19       ;Write FLEX sector
PC_GET_MAX      = $1a       ;Get maximum drives
PC_WRITE_FILE   = $1b       ;Open file for writing
PC_WRITE_BYTES  = $1c       ;Data to be written
PC_SAVE_CONFIG  = $1d       ;Save SD.CFG with current values
PC_SET_TIMER    = $1e       ;Set RTC timer
PC_RD_SEC_LONG  = $1f       ;Read sector with long sec num
PC_WR_SEC_LONG  = $20       ;Write sector with long sec num
PC_FORMAT       = $21       ;Format (create) new image
PC_ERASE        = $22       ;Delete file from SD       
PC_RENAME       = $23       ;Rename file on SD
PC_COPY         = $24       ;Copy file on SD
;
;=====================================================
; Responses from Arduino to host
;
PR_VERSION_INFO = $81       ;Contains version information
PR_ACK          = $82       ;ACK (no additional information)
PR_NAK          = $83       ;NAK - one status byte follows
PR_PONG         = $85       ;Reply to a ping
PR_CLOCK_DATA   = $87       ;Clock data
PR_DIR_ENTRY    = $90       ;Directory entry
PR_DIR_END      = $91       ;End of directory entries
PR_FILE_DATA    = $92       ;File data
PR_STATUS       = $93       ;Drive status
PR_SECTOR_DATA  = $94       ;Sector data
PR_MOUNT_INFO   = $95       ;Mount entry
PR_MAX_DRIVES   = $96       ;Maximum number of drives
;
;=====================================================
; Error codes for NAK events
;
ERR_NONE             = 0
ERR_FEATURE_DISABLED = 8
ERR_FILE_EXISTS      = 9
ERR_NOT_MOUNTED      = 10
ERR_MOUNTED          = 11
ERR_NOT_FOUND        = 12
ERR_READ_ONLY        = 13
ERR_BAD_DRIVE        = 14
ERR_BAD_TRACK        = 15
ERR_BAD_SECTOR       = 16
ERR_READ_ERROR       = 17
ERR_WRITE_ERROR      = 18
ERR_NOT_PRESENT      = 19
ERR_NOT_IMPL         = 20        ;Command not implemented
