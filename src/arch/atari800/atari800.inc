; Atari 800 OS defines

PTEMP  = $1f    ; P: handler temporary we can use freely, unless we print
FMSZPG = $43    ; FMS zero page, but we don't use Atari DOS.SYS (7 bytes)

POKMSK  = $10
RTCLOK  = $12

FONT    = $e000
FONTEND = $e400
TMPFONT = $8000             ; somewhere non-intruding
TMPFONTEND = $8400

COLPF2  = $d018
COLPM0  = $d012
KBCODE  = $d209
IRQST   = $d20e
IRQEN   = $d20e
SKSTAT  = $d20f
PORTB   = $d301
DMACTL  = $d400
DLISTL  = $d402
DLISTH  = $d403
CHBASE  = $d409
NMIEN   = $d40e
NMIRES  = $d40f
NMIST   = $d40f
NMIVEC  = $fffa
RESVEC  = $fffc
IRQVEC  = $fffe

VKEYBD  = $0208
VVBLKI  = $0222
SRTIMR  = $022b
SDMCTL  = $022f
SDLSTL  = $0230
SDLSTH  = $0231
SHFLOK  = $02be
PCOLOR0 = $02c0
CHBAS   = $02f4
FILDAT  = $02fd
KRPDEL  = $02d9
KEYREP  = $02da
KEYDEL  = $02f1
CH1     = $02f2
CH      = $02fc
RAMSIZ  = $02e4
MEMTOP  = $02e5

CIOV = $e456

ICHID = $0340
ICDNO = $0341
ICCOM = $0342
ICSTA = $0343
ICBAL = $0344
ICBAH = $0345
ICPTL = $0346
ICPTH = $0347
ICBLL = $0348
ICBLH = $0349
ICAX1 = $034a
ICAX2 = $034b
ICAX3 = $034c
ICAX4 = $034d
ICAX5 = $034e
ICAX6 = $034f

COPEN = 3
CCLSE = 12
CGTXT = 5
CPTXT = 9
CGBIN = 7
CPBIN = 11

ATARI_ESC         = 27
ATARI_UP_ARROW    = 28
ATARI_DOWN_ARROW  = 29
ATARI_LEFT_ARROW  = 30
ATARI_RIGHT_ARROW = 31
ATARI_CLS      = 125
ATARI_BS       = 126
ATARI_TAB      = 127
ATARI_EOL      = 155
ATARI_DEL_LINE = 156
ATARI_INS_LINE = 157
ATARI_BEL      = 253
ATARI_DEL      = 254
ATARI_INS      = 255

TERM_BEL = 7
TERM_BS  = 8
TERM_TAB = 9
TERM_LF  = 10
TERM_CLS = 26
TERM_CR  = 13
TERM_DEL = 127

LMARGN  = $52
ROWCRS  = $54
COLCRS  = $55
SAVMSC  = $58
COLOR1  = $02c5
COLOR2  = $02c6
COLBK   = $02c8

; SIO Device Control Block

DDEVIC  = $0300
DUNIT   = $0301
DCOMND  = $0302
DSTATS  = $0303
DBUFLO  = $0304
DBUFHI  = $0305
DTIMLO  = $0306
DBYTLO  = $0308
DBYTHI  = $0309
DAUX1   = $030a
DAUX2   = $030b

SIO_READ_SECTOR  = $52
SIO_WRITE_SECTOR = $50

SIOV = $e459

