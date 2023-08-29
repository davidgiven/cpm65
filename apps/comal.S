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

; IMPORTANT --- remember how comparisons work!
;
; lda A
; cmp #NUM
; If the Z flag is 0, then A <> NUM and BNE will branch
; If the Z flag is 1, then A = NUM and BEQ will branch
; If the C flag is 0, then A (unsigned) < NUM (unsigned) and BCC will branch
; If the C flag is 1, then A (unsigned) >= NUM (unsigned) and BCS will branch

OBJECT_FREE     = 0
OBJECT_ATOM     = 1
OBJECT_INTEGER  = 2

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
v0:        .byte 0
v1:        .byte 0
v2:        .byte 0
i0:        .word 0, 0
i1:        .word 0, 0
i2:        .word 0, 0

bufferpos: .byte 0 ; current beginning of token in input buffer
bufferend: .byte 0 ; current end of token in input buffer

bytecodeptr:        .byte 0 ; current position in the bytecode
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
        
token_data TOKEN_EOL,     15, 1, 0, 0, lister_bad,     lister_bad,     exec_bad
token_data TOKEN_VARREF,  15, 3, 0, 1, lister_varref,  lister_bad,     exec_bad
token_data TOKEN_INTEGER, 15, 5, 0, 1, lister_integer, lister_bad,     exec_integer
token_data TOKEN_MUL,     10, 1, 2, 1, lister_infix,   keyword_mul,    exec_mul
token_data TOKEN_DIV,     10, 1, 2, 1, lister_infix,   keyword_div,    exec_div
token_data TOKEN_ADD,      9, 1, 2, 1, lister_infix,   keyword_add,    exec_add
token_data TOKEN_SUB,      9, 1, 2, 1, lister_infix,   keyword_sub,    exec_sub
token_data TOKEN_MOD,     10, 1, 2, 1, lister_infix,   keyword_mod,    exec_mod
token_data TOKEN_PRINT,    0, 1, 1, 0, lister_print,   lister_bad,     exec_print
token_data TOKEN_PRINTNL,  0, 1, 0, 0, lister_printnl, lister_bad,     exec_printnl
token_data TOKEN_ASSIGN,   0, 1, 2, 0, lister_assign,  keyword_assign, exec_bad

OBJECT_TABLE_SIZE = 256

zproc main
    jsr clear
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
        jsr list_line
        jsr print_buffer
        jsr print_nl

        ; Run it.

        lda #<bytecode_buffer
        sta execlineptr+0
        lda #>bytecode_buffer
        sta execlineptr+1
        lda #0
        sta execbyteptr
        jsr exec_line
    zendloop
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

zproc exec_line
    lda #0
    sta bufferpos
    sta bufferend
zendproc
    ; fall through
zproc exec
    ldy execbyteptr
    lda (execlineptr), y
    zif_eq  
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

zproc exec_print
    jsr pop_i0
    jsr buffer_print_i0
    jmp print_buffer
zendproc

zproc exec_printnl
    jsr buffer_print_nl
    jmp print_buffer
zendproc

zproc exec_integer
    ldy execbyteptr
    ldx #0
    zrepeat
        lda (execlineptr), y
        sta i0, x
        iny
        inx
        cpx #4
    zuntil_eq
    sty execbyteptr

    lda #OBJECT_INTEGER
    sta v0
    jmp push_i0
zendproc

zproc exec_add
    jsr pop_i1
    jsr pop_i0

    ldx #-4 & 0xff
    clc
    zrepeat
        lda i0+4, x
        adc i1+4, x
        sta i0+4, x
        inx
    zuntil_eq

    jmp push_i0
zendproc

zproc exec_sub
    jsr pop_i1
    jsr pop_i0

    ldx #-4 & 0xff
    sec
    zrepeat
        lda i0+4, x
        sbc i1+4, x
        sta i0+4, x
        inx
    zuntil_eq

    jmp push_i0
zendproc

zproc exec_mul
    jsr pop_i2
    jsr pop_i0

    jsr mul4

    jmp push_i0
zendproc

zproc exec_div
    jsr pop_i2
    jsr pop_i0

    jsr divs4

    jmp push_i0
zendproc

zproc exec_mod
    jsr pop_i2
    jsr pop_i0

    jsr divs4

    jmp push_i1
zendproc

zproc exec_bad
    brk
zendproc

zproc push_i2
    ldx #i2
    bne push_ix
zendproc

zproc push_i1
    ldx #i1
    bne push_ix
zendproc

zproc push_i0
    ldx #i0
zendproc
    ; fall through
