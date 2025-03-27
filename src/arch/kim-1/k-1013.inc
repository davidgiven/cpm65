; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

; K-1013 FDC registers

HSRC = 0xffe8           ; R/W   - K-1003 Hardware Status Register
ADMA = 0xffea           ; Write - K-1013 Set DMA Address Register
MSTR = 0xffee           ; Read  - NEC-765 Main Status Register
DATR = 0xffef           ; R/W   - NEC-765 Data Register

;Some bits form the status registers

; Status Register 0
;
ST0_NOT_READY           = 0b00001000
ST0_DRIVE_NUMBER_MASK   = 0b00000011

; Status Register 3 (for Sense Drive Status)
;
ST3_RY                  = 0b00100000


;Extended command set

EXT_CMD_DIR         = 0b00000000
EXT_CMD_NXT         = 0b00000100
EXT_CMD_MNTS        = 0b00001000
EXT_CMD_NXT_MNT     = 0b00001100
EXT_CMD_NEW         = 0b00010000
EXT_CMD_ERA         = 0b00010100
EXT_CMD_CPY         = 0b00011000
EXT_CMD_MOV         = 0b00011100
EXT_CMD_MNT         = 0b00100000
EXT_CMD_UMNT        = 0b00100100

ST4_UNSUPPORTED     = 0b10000000
ST4_ABNORMAL_TERM   = 0b01000000
ST4_INVALID_CMD     = 0b00100000
ST4_BAD_PARAM       = 0b00010000
ST4_NOT_FOUND       = 0b00001000
ST4_INVLD_DRV       = 0b00000100
ST4_NOT_OPEN        = 0b00000010
ST4_NO_DATA         = 0b00000001
ST4_NORMAL_TERM     = 0b00000000

ST5_DRV_MOUNTED     = 0b00000001
ST5_DRV_NOT_MOUNTED = 0b00000010
ST5_IMG_MOUNTED     = 0b00000100
ST5_IMG2_MOUNTED    = 0b00001000
ST5_IMG_NAME        = 0b00010000
ST5_IMG_INVALID     = 0b00100000
ST5_IMG_EXISTS      = 0b01000000
ST5_DISK_FULL       = 0b10000000

PACKAGED_IMG        = 0b10000000

; Disk buffer

DISK_BUFFER = $fe00
BUFFER_DMA  = $f8       ; Disk buffer address DMA encoded (see K-1013 manual)
