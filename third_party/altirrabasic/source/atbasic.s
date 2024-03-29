; Altirra BASIC
; Copyright (C) 2014-2016 Avery Lee, All Rights Reserved.
;
; Copying and distribution of this file, with or without modification,
; are permitted in any medium without royalty provided the copyright
; notice and this notice are preserved.  This file is offered as-is,
; without any warranty.

        icl     'system.inc'
        icl     'tokens.inc'
        icl     'cpm65.inc'

;===========================================================================
.macro _MSG_BANNER
        dta     c'Altirra 8K BASIC 1.58 CP/M-65 version', 13, 10
        dta     c'This port is not supported by the', 13, 10
        dta     c'Altirra project. Do not contact them', 13, 10
        dta     c'about bugs.', 13, 10
.endm

;===========================================================================
; Zero page variables
;
; We try to be sort of compatible with Atari BASIC here, supporting all
; public variables and trying to support some unofficial usage as well.
;
; Test cases:
;   QUADRATO.BAS
;   - Uses $B0-B3 from USR() routine

        org ZPBASE
        opt     o-
_zp_start:
; These must be contiguous as they're loaded and saved with programs.
argstk  equ     *
lomem   dta     a(0)        ;$0080 (compat) from lomem; argument/operator stack
vntp    dta     a(0)        ;$0082 (compat - loaded) variable name table pointer
vntd    dta     a(0)        ;$0084 (compat - loaded) variable name table end
vvtp    dta     a(0)        ;$0086 (compat - loaded) variable value table pointer
stmtab  dta     a(0)        ;$0088 (compat - loaded) statement table pointer
stmcur  dta     a(0)        ;$008A (compat - loaded) current statement pointer
starp   dta     a(0)        ;$008C (compat - loaded) string and array table
runstk  dta     a(0)        ;$008E (compat) runtime stack pointer
memtop2 dta     a(0)        ;$0090 (compat) top of BASIC memory

exLineOffset    dta     0       ;offset within current line being executed
exLineOffsetNxt dta     0       ;offset of next statement
exLineEnd       dta     0       ;offset of end of current line
exTrapLine      dta     a(0)    ;TRAP line
exFloatStk      dta     0       ;bit 7 set if stack is floating (line numbers)
parPtrSav:                  ;[6 bytes] VNTD/VVTP/STMTAB save area for parser rollback
opsp        dta     0       ;operand stack pointer offset
argsp       dta     0       ;argument stack pointer offset
expCommas   dta     0       ;expression evaluator comma count
expFCommas  dta     0
expAsnCtx   dta     0       ;flag - set if this is an assignment context for arrays
expType     dta     0       ;bit 7 = 0 for numeric, 1 for string
varptr      dta     a(0)    ;pointer to current variable
lvarptr     dta     a(0)    ;lvar pointer for array assignment
parptr      dta     a(0)    ;parsing state machine pointer
parout      dta     0       ;parsing output idx
expCurPrec  dta     0       ;expression evaluator current operator precedence
iocbexec    dta     0       ;current immediate/deferred mode IOCB
iocbidx     dta     0       ;current IOCB*16
iocbidx2    dta     0       ;current IOCB (used to distinguish #0 and #16)
iterPtr     dta     a(0)    ;pointer used for sequential name table indexing
ioPrintCol  dta     0       ;IO: current PRINT column
ioTermSave  dta     0       ;IO: String terminator byte save location
ioTermOff   dta     0       ;IO: String terminator byte offset
argstk2     dta     a(0)    ;Evaluator: Second argument stack pointer
dataLnEnd   dta     0       ;current DATA statement line end
pmgbase     dta     0
pmgmode     dta     0
ioTermFlag  dta     0
            dta     a(0)    ; mathpack_data-2 is used by the parser code...
mathpack_data .ds mathpack_data_len

dataln      dta     a(0)    ;(compat - Mapping the Atari / ANALOG verifier) current DATA statement line
stopln      dta     0       ;(compat - Atari BASIC manual): line number of error
        
;--------------------------------------------------------------------------
; $BC-BF are reserved as scratch space for use by the currently executing
; statement or by the parser. They must not be used by functions or library
; code.
;
stScratch   dta     0
stScratch2  dta     0
stScratch3  dta     0
stScratch4  dta     0

printDngl   = stScratch     ;set if the print statement is 'dangling' - no follow EOL
parStrType  = prefr0        ;parsing string type: set if string exp, clear if numeric
parStBegin  = stScratch2    ;parsing offset of statement begin (0 if none)

;--------------------------------------------------------------------------
; $C0-C1 are reserved as scratch space for use by the currently executing
; function.
;
funScratch1 dta 0
funScratch2 dta 0
;--------------------------------------------------------------------------
errno   dta 0
errsave dta 0               ;(compat - Atari BASIC manual): error number

dataptr     dta     a(0)    ;current DATA statement pointer
dataoff     dta     0       ;current DATA statement offset
            dta     0       ;(unused)
ptabw       dta     0       ;(compat - Atari BASIC manual): tab width

; Floating-point library vars
;
; $D2-D3 is used as an extension prefix to FR0; $D4-FF are used by the FP
; library, but can be reused outside of it.
;
prefr0  = fr0-2
a0      = fr0               ;temporary pointer 0
a1      = fr0+2             ;temporary pointer 1
a2      = fr0+4             ;temporary pointer 2
a3      = fr0+6             ;temporary pointer 3
a4      = fr0+8             ;temporary pointer 4
a5      = fr0+10            ;temporary pointer 5

memtop  dta a(0)            ;address of top of memory
memlo   dta 0               ;page number of base of memory

.macro _STATIC_ASSERT
        .if :1
        .else
        .error ":2"
        .endif
.endm

.macro _PAGE_CHECK
        .if [:1^*]&$ff00
        .error "Page boundary crossed between ",:1," and ",*
        .endif
.endm

_zp_end:
    org TEXTBASE
    opt     o+
_text_start:
    
;==========================================================================
; CP/M-65 header and entrypoint
    dta _zp_end - _zp_start
    dta >(_text_end - _text_start + 255)
    dta a(_text_end)
BDOS:
    jmp 0x0000
;
.proc _entry
    ldy #BDOS_GETTPA
    jsr BDOS
    lda #0
    sta memtop+0
    stx memtop+1
    lda #>(_data_end + 256)
    sta memlo

    jsr initcio
;
;       ;check if there is a command line to process
;       ldy     #0
;       sty     iocbidx             ;!! - needed since we will be skipping it
;       lda     (dosvec),y
;       cmp     #$4c
;       bne     no_cmdline
;       ldy     #3
;       lda     (dosvec),y
;       cmp     #$4c
;       beq     have_cmdline
;no_cmdline:
;       lda     #0
;       jmp     no_filename
;
;have_cmdline:
;       ;skip spaces
;       ldy     #10
;       lda     (dosvec),y
;       clc
;       adc     #63
;       tay
;space_loop:
;       lda     (dosvec),y
;       cmp     #$9b
;       beq     no_filename
;       iny
;       cmp     #' '
;       beq     space_loop
;
;       ;stash filename base offset
;       dey
;       sty     fr0+3
;
;       ;check if the first character is other than D and there is a colon
;       ;afterward -- if so, we should skip DOS's parser and use it straight
;       ;as it may be a CIO filename that DOS would munge
;       cmp     #'D'
;       beq     possibly_dos_file
;cio_file:
;       ;copy filename to LBUFF
;       ldx     #0
;cio_copy_loop:
;       lda     (dosvec),y
;       sta     lbuff,x
;       inx
;       iny
;       cmp     #$9b
;       bne     cio_copy_loop
;
;       ;stash length
;       stx     fr0+2
;
;       tya
;       jmp     have_filename_nz
;
;possibly_dos_file:
;       ;scan for colon
;colon_loop:
;       lda     (dosvec),y
;       iny
;       cmp     #':'
;       beq     cio_file
;       cmp     #$9b
;       bne     colon_loop
;
;       ;okay, assume it's a DOS file - clear the CIO filename flag
;       lda     #0
;       sta     fr0+2
;       
;       ;try to parse out a filename
;       ldy     fr0+3
;       sec
;       sbc     #63
;       ldy     #10
;       sta     (dosvec),y
;
;       ldy     #4
;       mva     (dosvec),y fr0
;       iny
;       mva     (dosvec),y fr0+1
;       jsr     jump_fr0
;       
;no_filename:
;have_filename_nz:
;       ;save off filename flag
;       php

        ;cold boot ATBasic
        ldx     #1
        stx     errno

        ;print startup banner
        mwa     #msg_banner_begin icbal
        mwa     #msg_banner_end-msg_banner_begin icbll
        ldx     #0
        stx     iocbidx
        jsr     console_putchars

        jsr     _stNew.reset_entry
;       jsr     ExecReset
;
;       ;read filename flag
;       plp
;       bne     explicit_fn
;
;       ;no filename... try loading implicit file
;       ldx     #$70
;       stx     iocbidx
;       mwa     #default_fn_start icbal+$70
;       mwa     #default_fn_end-default_fn_start icbll+$70
;       mva     #CIOCmdOpen iccmd+$70
;       mva     #$04 icax1+$70
;       jsr     ciov
;       bmi     load_failed
;
;       ;load and run
;       lsr     stLoadRun._loadflg
;       jmp     stLoadRun.with_open_iocb
;
;load_failed:
;       ;failed... undo the EOL with an up arrow so the prompt is in the right place
;       mva     #0 iocbidx
;       lda     #$1c
;       jsr     putchar
;
;       ;close IOCB and jump to prompt
;       ldx     #$70
;       mva     #CIOCmdClose iccmd+$70
;       jsr     ciov
        jmp     immediateModeReset

;explicit_fn:
;       ;move filename to line buffer
;       ldy     #33
;       ldx     #0
;       stx     fr0+3
;
;       ;check if filename is already there
;       lda     fr0+2
;       bne     fncopy_skip
;fncopy_loop:
;       lda     (dosvec),y
;       sta     lbuff,x
;       cmp     #$9b
;       beq     fncopy_exit
;       iny
;       inx
;       bne     fncopy_loop
;fncopy_exit:
;       ;finish length
;       stx     fr0+2
;
;fncopy_skip:
;       ;set string pointer
;       mwa     #lbuff fr0
;
;       ;set up for RUN statement
;       jsr     IoPutNewline
;       lsr     stLoadRun._loadflg
;       ldx     #$70
;       stx     iocbidx
;       jmp     stLoadRun.loader_entry
;
;wait_vbl:
;       sei
;       mwa     #1 cdtmv3
;       cli
;       lda:rne cdtmv4
;       rts
;
;jump_fr0:
;       jmp     (fr0)
;
;editor:
;       dta     c'E',$9B
;
;default_fn_start:
;       dta     'D:AUTORUN.BAS',$9B
;default_fn_end:

msg_banner_begin:
        _MSG_BANNER
msg_banner_end:
.endp


;==========================================================================
; Entry point
;
; This is totally skipped in the EXE version, where we reuse the space for
; a reload-E: stub when returning to DOS.
;
ReturnToDOS:
        ldx     #0
        jsr     IoCloseX
        ldy     #BDOS_EXIT_PROGRAM
        jmp     BDOS

;==========================================================================
; Message base
;
msg_base:

msg_ready:
        dta     13, 10, c'Ready', 13, 10, 0

msg_stopped:
        dta     13, 10, c"Stopped", 0

msg_error:
        dta     13, 10, c"Error-   ",0

msg_atline:
        dta     c" at line ",0
msg_end:

        _STATIC_ASSERT (msg_end - msg_base) <= $100

;==========================================================================
immediateModeReset:
        jsr     ExecReset
immediateMode:
        ;use IOCB #0 (E:) for commands
        ldx     #0
        stx     iocbexec
.proc execLoop
        ;display prompt
        ldx     #msg_ready-msg_base
        jsr     IoPrintMessageIOCB0

loop2:  
        ;reset stack
        ldx     #$ff
        txs

        ;read read pointer
        inx
        stx     cix

        ;reset errno
        inx
        stx     errno
    
        ;read line
        ldx     iocbexec
        jsr     IoReadLineX         ;also sets iocbidx for error handling
        beq     eof
        
        ;float the stack if it isn't already
        jsr     ExecFloatStack

        ;##TRACE "Parsing immediate mode line: [%.*s]" dw(icbll) lbuff
        jsr     parseLine
        bcc     loop2       

        ;execute immediate mode line
        jmp     execDirect
        
eof:
        ;close IOCB #7
        jsr     IoSetupIOCB7        ;closes #7 as side effect
        
        ;restart in immediate mode with IOCB 0
        jmp     immediateMode
.endp
 
;==========================================================================

        icl     'parserbytecode.s'
        icl     'parser.s'
        icl     'exec.s'
        icl     'data.s'
        icl     'statements.s'
        icl     'evaluator.s'
        icl     'functions.s'
        icl     'variables.s'
        icl     'math.s'
        icl     'io.s'
        icl     'memory.s'
        icl     'list.s'
        icl     'error.s'
        icl     'util.s'
        icl     '../kernel/mathpack.s'
        icl     'cioemu.s'
        icl     'printerror.s'


;==========================================================================

pmg_dmactl_tab:                 ;3 bytes ($1c 0c 00)
        dta     $1c,$0c
empty_program:                  ;4 bytes ($00 00 80 03)
        dta     $00
pmgmode_tab:                    ;2 bytes ($00 80)
        dta     $00,$80
        dta     $03

;==========================================================================

        .pages 1

const_table:
        ;The Maclaurin expansion for sin(x) is as follows:
        ;
        ; sin(x) = x - x^3/3! + x^5/5! - x^7/7! + x^9/9! - x^11/11!...
        ;
        ;We modify it this way:
        ;
        ; let y = x / pi2 (for x in [0, pi], pi2 = pi/2
        ; sin(x) = y*[pi2 - y^2*pi2^3/3! + y^4*pi2^5/5! - y^6*pi2^7/7! + y^8*pi2*9/9! - y^10*pi2^11/11!...]
        ;
        ; let z = y^2
        ; sin(x) = y*[pi2 - z*pi2^3/3! + z^2*pi2^5/5! - z^3*pi2^7/7! + z^4*pi2*9/9! - z^5*pi2^11/11!...]
        ;
fpconst_sin:
        dta     $BD,$03,$43,$18,$69,$61     ;-0.00 00 03 43 18 69 61 07114469471
        dta     $3E,$01,$60,$25,$47,$91     ; 0.00 01 60 25 47 91 80067132008
        dta     $BE,$46,$81,$65,$78,$84     ;-0.00 46 81 65 78 83 6641486819
        dta     $3F,$07,$96,$92,$60,$37     ; 0.07 96 92 60 37 48579552158
        dta     $BF,$64,$59,$64,$09,$56     ;-0.64 59 64 09 55 8200198258
angle_conv_tab:
fpconst_pi2:
        dta     $40,$01,$57,$07,$96,$33     ; 1.57 07 96 32 67682236008 (also last sin coefficient)
        dta     $40,$90,$00,$00,$00         ; 90 (!! - last byte shared with next table!)
hvstick_table:
        dta     $00,$FF,$01,$00

fp_180_div_pi:
        .fl     57.295779513082

const_one:
        dta     $40,$01
pmg_move_mask_tab:
        dta     $00,$00,$00,$00,$fc,$f3,$cf,$3f
        .endpg
_text_end:
    
    opt o-
_data_start:
iocb_table:
    .ds 8 * $10

ichid   = iocb_table + $0       ;IOCB #0 handler ID
iccmd   = iocb_table + $1       ;IOCB #0 command byte
icsta   = iocb_table + $2       ;IOCB #0 status
icbal   = iocb_table + $3       ;IOCB #0 buffer address lo
icbah   = iocb_table + $4       ;IOCB #0 buffer address hi
icptl   = iocb_table + $5       ;IOCB #0 PUT address lo
icpth   = iocb_table + $6       ;IOCB #0 PUT address hi
icbll   = iocb_table + $7       ;IOCB #0 buffer length/byte count lo
icblh   = iocb_table + $8       ;IOCB #0 buffer length/byte count hi
icax1   = iocb_table + $9       ;IOCB #0 auxiliary information lo
icax2   = iocb_table + $a       ;IOCB #0 auxiliary information hi
icax3   = iocb_table + $b       ;
icax4   = iocb_table + $c       ;
icax5   = iocb_table + $d       ;
icax6   = iocb_table + $e       ;
icax7   = iocb_table + $f       ;

brkkey      dta 0       ; set on BREAK
; These must be consecutive as they're shared with the vector buffer.
_vectmp:
plyarg      .fl 0       ; mathpack polynomial arguments
fpscr       .fl 0       ; mathpack scratchpad
_fr3        .fl 0       ; mathpack temporary

lbuff:
    .ds 256
_data_end:

        end
