#include "../include/cpm65.inc"
#include "zif.inc"

; 1. Program storage
; 2. Editor
; 3. Interpreter
; 4. Variable storage
; 5. Correctness

; hi TPAEND
;             <-- progtop
;    comal bytecode
;             <-- progbase
;    stack
;             <-- stackptr
;
;             <-- heapptr
;    heap
;             <-- heapbase
;    interpreter and workspace
; lo TPABASE
; IMPORTANT --- remember how comparisons work!
;
; lda A
; cmp #NUM
; If the Z flag is 0, then A <> NUM and BNE will branch
; If the Z flag is 1, then A = NUM and BEQ will branch
; If the C flag is 0, then A (unsigned) < NUM (unsigned) and BCC will branch
; If the C flag is 1, then A (unsigned) >= NUM (unsigned) and BCS will branch

OBJECT_SIZE     = 0
OBJECT_TYPE     = 2
OBJECT_DATA     = 3

OTYPE_FREE      = 0
OTYPE_ATOM      = 1
OTYPE_INTEGER   = 2
OTYPE_VAR       = 3

HASH_SLOTS      = 16

; Hash node structure:
;  0..1 - object size
;  2    - object type
;  3..6 - data
;  7..8 - key
;  9..a - object ID of next node

HASHNODE_KEY    = 7
HASHNODE_NEXT   = 9
HASHNODE_SIZE   = 0xb

; Stack value structure:
;  0    - object type
;  1..4 - data

STACKVALUE_TYPE = 0
STACKVALUE_DATA = 1
STACKVALUE_SIZE = 5

; Program storage: a flat list of lines, each of which looks like:
;   0    - line size
;   1..2 - line number
;   3    - indentation
;   4... - data
; Lines should end in a TOKEN_EOL command (which may take a parameter).

LINE_SIZE       = 0
LINE_NUMBER     = 1
LINE_INDENT     = 3
LINE_DATA       = 4

; Run state flags.

RUNFLAG_RUNNING = 1<<0
RUNFLAG_STOPPED = 1<<1

ZEROPAGE

runflags:  .byte 0

heapptr:   .word 0
stackptr:  .word 0
progbase:  .word 0
progtop:   .word 0

p0:        .word 0
p1:        .word 0
p2:        .word 0
v0:        .byte 0
v1:        .byte 0
v2:        .byte 0
i0:        .word 0, 0 ; also, TOS when executing
i1:        .word 0, 0
i2:        .word 0, 0

bufferpos: .byte 0 ; current beginning of token in input buffer
bufferend: .byte 0 ; current end of token in input buffer

bytecodeptr:        .byte 0 ; used by parser and lister and editor
opstackptr:         .byte 0 ; operator stack pointer

; Parser temporaries

parsecmd:           .word 0 ; points into parser bytecode
parsefailstackptr:  .byte 0 ; stack pointer to rewind to
parsestartstackptr: .byte 0 ; stack pointer when parse starts

; Lister temporaries

listerroot:         .byte 0 ; address of topmost node
listersp:           .byte 0 ; SP when empty
listerflags:        .byte 0 ; flags

; Interpreter temporaries

execlineptr:        .word 0 ; line of code currently being run
execbyteptr:        .byte 0 ; offset into the line of code

LISTERFLAG_NOTSTART = 1<<7
LISTERFLAG_COMMA    = 1<<6

TOKEN_EOL       = 0x00 ; end of line
TOKEN_VARREF    = 0x01 ; +2 bytes for the ID
TOKEN_INTEGER   = 0x02 ; +4 bytes for the number
TOKEN_MUL       = 0x03
TOKEN_DIV       = 0x04
TOKEN_ADD       = 0x05
TOKEN_SUB       = 0x06
TOKEN_MOD       = 0x07
TOKEN_PRINT     = 0x08
TOKEN_PRINTNL   = 0x09
TOKEN_ASSIGN    = 0x0a
TOKEN_NEG       = 0x0b
TOKEN_LINEENTRY = 0x0c
TOKEN_ZERO      = 0x0d
TOKEN_LIST      = 0x0e
TOKEN_DEL       = 0x0f
TOKEN_MONE      = 0x10
TOKEN_RENUM     = 0x11
TOKEN_RUN       = 0x12
TOKEN_STOP      = 0x13
TOKEN_CON       = 0x14

.set tokenvalue, 0

.data 1
token_precedence_table:
.data 2
token_size_table:
.data 3
token_listers_hi:
.data 4
token_listers_lo:
.data 5
token_aux_hi:
.data 6
token_aux_lo:
.data 7
token_exec_hi:
.data 8
token_exec_lo:
.macro token_data token, precedence, tokensize, pops, pushes, lister, aux, exec
    .if \token != tokenvalue
        .error "Out of sequence token \token"
    .endif
    .data 1
    .byte \precedence
    .data 2
    .byte (\tokensize) | (\pops << 4) | (\pushes << 7)
    .data 3
    .byte (\lister-1)@mos16hi
    .data 4
    .byte (\lister-1)@mos16lo
    .data 5
    .byte \aux@mos16hi
    .data 6
    .byte \aux@mos16lo
    .data 7
    .byte (\exec-1)@mos16hi
    .data 8
    .byte (\exec-1)@mos16lo
    .set tokenvalue, tokenvalue+1
.endm
        
token_data TOKEN_EOL,       15, 1, 0, 0, lister_bad,     lister_bad,     exec_bad
token_data TOKEN_VARREF,    15, 3, 0, 1, lister_varref,  lister_bad,     exec_varref
token_data TOKEN_INTEGER,   15, 5, 0, 1, lister_integer, lister_bad,     exec_integer
token_data TOKEN_MUL,       10, 1, 2, 1, lister_infix,   keyword_mul,    exec_mul
token_data TOKEN_DIV,       10, 1, 2, 1, lister_infix,   keyword_div,    exec_div
token_data TOKEN_ADD,        9, 1, 2, 1, lister_infix,   keyword_add,    exec_add
token_data TOKEN_SUB,        9, 1, 2, 1, lister_infix,   keyword_sub,    exec_sub
token_data TOKEN_MOD,       10, 1, 2, 1, lister_infix,   keyword_mod,    exec_mod
token_data TOKEN_PRINT,      0, 1, 1, 0, lister_print,   lister_bad,     exec_print
token_data TOKEN_PRINTNL,    0, 1, 0, 0, lister_printnl, lister_bad,     exec_printnl
token_data TOKEN_ASSIGN,     0, 1, 2, 0, lister_assign,  keyword_assign, exec_assign
token_data TOKEN_NEG,       14, 1, 1, 1, lister_prefix,  keyword_neg,    exec_neg
token_data TOKEN_LINEENTRY,  0, 1, 1, 0, lister_nop,     lister_bad,     exec_lineentry
token_data TOKEN_ZERO,      15, 1, 0, 1, lister_simple,  keyword_zero,   exec_zero
token_data TOKEN_LIST,       0, 1, 2, 0, lister_nop,     lister_bad,     exec_list
token_data TOKEN_DEL,        0, 1, 2, 0, lister_nop,     lister_bad,     exec_del
token_data TOKEN_MONE,      15, 1, 0, 1, lister_simple,  keyword_mone,   exec_mone
token_data TOKEN_RENUM,      0, 1, 2, 0, lister_nop,     lister_bad,     exec_renum
token_data TOKEN_RUN,        0, 1, 0, 0, lister_nop,     lister_bad,     exec_run
token_data TOKEN_STOP,       0, 1, 0, 0, lister_simple,  keyword_stop,   exec_stop
token_data TOKEN_CON,        0, 1, 0, 0, lister_nop,     lister_bad,     exec_con

OBJECT_TABLE_SIZE = 256

zproc main
    jsr clear
zendproc
    ; fall through
zproc stack_destroyed
    lda progbase+0
    sta stackptr+0
    lda progbase+1
    sta stackptr+1

    lda #0
    sta runflags
zendproc
    ; fall through
zproc mainloop
    ldx #0xff
    txs

    zloop
        ; Read a line from the console.

        lda #'$'
        jsr bdos_CONOUT
        jsr print_space
        
        lda #255
        sta text_buffer+0
        lda #<text_buffer
        ldx #>text_buffer
        ldy #BDOS_READ_LINE
        jsr BDOS
        jsr print_nl

        ; Parse it.

        ldx text_buffer+1
        lda #0
        sta text_buffer+2, x

        lda #2
        sta bufferpos
        jsr parse_line

        ; Successful parse.

        lda #0
        sta p0+0
        zloop
            ldx p0+0
            cpx bytecodeptr
            zbreakif_eq

            lda bytecode_buffer, x
            jsr print_hex8_number
            jsr print_space

            inc p0+0
        zendloop
        jsr print_nl

        ; Print line back again.

        lda #0
        sta bufferpos
        sta bufferend

        lda #<bytecode_buffer
        sta execlineptr+0
        lda #>bytecode_buffer
        sta execlineptr+1
        lda #1
        sta execbyteptr
        jsr list_line
        jsr print_buffer
        jsr print_nl

        ; Run it.

        lda #<bytecode_buffer
        sta execlineptr+0
        lda #>bytecode_buffer
        sta execlineptr+1
        lda #1
        sta execbyteptr
        jsr exec_line
    zendloop
zendproc

zproc clear
    ; Initialise pointers.

    ldy #BDOS_GETTPA
    jsr BDOS
    stx progtop+1
    lda #0
    sta progtop+0

    lda #<heapbase
    sta heapptr+0
    lda #>heapbase
    sta heapptr+1

    sec
    lda progtop+0
    sbc #1
    sta progbase+0
    lda progtop+1
    sbc #0
    sta progbase+1

    lda #0
    tay
    sta (progbase), y

    rts
zendproc

; --- Debugging routines ----------------------------------------------------

; Prints a 16-bit hex number in XA.
zproc print_hex16_number
    pha
    txa
    jsr print_hex8_number
    pla
    jmp print_hex8_number
zendproc

; Prints an 8-bit hex number in A.
zproc print_hex8_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_hex4_number
    pla
print_hex4_number:
    and #$0f
    ora #'0'
    cmp #'9'+1
    zif_cs
        adc #6
    zendif
    pha
    jsr bdos_CONOUT
    pla
    rts
zendproc

; --- Output ----------------------------------------------------------------

; As for print_string, but puts a space after it.

zproc print_separated_string
    jsr print_string
zendproc
    ; fall through
zproc print_space
    lda #' '
    jmp bdos_CONOUT
zendproc

zproc print_nl
    lda #0x0d
    jsr bdos_CONOUT

    lda #0x0a
    jmp bdos_CONOUT
zendproc

; Prints the high-bit-terminated string in AX.

zproc print_string
    sta p0+0
    stx p0+1

    ldy #0xff
    sty p1+0

    zrepeat
        inc p1+0
        ldy p1+0
        lda (p0), y
        and #0x7f
        jsr bdos_CONOUT

        ldy p1+0
        lda (p0), y
    zuntil_mi

    rts
zendproc

; Prints the text buffer.

zproc print_buffer
    zloop
        ldx bufferpos
        cpx bufferend
        zbreakif_eq
    
        lda text_buffer, x
        jsr bdos_CONOUT

        inc bufferpos
    zendloop
    rts
zendproc

; Returns !C if not, C is it is.
; Preserves X and Y.
zproc isletter
    cmp #'A'
    bcc 1f
    cmp #'Z'+1
    bcc 2f
islower:
    cmp #'a'
    bcc 1f
    cmp #'z'+1
    bcc 2f
1:
    ; fail
    clc
    rts
2:
    ; succeed
    sec
    rts
zendproc

; Preserves X and Y.
zproc toupper
    jsr islower
    zif_cs
        eor #0x20
    zendif
    rts
zendproc

; --- Interpreter -----------------------------------------------------------

; Searches for line i0, and sets execlineptr to the address of the first line
; which is not less than that line number.
;
; Returns Z if the line was found, !Z if it wasn't (and the new line needs to
; be inserted).
 
zproc find_line
    ; Initialise search.

    lda progbase+0
    sta execlineptr+0
    lda progbase+1
    sta execlineptr+1

    ; Do a linear search through the program text.

    jmp 1f
    zrepeat
        ; Compare the line number.

        ldy #LINE_NUMBER+1
        lda (execlineptr), y
        cmp i0+1
        zif_eq              ; if high byte is =, test low byte
            dey
            lda (execlineptr), y
            cmp i0+0
        zendif
        zif_cs              ; is high byte >=?
            rts
        zendif

        ; Move to the next line.

        ldy #LINE_SIZE
        lda (execlineptr), y
        clc
        adc execlineptr+0
        sta execlineptr+0
        zif_cs
            inc execlineptr+1
        zendif

    1:
        ldy #LINE_SIZE
        lda (execlineptr), y
    zuntil_eq
            
    ; We didn't find the line. This means that all the lines in the program
    ; have a smaller line number than the one asked for. Return the address
    ; of the end marker.

    lda #1                  ; clear Z
    rts
zendproc

zproc goto_next_line
    ldy #LINE_SIZE
    lda (execlineptr), y

    clc
    adc execlineptr+0
    sta execlineptr+0
    zif_cs
        inc execlineptr+1
    zendif

    lda #LINE_DATA
    sta execbyteptr
    rts
zendproc

zproc exec_line
    lda #0
    sta bufferpos
    sta bufferend
zendproc
    ; fall through
zproc exec
    ldy execbyteptr
    lda (execlineptr), y
    zif_eq                  ; TOKEN_EOL?
        rts
    zendif
    tax
    
    ; Push return address.

    lda #>(exec-1)
    pha
    lda #<(exec-1)
    pha

    inc execbyteptr
    lda token_exec_hi, x     ; get execution routine
    pha
    lda token_exec_lo, x
    pha
    rts
zendproc

zproc exec_run
    ; TODO: clear variable storage

    ; Start at the beginning.

    lda progbase+0
    sta execlineptr+0
    lda progbase+1
    sta execlineptr+1
    lda #LINE_DATA
    sta execbyteptr

    ; Keep going until the end.

exec_loop:
    lda #RUNFLAG_RUNNING
    sta runflags

    jmp 1f
    zrepeat
        jsr exec_line
        jsr goto_next_line

    1:
        ldy #LINE_SIZE
        lda (execlineptr), y
    zuntil_eq

    lda #0
    sta runflags

    jmp mainloop
zendproc

zproc exec_stop
    lda #<1f
    ldx #>1f
    jsr print_string

    lda #3
    jsr extend_stack

    ldy #0
    lda execlineptr+0
    sta (stackptr), y
    iny
    lda execlineptr+1
    sta (stackptr), y
    iny
    lda execbyteptr
    sta (stackptr), y

    lda #RUNFLAG_RUNNING|RUNFLAG_STOPPED
    sta runflags

    jmp mainloop
1:
    .byte 13, 10
    .ascii "Stopped"
    .byte 13, 10|0x80
zendproc
    
zproc exec_con
    lda runflags
    and #RUNFLAG_STOPPED
    zif_eq
        brk ; TODO: not stopped
    zendif

    ldy #2
    lda (stackptr), y
    sta execbyteptr
    dey
    lda (stackptr), y
    sta execlineptr+1
    dey
    lda (stackptr), y
    sta execlineptr+0

    lda #3
    jsr retract_stack

    jmp exec_loop
zendproc

zproc exec_print
    jsr deref_i0
    jsr buffer_print_i0
    jsr pop_i0
    jmp print_buffer
zendproc

zproc exec_printnl
    jsr buffer_print_nl
    jmp print_buffer
zendproc

zproc exec_varref
    ldx #2
    lda #OTYPE_VAR
    bne push_value_from_bytecode    ; always taken
zendproc

zproc exec_zero
    jsr push_i0

    lda #0
set_4x_constant:
    sta i0+0
    sta i0+1
    sta i0+2
    sta i0+3
    lda #OTYPE_INTEGER
    sta v0
    rts
zendproc

zproc exec_mone
    jsr push_i0

    lda #0xff
    jmp set_4x_constant
zendproc

zproc exec_integer
    ldx #4
    lda #OTYPE_INTEGER
zendproc
    ; falls through

; On entry, X is the number of bytes to copy.
; A is the object type.

zproc push_value_from_bytecode
    pha
    txa
    pha

    jsr push_i0

    pla
    tax
    pla
    sta v0

    clc
    txa
    adc execbyteptr         ; advance execbyteptr
    sta execbyteptr
    tay

    zrepeat
        dey
        lda (execlineptr), y
        sta i0-1, x         ; offset for postdecrement
        dex
    zuntil_eq

    rts