zproc push_ix
    ldy #0
    lda v0
    sta (stackptr), y
    zrepeat
        iny
        lda 0, x
        sta (stackptr), y
        inx
        cpy #4
    zuntil_eq

    lda #5
    clc
    adc stackptr+0
    sta stackptr+0
    zif_cs
        inc stackptr+1
    zendif
    rts
zendproc

zproc pop_i2
    ldx #i2
    bne pop_ix              ; always taken
zendproc
zproc pop_i1
    ldx #i1
    bne pop_ix              ; always taken
zendproc
zproc pop_i0
    ldx #i0
zendproc
    ; fall through
zproc pop_ix
    sec
    lda stackptr+0
    sbc #5
    sta stackptr+0
    zif_cc
        dec stackptr+1
    zendif

    ldy #0
    lda (stackptr), y
    sta v0
    zrepeat
        iny
        lda (stackptr), y
        sta 0, x
        inx
        cpy #4
    zuntil_eq
    rts
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
        lda text_buffer, x ; get char from buffer
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

; --- Lister ----------------------------------------------------------------

; Renders the line in bytecode_buffer.

; operator_stack contains the tree.
; <bytecode address> {<child tree nodes>}*

; 1 2 + print
; 0 1 2 3

; 0 1 2 a b 3 c
; a b c d e f g
;           ^

zproc list_line
    lda #0
    sta bytecodeptr
    sta opstackptr
    sta listerflags
    tsx
    stx listersp

    zloop
        ; Create the first byte of the tree node.

        ldx bytecodeptr
        lda bytecode_buffer, x
        zbreakif_eq
        ldy opstackptr
        sty listerroot
        txa
        sta operator_stack, y
        inc opstackptr

        ; Pop consumed stack items.

        ldx bytecodeptr
        ldy bytecode_buffer, x
        lda token_size_table, y
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

        ldx bytecodeptr
        ldy bytecode_buffer, x
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

        ldx bytecodeptr
        ldy bytecode_buffer, x
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
    lda bytecode_buffer, y      ; get bytecode
    tay
    lda token_listers_hi, y     ; get lister routine
    pha
    lda token_listers_lo, y
    pha
    rts
zendproc

zproc lister_bad
    brk
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
    tax
    lda bytecode_buffer+1, x
    sta p0+0
    lda bytecode_buffer+2, x
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
    tax

    ldy #0
    zrepeat
        lda bytecode_buffer+1, x
        sta i0, y
        inx
        iny
        cpy #4
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
    lda bytecode_buffer, y      ; get bytecode
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
    ldx bytecode_buffer, y      ; get current bytecode
    lda token_precedence_table, x ; get current bytecode precedence
    sta p0+1

    ldy p0+0
    ldx operator_stack+0, y     ; get parameter bytecode address
    ldy bytecode_buffer, x      ; get parameter bytecode
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

; --- Parser ----------------------------------------------------------------

zproc parse_line
    lda #0
    sta bytecodeptr
    sta opstackptr
    tsx
    stx parsestartstackptr

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

    lda #0
    ldx bytecodeptr
    sta bytecode_buffer, x

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

    ldx #0
    lda #10
    sta i2+0
    stx i2+1
    stx i2+2
    stx i2+3

    stx i0+0
    stx i0+1
    stx i0+2
    stx i0+3

    lda bufferpos
    sta bufferend

    ; Is the number negative?

    ldx bufferend
    lda text_buffer, x
    cmp #'-'
    php                 ; save comparison result for later
    zif_eq
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

    plp                 ; is the number remainder?
    zif_eq
        jsr negi0
    zendif

    lda #TOKEN_INTEGER
    jsr queue_bytecode
    lda i0+0
    jsr queue_bytecode
    lda i0+1
    jsr queue_bytecode
    lda i0+2
    jsr queue_bytecode
    lda i0+3
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

statement_rule:
    P_TRY print_rule
    P_TRY assignment_rule
;    P_TRY for_rule
;    P_TRY if_rule
;    P_TRY proc_rule
    P_PANIC

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
    P_TRY parenthesised_rule
    P_TRY varref_rule
    P_TRY number_rule
    P_FAIL

parenthesised_rule:
    P_EAGER_TOKEN '('|0x80
    P_COMMIT
    P_PAREN
    P_JSR expr_rule
    P_EAGER_TOKEN ')'|0x80
    P_FLUSH
    P_RETURN

varref_rule:
    P_WORD
    P_RETURN

number_rule:
    P_NUMBER
    P_RETURN

.data

.bss
object_table:
    .ds OBJECT_TABLE_SIZE * 2

text_buffer:
    .ds 256
bytecode_buffer:
    .ds 256
operator_stack:
    .ds 256

; This must be last --- it's the beginning of the program workspace.

program_end:

; vim: ts=4 sw=4 et:

