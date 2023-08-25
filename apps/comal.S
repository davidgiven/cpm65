#include "../include/cpm65.inc"
#include "zif.inc"

; 1. Program storage
; 2. Editor
; 3. Interpreter
; 4. Variable storage
; 5. Correctness

; hi TPAEND
;    heap
;      v
;
;      ^
;    stack
;    comal bytecode
;    object table
;    interpreter
; lo TPABASE

OBJECT_FREE     = 0
OBJECT_ATOM     = 1

ATOM_TYPE       = 0
ATOM_DATA       = 1

TOKEN_VARREF    = 1 ; +2 bytes for the ID
TOKEN_MUL       = 0x0f
TOKEN_ADD       = 0x10
TOKEN_PRINT     = 0xfd
TOKEN_PRINTNL   = 0xfe
TOKEN_ASSIGN    = 0xff

ZEROPAGE

progbase:  .word 0
stackbase: .word 0
stackptr:  .word 0
heaptop:   .word 0
heapptr:   .word 0

p0:        .word 0
p1:        .word 0

bufferpos: .byte 0 ; current beginning of token in input buffer
bufferend: .byte 0 ; current end of token in input buffer

bytecodeptr:        .byte 0 ; current position in the bytecode
opstackptr:         .byte 0 ; operator stack pointer
parsecmd:           .word 0 ; points into parser bytecode
parsefailstackptr:  .byte 0 ; stack pointer to rewind to

OBJECT_TABLE_SIZE = 256

zproc main
    jsr clear
    
    lda #0
    sta bufferpos
    jsr parse_line

    rts
zendproc

zproc clear
    ; Initialise pointers.

    ldy #BDOS_GETTPA
    jsr BDOS
    stx heaptop+1
    stx heapptr+1
    lda #0
    sta heaptop+0
    sta heapptr+0

    lda #<program_end
    sta progbase+0
    lda #>program_end
    sta progbase+1

    lda #0
    tay
    sta (progbase), y

    lda progbase+0
    sta stackbase+0
    lda progbase+1
    sta stackbase+1
    inc stackbase+0
    zif_eq
        inc stackbase+1
    zendif

    lda stackbase+0
    sta stackptr+0
    lda stackbase+1
    sta stackptr+1

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

zproc print_nl
    lda #0x0d
    jsr bdos_CONOUT

    lda #0x0a
    jmp bdos_CONOUT
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

; p1 is the object ID counter. p0 is
; a pointer to the slot (which may contain zero
; Allocates a block of size p1 on the heap. The object ID is returned in p1 and
; a pointer to the new object in p0. The first byte of the block must be set
; to a valid object type.

zproc heap_alloc
    ; Store the size of the object above the object itself on the heap.

    sec
    lda heapptr+0
    sbc #2
    sta heapptr+0
    zif_cc
        dec heapptr+1
    zendif

    ldy #0
    lda p1+0
    sta (heapptr), y
    iny
    lda p1+1
    sta (heapptr), y

    ; Allocate the object itself.

    sec
    lda heapptr+0
    sbc p1+0
    sta heapptr+0
    lda heapptr+1
    sbc p1+1
    sta heapptr+1

    ; TODO: check for running out of memory here.

    ; Find a free slot in the object table.

    jsr find_first_object
    zrepeat
        zif_eq
            ; Found a free slot.

            lda heapptr+1
            sta (p0), y
            dey
            lda heapptr+0
            sta (p0), y

            ; Return the object pointer in p0.

            lda heapptr+0
            sta p0+0
            lda heapptr+1
            sta p0+1

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

            ldy #ATOM_TYPE
            lda (p0), y
            cmp #OBJECT_ATOM
            zif_eq
                ; Compare the text.

                ldy #ATOM_DATA
                ldx bufferpos
                zloop
                    lda (p0), y
                    and #0x7f
                    cmp input_buffer, x
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
    adc #ATOM_DATA          ; add one for the header

    sta p1+0
    lda #0
    sta p1+1
    jsr heap_alloc          ; allocate space for the atom
    ; id is in p1, pointer in p0

    ldy #ATOM_TYPE          ; set the type
    lda #OBJECT_ATOM
    sta (p0), y

    ; Copy the word into the heap object.

    ldx bufferpos
    zrepeat
        lda input_buffer, x ; get char from buffer
        iny
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

; --- Parser ----------------------------------------------------------------

zproc parse_line
    lda #0
    sta bytecodeptr
    sta opstackptr

    lda #<statement_rule
    sta parsecmd+0
    lda #>statement_rule
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

    tsx
    txa
    jsr print_hex8_number
    lda #' '
    jsr bdos_CONOUT
    lda parsecmd+0
    ldx parsecmd+1
    jsr print_hex16_number
    jsr print_nl

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
zproc queue_bytecode
    ldx bytecodeptr
    sta output_bytecode, x
    inx
    stx bytecodeptr
    rts
zendproc

; Shunts the operator A through the shunting yard algorithm.
zproc shunt_operator
    ldx opstackptr
    zif_ne
        zrepeat
            ldx opstackptr
            cmp operator_stack, x
            zbreakif_cc

            pha
            lda operator_stack, x
            dec opstackptr
            jsr queue_bytecode
            pla

            ldx opstackptr
        zuntil_eq
    zendif

    ; Stack the operator onto the operator stack.

    inx
    sta operator_stack, x
    stx opstackptr
    rts
zendproc

; Unstacks all remaining operators.
zproc unstack_operators
    zloop
        ldx opstackptr
        zbreakif_eq

        lda operator_stack, x
        dec opstackptr
        jsr queue_bytecode
    zendloop
    rts
zendproc
    
pop_succeed_ptr:
    .word pop_succeed

zproc pop_succeed
    jsr unstack_operators
    brk
zendproc

zproc pop_panic
    brk
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

    lda #'>'
    jsr bdos_CONOUT
    lda parsecmd+0
    ldx parsecmd+1
    jsr print_hex16_number
    jsr print_nl

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

    lda #'<'
    jsr bdos_CONOUT
    jsr print_nl

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

zproc parser_skip_whitespace
    zloop
        ldx bufferpos
        lda input_buffer, x
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
        lda input_buffer, x
        cmp #'A'-1
        zbreakif_cc
        cmp #'Z'
        zbreakif_cs

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

zproc pop_token
    jsr parser_fetch_word
    ; returns pointer to token data in p0

    ldy #2
    lda p0+0
    cmp (parsecmd), y
    bne 1f
    iny
    lda p0+1
    cmp (parsecmd), y
    bne 1f

    lda #4
    jsr parse_advance

    jmp parse_state_machine
1:
    jmp pop_fail
zendproc

zproc pop_word
    jsr parser_fetch_word

    lda #TOKEN_VARREF
    jsr queue_bytecode
    sta output_bytecode, x
    lda p1+0
    jsr queue_bytecode
    lda p1+1
    jsr queue_bytecode

    lda #2
    jsr parse_advance

    jmp parse_state_machine
zendproc

zproc pop_char
    jsr parser_skip_whitespace

    ldy #2
    lda (parsecmd), y
    ldx bufferpos
    cmp input_buffer, x
    zif_ne
        jmp pop_fail
    zendif
    inc bufferpos

    lda #3
    jsr parse_advance
    jmp parse_state_machine
zendproc

zproc pop_eol
    jsr parser_skip_whitespace

    ldx bufferpos
    lda input_buffer, x
    zif_ne
        jmp pop_fail
    zendif

    lda #2
    jsr parse_advance
    jmp parse_state_machine
zendproc

zproc pop_number
    jmp pop_fail
    jmp parse_state_machine
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

.macro P_TOKEN token
    .word pop_token
    .word \token
.endm

.macro P_SHUNT token
    .word pop_shunt
    .byte \token
.endm

.macro P_CHAR c
    .word pop_char
    .byte \c
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

statement_rule:
    P_TRY assignment_rule
    P_TRY print_rule
    P_PANIC

assignment_rule:
    P_JSR lvalue_rule
    P_CHAR '='
    P_SHUNT TOKEN_ASSIGN
    P_JSR expr_rule
    P_RETURN

print_rule:
    P_TOKEN print_token
    P_COMMIT
    P_TRY print_no_terminator_rule
    P_TRY print_first_expr_rule
    P_RETURN

print_first_expr_rule:
    P_SHUNT TOKEN_PRINT
    P_JSR expr_rule
    P_TRY print_expr_list_rule
    P_RETURN

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
    P_CHAR ','
    P_RETURN

print_separator_rule:
    P_TRY comma_rule
semicolon_rule:
    P_CHAR ';'
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
    P_TRY binop_rule
    P_TRY leaf_rule
    P_FAIL

binop_rule:
    P_JSR leaf_rule
    P_TRY addition_rule
    P_TRY multiplication_rule
    P_FAIL

addition_rule:
    P_CHAR '+'
    P_SHUNT TOKEN_ADD
    P_JMP compulsory_expr_rule

multiplication_rule:
    P_CHAR '*'
    P_SHUNT TOKEN_MUL
    P_JMP compulsory_expr_rule

leaf_rule:
    P_TRY varref_rule
    P_FAIL

varref_rule:
    P_WORD
    P_RETURN

input_buffer:
    .ascii "PRINT A,B+C;"
    .byte 0

.data

.set token_count, 0
.macro TOKEN name, values:vararg
.data 1
    .word \name
.data 0
\name:
    .byte OBJECT_ATOM
    .byte \values
.set token_count, token_count + 1
.endm
    
.data 1
object_table:
    TOKEN print_token, 'P', 'R', 'I', 'N', 'T'|0x80
.bss
    .ds (OBJECT_TABLE_SIZE - token_count) * 2

output_bytecode:
    .ds 256
operator_stack:
    .ds 256

; This must be last --- it's the beginning of the program workspace.

program_end:

; vim: ts=4 sw=4 et:

