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

OBJECT_TABLE_SIZE = 256

zproc main
    jsr clear
    
    lda #0
    sta bufferpos
    lda #4
    sta bufferend
    jsr get_atom

    lda #0
    sta bufferpos
    lda #4
    sta bufferend
    jsr get_atom

    lda #0
    sta bufferpos
    lda #5
    sta bufferend
    jsr get_atom

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

    ; Clear the object table.

    lda #1          ; counter
    sta p1+0
    lda #0
    sta p1+1

    zrepeat
        lda p1+0    ; copy counter to object ID
        sta p0+0
        lda p1+1
        sta p0+1

        jsr find_object_slot ; get pointer to slot

        lda #0          ; stores 0x0000 into slot
        tay
        sta (p0), y
        iny
        sta (p0), y

        inc p1+0        ; increment counter
        zif_eq
            inc p1+1
        zendif

        lda p1+0
        cmp #<OBJECT_TABLE_SIZE
        zcontinueif_ne
        lda p1+1
        cmp #>OBJECT_TABLE_SIZE
    zuntil_eq
        
    rts
zendproc

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

    lda #1          ; counter
    sta p1+0
    lda #0
    sta p1+1

    zrepeat
        lda p1+0    ; copy counter to object ID
        sta p0+0
        lda p1+1
        sta p0+1

        jsr find_object_slot ; get pointer to slot

        ldy #0          ; check if value in slot is 0x0000
        lda (p0), y
        iny
        ora (p0), y
        
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

        inc p1+0        ; increment counter
        zif_eq
            inc p1+1
        zendif

        lda p1+0
        cmp #<OBJECT_TABLE_SIZE
        zcontinueif_ne
        lda p1+1
        cmp #>OBJECT_TABLE_SIZE
    zuntil_eq
        
    ; TODO: object table is full, error out
    rts
zendproc

; Returns the object ID in p1 of the atom in the input buffer starting at
; bufferpos and ending at the character just before bufferend.

zproc get_atom
    ; Search the object table for atoms.

    lda #1          ; counter
    sta p1+0
    lda #0
    sta p1+1

    zrepeat
        lda p1+0    ; copy counter to object ID
        sta p0+0
        lda p1+1
        sta p0+1

        jsr find_object_slot ; get pointer to slot

        ldy #0          ; check if value in slot is 0x0000
        lda (p0), y
        iny
        ora (p0), y
        
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

        inc p1+0        ; increment counter
        zif_eq
            inc p1+1
        zendif

        lda p1+0
        cmp #<OBJECT_TABLE_SIZE
        zcontinueif_ne
        lda p1+1
        cmp #>OBJECT_TABLE_SIZE
    zuntil_eq

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

input_buffer:
    .ascii "WORDX"
    .byte 0

.bss

object_table:
    .ds OBJECT_TABLE_SIZE * 2

; This must be last --- it's the beginning of the program workspace.

program_end:

; vim: ts=4 sw=4 et:

