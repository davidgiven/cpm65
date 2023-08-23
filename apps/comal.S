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

parsecmd:  .word 0 ; points into parser bytecode
parsefailcmd:       .word 0 ; where we fail parsing to
parsefailbufferpos: .byte 0 ; buffer position to rewind to
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

pop_succeed_ptr:
    .word pop_succeed

zproc pop_succeed
    jmp pop_succeed
zendproc

zproc pop_panic
    jmp pop_panic
zendproc

zproc pop_try
    ; Push old backtracking state.

    lda parsefailcmd+0
    pha
    lda parsefailcmd+1
    pha
    lda parsefailbufferpos
    pha
    lda parsefailstackptr
    pha

    ; Push the marker indicating that this is a backtracking state.

    lda #0
    pha
    pha

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

    ; Update backtracking state.

    lda parsecmd+0
    sta parsefailcmd+0
    lda parsecmd+1
    sta parsefailcmd+1
    lda bufferpos
    sta parsefailbufferpos
    tsx
    stx parsefailstackptr

    ; Switch to rule being tried.

    lda p0+0
    sta parsecmd+0
    lda p0+1
    sta parsecmd+1

    jmp parse_state_machine
zendproc

; Revert to a backtracking state.

zproc pop_fail
    ; Revert the state.

    ldx parsefailstackptr
    txs
    lda parsefailbufferpos
    sta bufferpos
    lda parsefailcmd+0
    sta parsecmd+0
    lda parsefailcmd+1
    sta parsecmd+1

    ; Pop the old state off the stack.

    pla             ; discard marker
    pla

    pla
    sta parsefailstackptr
    pla
    sta parsefailbufferpos
    pla
    sta parsefailcmd+1
    pla
    sta parsefailcmd+0

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
        jmp pop_return
    zendif

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

zproc pop_token
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
    beq fail

    jsr get_atom
    ; returns pointer to token data in p0

    ldy #2
    lda p0+0
    cmp (parsecmd), y
    bne fail
    iny
    lda p0+1
    cmp (parsecmd), y
    bne fail

    lda #4
    jsr parse_advance

    jmp parse_state_machine
fail:
    jmp pop_fail
zendproc

zproc pop_word
    jmp pop_fail
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

.macro P_PANIC
    .word pop_panic
.endm

.macro P_RETURN
    .word pop_return
.endm

.macro P_TOKEN token
    .word pop_token
    .word \token
.endm

.macro P_WORD
    .word pop_word
.endm

.macro P_NUMBER
    .word pop_number
.endm

statement_rule:
    P_TRY assignment_rule
    P_TRY print_rule
    P_PANIC

assignment_rule:
    P_JSR lvalue_rule
    P_TOKEN assignment_token
    P_JSR expr_rule
    P_RETURN

print_rule:
    P_TOKEN print_token
    P_JSR optional_expr_rule
    P_RETURN

lvalue_rule:
    P_WORD
    P_RETURN

optional_expr_rule:
    P_TRY expr_rule
    P_RETURN

expr_rule:
    P_NUMBER
    P_RETURN

input_buffer:
    .ascii "PRINT"
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
    TOKEN assignment_token, ':', '='|0x80
    TOKEN print_token, 'P', 'R', 'I', 'N', 'T'|0x80
.bss
    .ds (OBJECT_TABLE_SIZE - token_count) * 2

; This must be last --- it's the beginning of the program workspace.

program_end:

; vim: ts=4 sw=4 et:

