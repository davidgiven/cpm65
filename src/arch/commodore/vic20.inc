TEXT = 0x1000
FRAMEBUFFER = 0x1100
COLOURRAM = 0x9400

VIA1     = 0x9110
VIA1_PB  = VIA1 + 0x0
VIA1_PA  = VIA1 + 0x1
VIA1_PCR = VIA1 + 0xc
VIA1_DRA = VIA1 + 0xf

VIA1_PA_CLOCK_IN    = 1<<0
VIA1_PA_DATA_IN     = 1<<1
VIA1_PA_JOY0_IN     = 1<<2
VIA1_PA_JOY1_IN     = 1<<3
VIA1_PA_JOY2_IN     = 1<<4
VIA1_PA_LIGHTPEN_IN = 1<<5
VIA1_PA_CASSETTE_IN = 1<<6
VIA1_PA_ATN_OUT     = 1<<7

VIA2      = 0x9120
VIA2_PB   = VIA2 + 0x0
VIA2_PA   = VIA2 + 0x1
VIA2_T2CL = VIA2 + 0x8
VIA2_T2CH = VIA2 + 0x9
VIA2_PCR  = VIA2 + 0xc
VIA2_IFR  = VIA2 + 0xd
VIA2_DRA  = VIA2 + 0xf

VIA2_IFR_T2 = 1<<5

VIA2_PCR_CA1_CASSETTE_IN = 1<<0
VIA2_PCR_CA2_CLOCK_OUT   = 1<<1 ; set to %110 or %111
VIA2_PCR_CB1_SRQ_IN      = 1<<4
VIA2_PCR_CB2_DATA_OUT    = 1<<5 ; set to %110 or %111

STATUS  = 0x90
SA = 0xb9
FA = 0xba

VICPALNTSC = $ede4 ; PAL=$0c, NTSC=$05
SENDSECOND = $f495
CLOSECURR = $f6da
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