zendproc

zproc exec_assign
    jsr deref_i0            ; value to assign
    jsr pop_i1              ; lvalue (variable reference)

    ; Find the hash node.

    lda i1+0                ; object ID -> p1
    sta p1+0
    lda i1+1
    sta p1+1

    lda #<global_variables
    sta p0+0
    lda #>global_variables
    sta p0+1

    jsr hash_deref          ; return ptr to node in p0

    ; Copy value into node.

    ldy #OBJECT_TYPE
    lda v0
    sta (p0), y
    iny

    ldx #-4 & 0xff
    clc
    zrepeat
        lda i0+4, x
        sta (p0), y
        iny
        inx
    zuntil_eq

    jmp pop_i0
zendproc

zproc exec_add
    jsr deref_i0        ; RHS
    jsr pop_and_deref_i1 ; LHS

    ldx #-4 & 0xff
    clc
    zrepeat
        lda i0+4, x
        adc i1+4, x
        sta i0+4, x
        inx
    zuntil_eq

    rts
zendproc

zproc exec_sub
    jsr deref_i0        ; RHS
    jsr pop_and_deref_i1 ; LHS

    ldx #-4 & 0xff
    sec
    zrepeat
        lda i1+4, x
        sbc i0+4, x
        sta i0+4, x
        inx
    zuntil_eq

    rts
zendproc

zproc exec_neg
    jsr deref_i0
    jsr pop_and_deref_i1 ; LHS

    ldx #-4 & 0xff
    sec
    zrepeat
        lda #0
        sbc i0+4, x
        sta i0+4, x
        inx
    zuntil_eq

    rts
zendproc

zproc exec_mul
    jsr deref_i0        ; RHS
    jsr pop_and_deref_i2 ; LHS

    jmp mul4
zendproc

zproc exec_div
    jsr deref_i0        ; RHS
    jsr i0_to_i2
    jsr pop_and_deref_i0 ; LHS

    jmp divs4
zendproc

zproc exec_mod
    jsr deref_i0        ; RHS
    jsr i0_to_i2
    jsr pop_and_deref_i0 ; LHS

    jsr divs4
    jmp i1_to_i0
zendproc

zproc exec_bad
    brk
zendproc

zproc push_i2
    ldy v2
    ldx #i2
    bne push_ix
zendproc

zproc push_i1
    ldy v1
    ldx #i1
    bne push_ix
zendproc

zproc push_i0
    ldy v0
    ldx #i0
zendproc
    ; fall through
    ; On entry:
    ;   x = address of i register
    ;   y = value byte
zproc push_ix
    lda #STACKVALUE_SIZE
    jsr extend_stack

    tya
    ldy #STACKVALUE_TYPE
    sta (stackptr), y

    zrepeat
        iny
        lda 0, x
        sta (stackptr), y
        inx
        cpy #4
    zuntil_eq
    rts
zendproc

zproc pop_i2
    ldx #i2
    jsr pop_ix
    sta v2
    rts
zendproc

zproc pop_i1
    ldx #i1
    jsr pop_ix
    sta v1
    rts
zendproc

zproc pop_i0
    ldx #i0
    jsr pop_ix
    sta v0
    rts
zendproc

    ; Returns A=object type
zproc pop_ix
    ldy #4
    zrepeat
        lda (stackptr), y
        sta +3, x
        dex
        dey
    zuntil_eq

    lda (stackptr), y       ; type field, at y=0
    pha

    lda #STACKVALUE_SIZE
    jsr retract_stack

    pla
    rts
zendproc

zproc pop_and_deref_i1
    jsr pop_i1
zendproc
    ; falls through
zproc deref_i1
    ldx #i1
    ldy #v1
    jmp deref_ix
zendproc

zproc pop_and_deref_i2
    jsr pop_i2
zendproc
    ; falls through
zproc deref_i2
    ldx #i2
    ldy #v2
    jmp deref_ix
zendproc

zproc pop_and_deref_i0
    jsr pop_i0
zendproc
    ; falls through
zproc deref_i0
    ldx #i0
    ldy #v0
zendproc
    ; falls through

; On entry:
;   X - address of i register
;   Y - address of type byte
zproc deref_ix
    lda 0, y
    cmp #OTYPE_VAR      ; is the object a variable reference?
    zif_eq
        tya
        pha

        lda 0, x            ; object ID -> p1
        sta p1+0
        lda 1, x
        sta p1+1

        txa
        pha

        lda #<global_variables
        sta p0+0
        lda #>global_variables
        sta p0+1

        jsr hash_deref          ; return ptr to node in p0

        pla
        tax

        ; Copy the value to register.

        ldy #OBJECT_DATA
        zrepeat
            lda (p0), y         ; get byte from object
            sta 0, x            ; write to register
            inx
            iny
            cpy #OBJECT_DATA+4
        zuntil_eq

        ; Write the type byte.

        pla
        tax
        lda (p0), y
        sta 0, x
    zendif
    rts
zendproc

zproc extend_stack
    eor #0xff
    sec
    adc stackptr+0
    sta stackptr+0
    zif_cc
        dec stackptr+1
    zendif
    rts
zendproc

zproc retract_stack
    clc
    adc stackptr+0
    sta stackptr+0
    zif_cs
        inc stackptr+1
    zendif
    rts
zendproc

; --- Editor ----------------------------------------------------------------

zproc exec_lineentry
    ; TODO: ensure the stack is empty!

    ; Check line number validity.

    lda i0+2
    ora i0+3
    zif_ne
        brk
    zendif

    jsr find_line               ; sets execlineptr
    zif_eq
        ; The line already exists. Delete it.

        jsr delete_current_line
    zendif

    ; Calculate the size of the new line.

    lda bytecode_buffer+0       ; length of bytecode in buffer
    sec
    sbc execbyteptr             ; position in buffer
    clc
    adc #LINE_DATA              ; fixed line header
    sta p2+0
    
    ; Shuffle everything below this line down by that many bytes.

    ; TODO: check for out of memory!

    lda progbase+0
    sta p0+0
    sec
    sbc p2+0
    sta progbase+0
    sta p1+0

    lda progbase+1
    sta p0+1
    sbc #0
    sta progbase+1
    sta p1+1

    zloop
        lda p0+0
        cmp execlineptr+0
        zif_eq
            lda p0+1
            cmp execlineptr+1
            zbreakif_eq
        zendif

        ldy #0
        lda (p0), y
        sta (p1), y

        inc p0+0
        zif_eq
            inc p0+1
        zendif

        inc p1+0
        zif_eq
            inc p1+1
        zendif
    zendloop
    ; leaves p1 as the address of our new line

    ; Copy the bytecode.

    ldy #LINE_DATA
    ldx execbyteptr
    zrepeat
        lda bytecode_buffer, x
        sta (p1), y
        inx
        iny
        cpy p2+0
    zuntil_eq

    ; Initialise the line header.

    ldy #LINE_SIZE
    lda p2+0
    sta (p1), y         ; line length
    iny
    lda i0+0
    sta (p1), y         ; line number low
    iny
    lda i0+1
    sta (p1), y         ; line number high
    iny
    lda #0
    sta (p1), y         ; indent

    ; Restart the main loop.

    jmp stack_destroyed
zendproc

zproc delete_current_line
    ldy #LINE_SIZE
    lda (execlineptr), y
    sta p2+0

    ; Calculate the new progbase.

    clc
    lda execlineptr+0
    sta p0+0            ; lower copy pointer
    adc p2+0
    sta execlineptr+0
    sta p1+0            ; upper copy pointer
    lda execlineptr+1
    sta p0+1
    adc #0
    sta execlineptr+1
    sta p1+1

    clc
    lda progbase+0
    adc p2+0
    sta progbase+0
    zif_cs
        inc progbase+1
    zendif

    ; Move the bottom half of the program up.

    zloop
        lda p1+0
        cmp progbase+0
        zif_eq
            lda p1+1
            cmp progbase+1
            zbreakif_eq
        zendif

        lda p0+0
        zif_eq
            dec p0+1
        zendif
        dec p0+0

        lda p1+0
        zif_eq
            dec p1+1
        zendif
        dec p1+0

        ldy #0
        lda (p0), y
        sta (p1), y
    zendloop

    rts
zendproc

zproc exec_list
    jsr adjust_line_range
    jsr find_line       ; sets execlineptr
    jmp 1f
    zrepeat
        ; Check terminating line.

        ldy #LINE_NUMBER+1
        lda (execlineptr), y
        cmp i2+1
        zif_eq
            dey
            lda (execlineptr), y
            cmp i2+0
        zendif
        zif_ne
            zbreakif_cs
        zendif
            
        ; Print the line number.

        ldy #LINE_NUMBER+0
        lda (execlineptr), y
        sta i0+0
        iny
        lda (execlineptr), y
        sta i0+1
        
        ; Do the printing.

        lda #0
        sta bufferpos
        sta bufferend

        lda #LINE_DATA
        sta execbyteptr

        lda i2+0
        pha
        lda i2+1
        pha

        jsr buffer_print_i0
        jsr buffer_print_space
        jsr list_line
        jsr print_buffer
        jsr print_nl

        pla
        sta i2+1
        pla
        sta i2+0

        jsr goto_next_line

        ; Check for end of program.

    1:
        ldy #LINE_SIZE
        lda (execlineptr), y
    zuntil_eq

    ; Don't continue execution.

    pla
    pla
    rts
zendproc

zproc exec_del
    jsr adjust_line_range
    jsr find_line       ; sets execlineptr

    jmp 1f
    zrepeat
        ; Is the current line greater than the end of the range?

        ldy #LINE_NUMBER+1
        lda i2+1
        cmp (execlineptr), y
        zif_eq
            dey
            lda i2+0
            cmp (execlineptr), y
        zendif
        zbreakif_cc

        jsr delete_current_line

    1:
        ldy #LINE_SIZE
        lda (execlineptr), y
    zuntil_eq

    jmp stack_destroyed
zendproc

zproc adjust_line_range
    ; end line in i0
    jsr i0_to_i2        ; end line in i2
    jsr pop_i0          ; start line in i0

    ; Turn list 0, 0 to list 0, 0xffff

    lda i0+0
    ora i0+1
    ora i2+0
    ora i2+1
    zif_eq
        dec i2+0
        dec i2+1
    zendif

    ; Turn list x, 0 to list x, x

    lda i2+0
    ora i2+1
    zif_eq
        lda i0+0
        sta i2+0
        lda i0+1
        sta i2+1
    zendif

    rts
zendproc

zproc exec_renum
    ; end line in i0
    jsr pop_i2          ; start line in i0

    ; Validate.

    lda i2+3
    ora i0+3
    zif_mi
        brk ; TODO: silly
    zendif

    ; Turn renum 0,x to renum 10,x

    lda i2+0
    ora i2+1
    zif_eq
        lda #10
        sta i2+0
    zendif

    ; Turn renum x,0 to renum x,10

    lda i0+0
    ora i0+1
    zif_eq
        lda #10
        sta i0+0
    zendif

    ; Iterate through each line.

    lda progbase+0
    sta execlineptr+0
    lda progbase+1
    sta execlineptr+1
    jmp 1f
    zrepeat
        ldy #LINE_NUMBER
        lda i2+0
        sta (execlineptr), y
        iny
        lda i2+1
        sta (execlineptr), y

        clc
        lda i0+0
        adc i2+0
        sta i2+0
        lda i0+1
        adc i2+1
        sta i2+1

        jsr goto_next_line

    1:
        ldy #LINE_SIZE
        lda (execlineptr), y
    zuntil_eq

    jmp stack_destroyed
zendproc

; --- Buffer output ---------------------------------------------------------

; Prints the decimal number in i0.

zproc buffer_print_i0
    lda #10
    sta i2+0
    lda #0
    sta i2+1
    sta i2+2
    sta i2+3
    sta p0+0

    ; Is this a negative number?

    lda i0+3
    zif_mi
        lda #'-'
        jsr buffer_print_char

        jsr negi0
    zendif

    zrepeat
        jsr divu4
        lda i1+0
        pha
        inc p0+0

        lda i0+0
        ora i0+1
        ora i0+2
        ora i0+3
    zuntil_eq

    zrepeat
        pla
        clc
        adc #'0'
        jsr buffer_print_char

        dec p0+0
    zuntil_eq
    rts
zendproc

; Outputs the high-bit-terminated string in AX.

zproc buffer_print_string
    sta p0+0
    stx p0+1

    ldy #0xff
    sty p1+0

    ldx bufferend
    zrepeat
        inc p1+0
        ldy p1+0
        lda (p0), y
        and #0x7f
        sta text_buffer, x
        inx

        ldy p1+0
        lda (p0), y
    zuntil_mi
    stx bufferend

    rts
zendproc

zproc buffer_print_separated_string
    jsr buffer_print_string
zendproc
    ; fall through
zproc buffer_print_space
    lda #' '
zendproc
    ; fall through
zproc buffer_print_char
    ldx bufferend
    sta text_buffer, x
    inc bufferend
    rts
zendproc

zproc buffer_print_nl
    lda #0x0d
    jsr buffer_print_char
    lda #0x0a
    bne buffer_print_char       ; always taken
zendproc

; --- Maths -----------------------------------------------------------------

zproc i0_to_i2
    lda v0
    sta v2

    ldx #i0
    ldy #i2
    bne i_to_i      ; always taken
zendproc

zproc i1_to_i0
    lda v1
    sta v0

    ldx #i1
    ldy #i0
    bne i_to_i      ; always taken
zendproc

; Copies four bytes from x to y.

zproc i_to_i
    lda 0, x
    sta 0, y
    lda 1, x
    sta 1, y
    lda 2, x
    sta 2, y
    lda 3, x
    sta 3, y
    rts
zendproc

; Computes i1i0 := i0 * i2.

zproc mul4
    lda #0              ; clear high part of result
    sta i1+0
    sta i1+1
    sta i1+2
    sta i1+3

    clc
    ldy #$21            ; bit counter

    zrepeat
        ldx #8              ; shift right result and lhs
        zrepeat
            ror i0-1, x
            dex
        zuntil_eq
        zif_cs
            ldx #-4 & 0xff      ; add rhs to low half of result
            clc
            zrepeat
                lda i1+4, x
                adc i2+4, x
                sta i1+4, x
                inx
            zuntil_eq
        zendif

        dey
    zuntil_eq
    rts
zendproc

; Computes i0 rem i1 := i0 / i2, unsigned.

zproc divu4
    lda #0              ; clear remainder
    ldx #3
    zrepeat
        sta i1, x
        dex
    zuntil_mi

    ldy #32             ; bit counter
    zrepeat
        ldx #-8 & 0xff      ; left shift result and remainder
        clc
        zrepeat
            rol i0+8, x
            inx
        zuntil_eq

        sec                 ; if remainder < rhs
        ldx #-4 & 0xff
        zrepeat
            lda i1+4, x
            sbc i2+4, x
            inx
        zuntil_eq
        zif_cs
            ldx #-4 & 0xff      ; remainder := remainder - rhs
            zrepeat
                lda i1+4, x
                sbc i2+4, x
                sta i1+4, x
                inx
            zuntil_eq
            inc i0
        zendif

        dey
    zuntil_eq
    rts
zendproc

; Computes i0 rem i1 := i0 / i2, signed.

zproc divs4
    lda i0+3            ; high byte of LHS
    eor i2+3            ; high byte of RHS
    php                 ; save sign of result for later
    lda i0+3            ; high byte of LHS
    php                 ; save sign of remainder for later
    zif_mi              ; negate LHS if negative
        jsr negi0
    zendif

    lda i2+3            ; get sign of RHS
    zif_mi
        jsr negi2       ; negate RHS if negative
    zendif

    jsr divu4           ; actually do the division

    plp                 ; get sign of remainder
    zif_mi
        jsr negi1       ; negate remainder if required
    zendif

    plp                 ; get sign of result
    zif_mi
        jsr negi0       ; invert result if required
    zendif
    rts
zendproc

; Negates i0/i1/i2.

zproc negi0
    ldx #i0
    bne negi            ; always taken
zendproc

zproc negi1
    ldx #i1
    bne negi            ; always taken
zendproc

zproc negi2
    ldx #i2
zendproc
    ; falls through
zproc negi
    ldy #(-4) & 0xff
    sec
    zrepeat
        lda #0
        sbc 0, x
        sta 0, x
        inx
        iny
    zuntil_eq
    rts
zendproc

; --- Hashing stuff ---------------------------------------------------------

; Returns a (possibly new) value node for a given ID.
; On entry:
;   p0 - pointer to hash table
;   p1 - ID
; On exit:
;   p0 - pointer to value node

zproc hash_deref
    ; Hash the ID.

    lda p1+0
    eor p1+1
    and #HASH_SLOTS-1
    
    ; Get the address of the hash slot.

    asl a
    adc p0+0            ; we know C is clear
    sta p0+0
    zif_cs
        inc p0+1
    zendif

    ; Walk the list.

    zloop
        ; Here, p0 is the _address_ of the object ID of the first node.

        ldy #0
        lda (p0), y
        sta p2+0
        iny
        lda (p0), y
        sta p2+1        ; get the object ID
        ora p2+0        ; test if null
        zbreakif_eq

        ; Get the pointer to the node from the ID.

        lda p2+0
        sta p0+0
        lda p2+1
        sta p0+1
        jsr deref_object
        
        ; Is this the node we're looking for?

        ldy #HASHNODE_KEY
        lda (p0), y
        cmp p1+0
        zif_eq
            iny
            lda (p0), y
            cmp p1+1
            zif_eq
                ; Yes. We've found a matching node. Just return it.

                rts
            zendif
        zendif

        ; Didn't match. Go on to the next item in the chain.

        clc
        lda p0+0
        adc #HASHNODE_NEXT
        sta p0+0
        zif_eq
            inc p0+1
        zendif
    zendloop

    ; Reached the end of the chain --- allocate a new node.
    
    lda p0+0
    pha
    lda p0+1
    pha
    lda p1+0
    pha
    lda p1+1
    pha

    lda #HASHNODE_SIZE
    sta p1+0
    lda #0
    sta p1+1
    jsr heap_alloc          ; returns pointer in p0, id in p1

    ; Zero the node.

    ldy #HASHNODE_SIZE-1
    lda #0
    zrepeat
        sta (p0), y
        dey
        cpy #OBJECT_DATA
    zuntil_mi

    ; Set the node's key.

    ldy #HASHNODE_KEY+1
    pla
    sta (p0), y
    dey
    pla
    sta (p0), y

    ; Add this new node to the chain.

    pla
    sta p2+1
    pla
    sta p2+0                ; recover address of object ID

    ldy #0
    lda p1+0
    sta (p2), y
    iny
    lda p1+1
    sta (p2), y

    ; Return the new node.

    rts
zendproc

; --- Objects and atoms -----------------------------------------------------

; Given an object ID in p0, returns in p0 the address in the object table of
; the slot.

zproc find_object_slot
    ; p0 = object_table + (p0-1)*2

    lda p0+0
    zif_eq
        dec p0+1
    zendif
    dec p0+0

    asl p0+0
    rol p0+1

    lda #<object_table
    adc p0+0
    sta p0+0
    lda #>object_table
    adc p0+1
    sta p0+1
    rts
zendproc

; Given an object ID in p0, dereferences it (or produces an error). Returns the
; pointer to the data in p0.

zproc deref_object
    jsr find_object_slot

    ldy #0
    lda (p0), y
    tax
    iny
    lda (p0), y
    sta p0+1
    stx p0+0
    rts
zendproc

; Start iterating through the object table. Chains on to find_next_object.

zproc find_first_object
    lda #0
    sta p1+0
    sta p1+1
zendproc
    ; fall through
    ; Returns the next object id in p1, and the pointer to the slot in p0.
    ; Returns C if there are no more objects.
    ; Returns Z if the current slot is empty.
zproc find_next_object
    inc p1+0        ; increment counter
    zif_eq
        inc p1+1
    zendif

    lda p1+0
    cmp #<OBJECT_TABLE_SIZE
    bne not_eof
    lda p1+1
    cmp #>OBJECT_TABLE_SIZE
    bne not_eof
    sec             ; no more objects
    rts

not_eof:
    lda p1+0
    sta p0+0
    lda p1+1
    sta p0+1
    jsr find_object_slot

    ldy #0          ; check if value in slot is 0x0000
    lda (p0), y
    iny
    ora (p0), y
    rts
zendproc

; Allocates a block of size p1 on the heap. The object ID is returned in p1 and
; a pointer to the new object in p0. The first byte of the block must be set
; to a valid object type.
;
; On entry, A is the new objec type.

zproc heap_alloc
    ; Initialise the object header.

    ldy #OBJECT_TYPE
    sta (heapptr), y
    dey
    lda p1+1
    sta (heapptr), y
    dey
    lda p1+0
    sta (heapptr), y

    ; Allocate the object itself.

    clc
    lda heapptr+0
    sta p2+0            ; put the object pointer into p2
    adc p1+0
    sta heapptr+0
    lda heapptr+1
    sta p2+1
    adc p1+1
    sta heapptr+1

    ; TODO: check for running out of memory here.

    ; Find a free slot in the object table.

    jsr find_first_object
    zrepeat
        zif_eq
            ; Found a free slot (and copy the pointer into XA).

            lda p2+1
            sta (p0), y
            tax
            dey
            lda p2+0
            sta (p0), y

            ; Return the object pointer in p0.

            sta p0+0
            stx p0+1

            ; ID is returned in p1.

            rts
        zendif

        jsr find_next_object
    zuntil_cs
        
    ; TODO: object table is full, error out
    rts
zendproc

; Returns the object ID in p1 of the atom in the input buffer starting at
; bufferpos and ending at the character just before bufferend.

zproc get_atom
    ; Search the object table for atoms.

    jsr find_first_object
    zrepeat
        zif_ne
            ; Dereference it.

            lda (p0), y
            tax
            dey
            lda (p0), y
            sta p0+0
            stx p0+1

            ; Is this an atom?

            ldy #OBJECT_TYPE
            lda (p0), y
            cmp #OTYPE_ATOM
            zif_eq
                ; Compare the text.

                ldy #OBJECT_DATA
                ldx bufferpos
                zloop
                    lda (p0), y
                    and #0x7f
                    cmp text_buffer, x
                    zbreakif_ne

                    inx

                    lda (p0), y
                    zif_mi
                        cpx bufferend
                        zbreakif_ne

                        ; Found the right atom!

                        rts
                    zendif

                    iny
                zendloop
            zendif
        zendif

        jsr find_next_object
    zuntil_cs

    ; Atom not found, so allocate a new one.

    sec
    lda bufferend
    sbc bufferpos           ; get length of atom
    clc
    adc #OBJECT_DATA        ; add on the header

    sta p1+0
    lda #0
    sta p1+1
    lda #OTYPE_ATOM         ; object type
    jsr heap_alloc          ; allocate space for the atom
    ; id is in p1, pointer in p0

    ; Copy the word into the heap object.

    ldy #OBJECT_DATA-1      ; -1 to compensate for predecrement later
    ldx bufferpos
    zrepeat
        iny
        lda text_buffer, x ; get char from buffer
        sta (p0), y         ; store into object
        inx
        cpx bufferend
    zuntil_eq

    ; Mark the last byte of the heap object as the terminator.

    lda #0x80
    ora (p0), y
    sta (p0), y

    ; Return the ID in p1.

    rts
zendproc

; --- Lister ----------------------------------------------------------------

; Renders the line pointed to by execlineptr+execbyteptr.

; operator_stack contains the tree.
; <bytecode address> {<child tree nodes>}*

zproc list_line
    ldx execbyteptr
    stx bytecodeptr
    ldx #0
    stx opstackptr
    stx listerflags
    tsx
    stx listersp

    zloop
        ; Create the first byte of the tree node.

        ldy bytecodeptr
        lda (execlineptr), y            ; read opcode
        zbreakif_eq
        ldy opstackptr
        sty listerroot
        lda bytecodeptr
        sta operator_stack, y
        inc opstackptr

        ; Pop consumed stack items.

        ldy bytecodeptr
        lda (execlineptr), y            ; read opcode
        tax
        lda token_size_table, x
        and #0b01110000
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        jmp 1f
        zrepeat
            pla
            ldy opstackptr
            sta operator_stack, y
            inc opstackptr

        1:
            dex
        zuntil_mi
        
        ; Push produced stack items.

        ldy bytecodeptr
        lda (execlineptr), y            ; read opcode
        tay
        lda token_size_table, y
        zif_mi
            lda listerroot
            pha
        zendif

        ; Is the stack empty? If so, flush out the current tree.

        tsx
        cpx listersp
        zif_eq
            ldx listerroot
            jsr list_clause

            lda #0
            sta opstackptr
            lda listerflags
            ora #LISTERFLAG_NOTSTART
            sta listerflags
        zendif

        ; Move to next bytecode.

        ldy bytecodeptr
        lda (execlineptr), y            ; read opcode
        tay
        lda token_size_table, y
        and #0b00001111
        clc
        adc bytecodeptr
        sta bytecodeptr
    zendloop
    
    ; Assert that the stack is empty.

    tsx
    cpx listersp
    zif_ne
        brk
    zendif

    bit listerflags
    zif_vs
        lda #','
        jsr buffer_print_char
    zendif
    rts
zendproc

; Takes the tree node address in X.
zproc list_clause
    lda operator_stack, x       ; get bytecode address
    tay
    lda (execlineptr), y        ; get bytecode
    tay
    lda token_listers_hi, y     ; get lister routine
    pha
    lda token_listers_lo, y
    pha
lister_nop:
    rts
zendproc

zproc lister_bad
    brk
zendproc

zproc lister_simple
    lda operator_stack, x       ; get bytecode address
    tay
    lda (execlineptr), y      ; get bytecode
    tay
    ldx token_aux_hi, y
    lda token_aux_lo, y
    jmp buffer_print_string
zendproc

zproc lister_print
    lda #<keyword_print
    ldx #>keyword_print
    bit listerflags
    zif_mi                      ; if LISTERFLAG_NOTSTART
        lda #<keyword_comma
        ldx #>keyword_comma
    zendif
    jsr buffer_print_separated_string

    lda listerflags
    ora #LISTERFLAG_COMMA
    sta listerflags

    ldy listerroot
    ldx operator_stack+1, y
    jmp list_clause
zendproc

zproc lister_printnl
    bit listerflags
    zif_pl                      ; if !LISTERFLAG_NOTSTART
        lda #<keyword_print
        ldx #>keyword_print
        jmp buffer_print_string
    zendif

    lda listerflags
    and #(~LISTERFLAG_COMMA) & 0xff
    sta listerflags
    rts
zendproc
    
zproc lister_varref
    lda operator_stack, x       ; get bytecode address
    tay
    iny
    lda (execlineptr), y
    sta p0+0
    iny
    lda (execlineptr), y
    sta p0+1
    jsr deref_object

    ldx p0+1
    inc p0+0
    zif_eq
        inx
    zendif
    lda p0+0
    jmp buffer_print_string
zendproc

zproc lister_integer
    lda operator_stack, x       ; get bytecode address
    tay
    iny

    ldx #0
    zrepeat
        lda (execlineptr), y
        sta i0, x
        iny
        inx
        cpx #4
    zuntil_eq

    jmp buffer_print_i0
zendproc

zproc lister_assign
    bit listerflags
    zif_mi
        txa
        pha

        lda #<keyword_semicolon
        ldx #>keyword_semicolon
        jsr buffer_print_separated_string

        pla
        tax
    zendif
zendproc
    ; fall through
zproc lister_infix
    txa
    pha

    ldy operator_stack+2, x     ; get first parameter tree address
    jsr list_parenthesised_clause
    jsr buffer_print_space

    pla
    pha
    tax
    lda operator_stack, x       ; get bytecode address
    tay
    lda (execlineptr), y        ; get bytecode
    tay
    ldx token_aux_hi, y
    lda token_aux_lo, y
    jsr buffer_print_separated_string

    pla
    tax                         ; recover current node tree address
    ldy operator_stack+1, x     ; get second parameter tree address
zendproc
    ; falls through
   
; On entry,
; X = tree address of current node
; Y = tree address of node to print
; Corrupts everything!

zproc list_parenthesised_clause
    sty p0+0

    ldy operator_stack+0, x     ; get current bytecode address
    lda (execlineptr), y        ; get current bytecode
    tax
    lda token_precedence_table, x ; get current bytecode precedence
    sta p0+1

    ldx p0+0
    ldy operator_stack+0, x     ; get parameter bytecode address
    lda (execlineptr), y        ; get parameter bytecode
    tay
    lda token_precedence_table, y ; get parameter precedence
    cmp p0+1
    zif_cc                      ; parameter is lower precedence
        lda #'('
        jsr buffer_print_char

        ldx p0+0                ; tree address of parameter to print
        jsr list_clause

        lda #')'
        jmp buffer_print_char
    zendif

    ldx p0+0                ; tree address of parameter to print
    jmp list_clause
zendproc

zproc lister_prefix
    txa
    pha

    lda operator_stack, x       ; get bytecode address
    tay
    lda (execlineptr), y        ; get bytecode
    tay
    ldx token_aux_hi, y
    lda token_aux_lo, y
    jsr buffer_print_string

    pla
    tax                         ; recover current node tree address
    ldy operator_stack+1, x     ; get second parameter tree address
    jmp list_parenthesised_clause
zendproc

; --- Parser ----------------------------------------------------------------

zproc parse_line
    ldx #1
    stx bytecodeptr
    dex
    stx opstackptr
    tsx
    stx parsestartstackptr

    lda #<immediate_statement_rule
    sta parsecmd+0
    lda #>immediate_statement_rule
    sta parsecmd+1

    lda #<pop_succeed_ptr
    pha
    lda #>pop_succeed_ptr
    pha
zendproc
    ; fall through
zproc parse_state_machine
    ldy #0
    lda (parsecmd), y
    sta p0+0
    iny
    lda (parsecmd), y
    sta p0+1

#if 0
    tsx
    txa
    jsr print_hex8_number
    jsr print_space
    lda parsecmd+0
    ldx parsecmd+1
    jsr print_hex16_number
    jsr print_nl
#endif

    jmp (p0)
zendproc

; Adds A to parsecmd.
zproc parse_advance
    clc
    adc parsecmd+0
    sta parsecmd+0
    zif_cs
        inc parsecmd+1
    zendif
    rts
zendproc

; Pushes A onto the bytecode queue.
; Preserves Y.
zproc queue_bytecode
    ldx bytecodeptr
    sta bytecode_buffer, x
    inx
    stx bytecodeptr
    rts
zendproc

; Shunts the operator A through the shunting yard algorithm.
zproc shunt_operator
    tay             ; Y contains operator throughout

    jmp 1f
    zrepeat
        ldx opstackptr
        lda operator_stack, x
        zbreakif_eq ; if TOS is 0, it's a parenthesis
        tax
        lda token_precedence_table, x ; priority of operator
        cmp token_precedence_table, y ; priority of TOS
        zbreakif_cc ; stack if TOS < operator

        dec opstackptr
        txa
        jsr queue_bytecode

    1:
        ldx opstackptr
    zuntil_eq

    ; Stack the operator onto the operator stack.

stack_operator:
    ldx opstackptr
    inx
    tya
    sta operator_stack, x
    stx opstackptr
    rts
zendproc

; Unstacks operators down to and including a parenthesis marker (or the stack
; is empty).

zproc unstack_operators
    zloop
        ldx opstackptr
        zif_eq
            rts
        zendif

        lda operator_stack, x
        zif_eq
            dec opstackptr
            rts
        zendif

        dec opstackptr
        jsr queue_bytecode
    zendloop
zendproc
    
pop_succeed_ptr:
    .word pop_succeed

zproc pop_succeed
    jsr unstack_operators

    lda #TOKEN_EOL
    ldx bytecodeptr
    sta bytecode_buffer, x
    inx
    stx bytecode_buffer+0

    ldx parsestartstackptr
    txs
    rts
zendproc

zproc pop_panic
    ldx parsestartstackptr
    txs

    lda #<1f
    ldx #>1f
    jsr print_string

    lda #0
    sta p0+0
    zrepeat
        ldx p0+0
        lda text_buffer+2, x
        jsr bdos_CONOUT

        inc p0+0
        ldx p0+0
        cpx text_buffer+1
    zuntil_eq
    jsr print_nl

    lda #2
    sta p0+0
    zloop
        ldx p0+0
        cpx bufferpos
        zbreakif_eq

        jsr print_space
        inc p0+0
    zendloop
    lda #'^'
    jsr bdos_CONOUT
    jsr print_nl

    jmp mainloop
1:
    .ascii "\r\nSyntax error\r"
    .byte '\n'|0x80

zendproc

zproc pop_try
    ; Read parameter into p0.

    ldy #2
    lda (parsecmd), y
    sta p0+0
    iny
    lda (parsecmd), y
    sta p0+1

    ; Advance.

    lda #4
    jsr parse_advance

#if 0
    lda #'>'
    jsr bdos_CONOUT
    lda parsecmd+0
    ldx parsecmd+1
    jsr print_hex16_number
    jsr print_nl
#endif

    ; Push backtracking state.

    lda parsefailstackptr
    pha

    lda parsecmd+0
    pha
    lda parsecmd+1
    pha
    lda bufferpos
    pha
    lda bytecodeptr
    pha
    lda opstackptr
    pha

    tsx
    stx parsefailstackptr

    ; Push the marker indicating that this is a backtracking state.

    lda #0
    pha
    pha

    ; Switch to rule being tried.

    lda p0+0
    sta parsecmd+0
    lda p0+1
    sta parsecmd+1

    jmp parse_state_machine
zendproc

; We can't backtrack any more --- if we get a parse failure, panic.

zproc pop_commit
    lda parsefailstackptr
    pha

    lda #<pop_panic_ptr
    pha
    lda #>pop_panic_ptr
    pha
    lda bufferpos
    pha
    lda bytecodeptr
    pha
    lda opstackptr
    pha

    tsx
    stx parsefailstackptr

    ; Push the marker indicating that this is a backtracking state.

    lda #0
    pha
    pha

    lda #2
    jsr parse_advance
    jmp parse_state_machine
zendproc

pop_panic_ptr:
    .word pop_panic

; Revert to a backtracking state.

zproc pop_fail
    ; Revert the state.

#if 0
    lda #'<'
    jsr bdos_CONOUT
    jsr print_nl
#endif

    ldx parsefailstackptr
    txs

    pla
    sta opstackptr
    pla
    sta bytecodeptr
    pla
    sta bufferpos
    pla
    sta parsecmd+1
    pla
    sta parsecmd+0
    pla
    sta parsefailstackptr

    jmp parse_state_machine
zendproc

zproc pop_jsr
    ; Read parameter into p0.

    ldy #2
    lda (parsecmd), y
    sta p0+0
    iny
    lda (parsecmd), y
    sta p0+1

    ; Advance.

    lda #4
    jsr parse_advance

    ; Push return point.

    lda parsecmd+0
    pha
    lda parsecmd+1
    pha

    ; Jump to the new rule.

    lda p0+0
    sta parsecmd+0
    lda p0+1
    sta parsecmd+1

    jmp parse_state_machine
zendproc

zproc pop_jmp
    ; Read parameter into parsecmd.

    ldy #2
    lda (parsecmd), y
    tax
    iny
    lda (parsecmd), y
    stx parsecmd+0
    sta parsecmd+1

    jmp parse_state_machine
zendproc
    
zproc pop_return
    ; Pop the return point.

    pla
    sta parsecmd+1
    pla
    sta parsecmd+0

    ; Was this a backtracking marker?

    lda parsecmd+0
    ora parsecmd+1
    zif_eq
        ; It was. Discard the backtracking state and return again.

        pla
        pla
        pla
        pla
        pla
        pla
        sta parsefailstackptr

        jmp pop_return
    zendif

    jmp parse_state_machine
zendproc

zproc pop_shunt
    ldy #2
    lda (parsecmd), y

    jsr shunt_operator

    lda #3
    jsr parse_advance
    jmp parse_state_machine
zendproc

zproc pop_paren
    ldy #0
    jsr stack_operator

    lda #2
    jsr parse_advance
    jmp parse_state_machine
zendproc

zproc pop_endparen
zendproc

zproc pop_flush
    jsr unstack_operators

    lda #2
    jsr parse_advance
    jmp parse_state_machine
zendproc

zproc parser_skip_whitespace
    zloop
        ldx bufferpos
        lda text_buffer, x
        cmp #' '
        zbreakif_ne

        inc bufferpos
    zendloop
    rts
zendproc

; Fetch an identifier and set p0/p1 to the atom pointer and ID.
zproc parser_fetch_word
    jsr parser_skip_whitespace

    lda bufferpos
    sta bufferend
    zloop
        ldx bufferend
        lda text_buffer, x
        jsr isletter
        zbreakif_cc

        inc bufferend
    zendloop

    lda bufferpos
    cmp bufferend
    beq 1f

    jsr get_atom

    lda bufferend
    sta bufferpos
    rts
1:
    jmp pop_fail
zendproc

; Used by pop*token. Leaves the buffer position in X.

zproc skip_token
    jsr parser_skip_whitespace

    ldx bufferpos
    dex
    ldy #1 ; 2 - 1
    zrepeat
        inx
        iny

        lda text_buffer, x
        jsr toupper
        eor (parsecmd), y
        and #0x7f
        zif_ne
            jmp pop_fail
        zendif

        lda (parsecmd), y
    zuntil_mi

    inx
    stx bufferpos
    rts
zendproc

zproc pop_token
    jsr skip_token

    ; Check that this is the end of a word.

    lda text_buffer, x
    jsr isletter
    zif_cs
        jmp pop_fail
    zendif

1:
    iny
    tya
    jsr parse_advance

    jmp parse_state_machine
zendproc

zproc pop_eager_token
    jsr skip_token
    jmp 1b
zendproc

zproc pop_emit
    ldy #2
    lda (parsecmd), y
    jsr queue_bytecode

    lda #3
    jsr parse_advance
    jmp parse_state_machine
zendproc

zproc pop_word
    jsr parser_fetch_word

    lda #TOKEN_VARREF
    jsr queue_bytecode
    sta bytecode_buffer, x
    lda p1+0
    jsr queue_bytecode
    lda p1+1
    jsr queue_bytecode

    lda #2
    jsr parse_advance

    jmp parse_state_machine
zendproc

zproc pop_eol
    jsr parser_skip_whitespace

    ldx bufferpos
    lda text_buffer, x
    zif_ne
        jmp pop_fail
    zendif

    lda #2
    jsr parse_advance
    jmp parse_state_machine
zendproc

zproc pop_number
    jsr parser_skip_whitespace

    ; Clear i2 and i0.

    ldx #3
    lda #0
    zrepeat
        sta i2, x
        sta i0, x
        dex
    zuntil_mi

    ; Set i2 to 10 for the multiplication.

    lda #10
    sta i2+0

    lda bufferpos
    sta bufferend

    ; Is the number negative?

    ldx bufferend
    lda text_buffer, x
    cmp #'-'
    php                 ; save comparison result for later
    zif_eq
        inc bufferpos
        inc bufferend
    zendif

    zloop
        ldx bufferend
        lda text_buffer, x
        cmp #'0'
        zbreakif_cc
        cmp #'9'+1
        zbreakif_cs

        pha
        jsr mul4
        pla

        sec
        sbc #'0'
        clc
        adc i0+0
        sta i0+0
        zif_cs
            inc i0+1
            zif_eq
                inc i0+2
                zif_eq
                    inc i0+3
                zendif
            zendif
        zendif

        inc bufferend
    zendloop

    lda bufferpos
    cmp bufferend
    beq 1f

    plp                 ; is the number negative?
    zif_eq
        jsr negi0
    zendif

    lda i0+0
    ora i0+1
    ora i0+2
    ora i0+3
    zif_eq              ; is the number zero?
        lda #TOKEN_ZERO
    zelse
        lda i0+0
        and i0+1
        and i0+2
        and i0+3
        cmp #0xff
        zif_eq          ; is the number minus one?
            lda #TOKEN_MONE
        zelse
            lda #TOKEN_INTEGER
            jsr queue_bytecode
            lda i0+0
            jsr queue_bytecode
            lda i0+1
            jsr queue_bytecode
            lda i0+2
            jsr queue_bytecode
            lda i0+3
        zendif
    zendif
    jsr queue_bytecode

    lda bufferend
    sta bufferpos

    lda #2
    jsr parse_advance
    jmp parse_state_machine
1:
    jmp pop_fail
zendproc

.macro P_TRY rule
    .word pop_try
    .word \rule
.endm

.macro P_JSR rule
    .word pop_jsr
    .word \rule
.endm

.macro P_JMP rule
    .word pop_jmp
    .word \rule
.endm

.macro P_FAIL
    .word pop_fail
