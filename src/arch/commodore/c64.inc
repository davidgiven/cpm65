SENDSECOND = $f3d5
CLOSECURR = $f642
READST = $ffb7
SETLFS = $ffba
SETNAM = $ffbd
OPEN = $ffc0
CLOSE = $ffc3
CHKIN = $ffc6
CHKOUT = $ffc9
CHRIN = $ffcf
CHROUT = $ffd2
LOAD = $ffd5
SAVE = $ffd8
CLALL = $ffe7
SETMSG = $ff90
ACPTR = $ffa5
CIOUT = $ffa8
UNTALK = $ffab
UNLSN = $ffae
LISTEN = $ffb1
TALK = $ffb4
SECOND = $ff93
TALKSA = $ff96
CLRCHN = $ffcc
GETIN = $ffe4
CLEAR_SCREEN = $e544
MOVE_CURSOR = $e56c 
SHOW_CURSOR = $cc
CURSOR_X = $d3
CURSOR_Y = $d6
SA = $b9
FA = $ba
STATUS = $90

MMU = 1

SCREEN_CONTROL = 0xd011
SCREEN_RASTER = 0xd012
COLOUR_RAM = 0xd800

CIA1_PA = 0xdc00
CIA1_PB = 0xdc01
CIA1_DA = 0xdc02
CIA1_DB = 0xdc03
CIA2_PA = 0xdd00
CIA2_PB = 0xdd01
CIA2_DA = 0xdd02
CIA2_DB = 0xdd03

SCREEN_WIDTH=40
SCREEN_HEIGHT=25 
VIDEO = $0400

.macro set1 port, bit
    lda \port
    ora #\bit
    sta \port
.endm

.macro set0 port, bit
    lda \port
    and #(~(\bit)) & 0xff
    sta \port
.endm

.macro set10 port, bitson, bitsoff
    lda \port
    ora #\bitson
    and #(~(\bitsoff)) & 0xff
    sta \port
.endm