.endm

.macro P_PANIC
    .word pop_panic
.endm

.macro P_RETURN
    .word pop_return
.endm

.macro P_COMMIT
    .word pop_commit
.endm

.macro P_TOKEN bytes:vararg
    .word pop_token
    .byte \bytes
.endm

.macro P_EAGER_TOKEN bytes:vararg
    .word pop_eager_token
    .byte \bytes
.endm

.macro P_EMIT token
    .word pop_emit
    .byte \token
.endm

.macro P_SHUNT token
    .word pop_shunt
    .byte \token
.endm

.macro P_FLUSH
    .word pop_flush
.endm

.macro P_WORD
    .word pop_word
.endm

.macro P_NUMBER
    .word pop_number
.endm

.macro P_EOL
    .word pop_eol
.endm

.macro P_PAREN
    .word pop_paren
.endm

immediate_statement_rule:
    P_TRY lineentry_rule
    P_TRY list_rule
    P_TRY del_rule
    P_TRY renum_rule
    P_TRY run_rule
    P_TRY con_rule
statement_rule:
    P_TRY print_rule
    P_TRY assignment_rule
    P_TRY stop_rule
;    P_TRY for_rule
;    P_TRY if_rule
;    P_TRY proc_rule
    P_PANIC

lineentry_rule:
    P_NUMBER
    P_COMMIT
    P_EMIT TOKEN_LINEENTRY
    P_JMP statement_rule

list_rule:
    P_TOKEN 'L', 'I', 'S', 'T'|0x80
    P_COMMIT
    P_TRY empty_list_rule
    P_JSR line_range_rule
    P_EMIT TOKEN_LIST
    P_EOL
    P_RETURN

empty_list_rule:
    P_EOL
    P_EMIT TOKEN_ZERO
    P_EMIT TOKEN_ZERO
    P_EMIT TOKEN_LIST
    P_RETURN

del_rule:
    P_TOKEN 'D', 'E', 'L'|0x80
    P_COMMIT
    P_JSR line_range_rule
    P_EMIT TOKEN_DEL
    P_EOL
    P_RETURN

renum_rule:
    P_TOKEN 'R', 'E', 'N', 'U', 'M'|0x80
    P_COMMIT
    P_JSR first_optional_number_or_zero_rule
    P_JSR second_optional_number_or_zero_rule
    P_EOL
    P_EMIT TOKEN_RENUM
    P_RETURN

second_optional_number_or_zero_rule:
    P_TRY comma_then_number_rule
    P_EMIT TOKEN_ZERO
    P_RETURN

first_optional_number_or_zero_rule:
    P_TRY number_rule
    P_EMIT TOKEN_ZERO
    P_RETURN

comma_then_number_rule:
    P_EAGER_TOKEN ','|0x80
number_rule:
    P_NUMBER
    P_RETURN

line_range_rule:
    P_TRY open_left_line_range_rule
    P_TRY single_line_range_rule
    P_NUMBER
    P_EAGER_TOKEN '-'|0x80
    P_TRY eol_line_range_rule
    P_NUMBER
    P_RETURN

single_line_range_rule:
    P_NUMBER
    P_EMIT TOKEN_ZERO
    P_EOL
    P_RETURN

open_left_line_range_rule:
    P_EAGER_TOKEN '-'|0x80
    P_EMIT TOKEN_ZERO
    P_NUMBER
    P_RETURN

eol_line_range_rule:
    P_EOL
    P_EMIT TOKEN_MONE
    P_RETURN

run_rule:
    P_TOKEN 'R', 'U', 'N'|0x80
    P_EMIT TOKEN_RUN
    P_RETURN

stop_rule:
keyword_stop = . + 2
    P_TOKEN 'S', 'T', 'O', 'P'|0x80
    P_EMIT TOKEN_STOP
    P_RETURN

con_rule:
    P_TOKEN 'C', 'O', 'N'|0x80
    P_EMIT TOKEN_CON
    P_RETURN

assignment_rule:
    P_JSR lvalue_rule
    P_EAGER_TOKEN '='|0x80
    P_SHUNT TOKEN_ASSIGN
    P_COMMIT
    P_JSR expr_rule
    P_TRY eol_rule
    P_FLUSH
    P_EAGER_TOKEN ';'|0x80
    P_JMP assignment_rule

assignment_operator_rule:
    P_TRY equals_rule
keyword_assign = . + 2
    P_EAGER_TOKEN ':', '='|0x80
    P_RETURN

equals_rule:
    P_EAGER_TOKEN '='|0x80
    P_RETURN

eol_rule:
    P_EOL
    P_RETURN

print_rule:
keyword_print = . + 2
    P_TOKEN 'P', 'R', 'I', 'N', 'T'|0x80
    P_COMMIT
    P_TRY print_no_terminator_rule
    P_SHUNT TOKEN_PRINT
    P_JSR expr_rule
print_expr_list_rule:
    P_TRY print_no_terminator_rule
    P_TRY print_terminator_rule
    P_JSR print_separator_rule
    P_COMMIT
    P_SHUNT TOKEN_PRINT
    P_JSR expr_rule
    P_JMP print_expr_list_rule

print_terminator_rule:
    P_JSR print_separator_rule
    P_EOL
    P_RETURN

comma_rule:
keyword_comma = . + 2
    P_EAGER_TOKEN ','|0x80
    P_RETURN

print_separator_rule:
    P_TRY comma_rule
semicolon_rule:
keyword_semicolon = . + 2
    P_EAGER_TOKEN ';'|0x80
    P_RETURN

print_no_terminator_rule:
    P_EOL
    P_SHUNT TOKEN_PRINTNL
    P_RETURN

lvalue_rule:
    P_WORD
    P_RETURN

optional_expr_rule:
    P_TRY expr_rule
    P_RETURN

compulsory_expr_rule:
    P_TRY expr_rule
    P_PANIC

expr_rule:
    P_JSR leaf_rule
    P_COMMIT
    P_TRY addition_rule
    P_TRY subtraction_rule
    P_TRY multiplication_rule
    P_TRY division_rule
    P_TRY modulus_rule
    P_RETURN

addition_rule:
keyword_add = . + 2
    P_EAGER_TOKEN '+'|0x80
    P_SHUNT TOKEN_ADD
    P_JMP compulsory_expr_rule

subtraction_rule:
keyword_sub = . + 2
    P_EAGER_TOKEN '-'|0x80
    P_SHUNT TOKEN_SUB
    P_JMP compulsory_expr_rule

multiplication_rule:
keyword_mul = . + 2
    P_EAGER_TOKEN '*'|0x80
    P_SHUNT TOKEN_MUL
    P_JMP compulsory_expr_rule

division_rule:
keyword_div = . + 2
    P_EAGER_TOKEN '/'|0x80
    P_SHUNT TOKEN_DIV
    P_JMP compulsory_expr_rule

modulus_rule:
keyword_mod = . + 2
    P_TOKEN 'M', 'O', 'D'|0x80
    P_SHUNT TOKEN_MOD
    P_JMP compulsory_expr_rule

leaf_rule:
    P_TRY parenthesised_rvalue_rule
    P_TRY varref_rvalue_rule
    P_TRY number_rvalue_rule
    P_TRY negate_rvalue_rule
    P_FAIL

parenthesised_rvalue_rule:
    P_EAGER_TOKEN '('|0x80
    P_COMMIT
    P_PAREN
    P_JSR expr_rule
    P_EAGER_TOKEN ')'|0x80
    P_FLUSH
    P_RETURN

varref_rvalue_rule:
    P_WORD
    P_RETURN

number_rvalue_rule:
    P_NUMBER
    P_RETURN

negate_rvalue_rule:
keyword_neg = . + 2
    P_EAGER_TOKEN '-'|0x80
    P_COMMIT
    P_SHUNT TOKEN_NEG
    P_JSR leaf_rule
    P_RETURN

keyword_zero:
    .byte '0'|0x80
keyword_mone:
    .byte '-', '1'|0x80

.data

.bss
object_table:
    .ds OBJECT_TABLE_SIZE * 2

global_variables:
    .ds HASH_SLOTS * 2
text_buffer:
    .ds 256
bytecode_buffer:
    .ds 256
operator_stack:
    .ds 256

; This must be last --- it's the beginning of the program workspace.

heapbase:

; vim: ts=4 sw=4 et:

