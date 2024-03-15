;  MIT License
;
;  Copyright (c) 1978, 2021 Hans Otten
;
;  Permission is hereby granted, free of charge, to any person obtaining a copy
;  of this software and associated documentation files (the "Software"), to deal
;  in the Software without restriction, including without limitation the rights
;  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;  copies of the Software, and to permit persons to whom the Software is
;  furnished to do so, subject to the following conditions:
;
;  The above copyright notice and this permission notice shall be included in all
;  copies or substantial portions of the Software.
;
;  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;  SOFTWARE.
;
;
; First version by G.J.v.d. Grinten 1978,1979
; 
; Hans Otten 1982- 2006 -june 2007  
;   - typed in as is, adapted for TASM , exact binary identical to original! 
;   - bugfixed KIM-1 routines
;   - lowercase
;   - KIM in character no echo
;   - SFA GFA mcode for files handles, no meaning though
;
; Hans Otten V2  October 2021
; interpreter only, loader removed
; expects pascalm mcode and procedure buffer loaded externally
;
; Memory layout
; - $0000 zeropage, starts at 0 
; - $2000 interpreter code, readonly
; - PRCBUF
; - M-code (from BASE)
; - Heap (after last M-code)
; - stack down from ENDCOR
;
; interpreter start 2000 readonly 
; procedure buffer after interpreter at page boundary readonly 
; base memory pcode readonly
; end base memory (stack growing down) read/write
; prcbuf  placed before base memory
;
; TODO
;
; - check if prcbuf is handled right in CUP2
; - align naming conventions with Pascal interpreter

#define CHECK_NULLS 0           // check some null pointer dereferences

#include "cpm65.inc"

ZEROPAGE

pc:     .fill 2 ; program counter
stack:  .fill 2 ; software stack pointer
hp:     .fill 2 ; heap pointer
mp:     .fill 2 

mpsave: .fill 2 
progbase: .fill 2 ; start of user m-code
strptr: .fill 1 ; string print pointer
eolb:   .fill 1 ; end of input line boolean
eofb:   .fill 1 ; end of file boolean
op:     .fill 1 ; last op code

fa:     .fill 2 ; file object pointer
tmp2l2: .fill 2 ; 2 byte temp
tmp3l2: .fill 2 ; 2 byte temp
ytmp:   .fill 1 ; temporary Y save
cmdline: .fill 1 ; command line offset

tmp1l8: .fill 8 ; 8 byte temp field

;
; file structure layout
;
FP_FCB        = 0
FP_POS        = 36
FP_NEEDSFLUSH = 37
FP_BUFFER     = 38

;
; constants
;
CR      = $0D                   ; Carriage return
LF      = $0A                   ; Linefeed

BASE    = cpm_ram               ; where the m-code is loaded
prcbuf  = BASE + 2

.macro incr zp
        inc \zp + 0
        bne . + 4
        inc \zp + 1
.endm

.macro incr2 zp
        clc
        lda \zp + 0
        adc #2
        sta \zp + 0
        bne . + 4
        inc \zp + 1
.endm

.macro decr zp
        lda \zp + 0
        bne . + 4
        dec \zp + 1
        dec \zp + 0
.endm

.macro decr2 zp
        sec
        lda \zp + 0
        sbc #2
        sta \zp + 0
        bcs . + 4
        dec \zp + 1
.endm

; Interpreter 
;
; Initialize interpreter
.text
.global main
main:
        lda #0
        sta fa+1
        sta eolb
        sta eofb

        lda #>mstart ; start of mcode 
        sta pc + 1
        lda #<mstart
        sta pc

        jsr bdos_GETTPA     ; get end of memory
        dex                 ; the stack is post-decrement
        stx stack + 1
        stx mp + 1
        lda #0xff
        sta stack
        sta mp

;
; say hello and show the amount of free memory
;

        lda #<startup_msg
        ldx #>startup_msg
        jsr bdos_WRITESTRING
        sec
        lda stack+0
        sbc #<BASE
        pha
        lda stack+1
        sbc #>BASE
        jsr phex2
        pla
        jsr phex2
        lda #<free_msg
        ldx #>free_msg
        jsr bdos_WRITESTRING
       
;
; load the program
;
        lda cpm_fcb+FCB_F1
        cmp #' '
        beq badload

        lda #0
        sta cpm_fcb+FCB_CR
        
        lda #<BASE              ; heap starts at the beginning of program workspace
        sta hp+0
        ldx #>BASE
        stx hp+1

        lda #<cpm_fcb
        ldx #>cpm_fcb
        jsr bdos_OPEN_FILE

loadloop:
        lda hp+0
        ldx hp+1
        jsr bdos_SET_DMA_ADDRESS

        lda #<cpm_fcb
        ldx #>cpm_fcb
        jsr bdos_READ_SEQUENTIAL
        bcs done_load

        lda hp+0
        eor #0x80
        sta hp+0
        bmi noadd
        inc hp+1
noadd:
        jmp loadloop
done_load:                  ; heap has been advanced past the program

        ;
        ; compute the base of user mcode
        ;

        clc
        lda BASE+0
        adc #<BASE
        sta progbase+0
        lda BASE+1
        adc #>BASE
        sta progbase+1

        ;
        ; locate the command line parameters
        ;

        ldx #0
param_loop:
        cpx cpm_cmdlinelen
        beq done_params
        lda cpm_cmdline, x
        inx
        cmp #' '
        bne param_loop
done_params:
        stx cmdline
;        
        jmp interpr            ; start interpreting

badload:
        lda #<badload_msg
        ldx #>badload_msg
        jsr bdos_WRITESTRING
        jmp con_cr
badload_msg:
        .ascii "No OBB specified"
        .byte 13, 10, 0

startup_msg:
        .asciz "Pascal-M interpreter for CP/M-65: "
free_msg:
        .ascii " bytes free"
        .byte 13, 10, 0

        ;
        ; useful routines
       
        ;
        ; Add fast 2 to PC
        ;
incpc2: clc
        lda pc
        adc #$02
        sta pc
        bcc incpca      ; adjust upper?
        inc pc + 1
incpca: rts
        ;
        ; to HEX
        ;
hexit:  cmp #$3A
        php
        and #$0F
        plp
        bcc hexit1      ; 0 .. 9
        adc #$08         
hexit1: rts
        ;
        ; stack operations PULL and PUSH
        ; PULL2 and PUSH2
        ; enter or exit with val in A or A + Y
        ; A contains upper 8 bits , Y lower 8 bits
        ;
pull2:  incr stack
        ldx #0
        lda (stack, x)
        tay
pull:
        incr stack
        ldx #0
        lda (stack, x)
        rts
       
push2:  ldx #0
        sta (stack, x)
        decr stack
        tya
push:
        ldx #0
        sta (stack, x)
        decr stack
        rts
        
        ;
        ; fatal error message 
        ; output string (max 256, with CRLF, end)

        ; exit to monitor after print
        ;
prstrng:
        txa
        tay
        tax
        jsr bdos_WRITESTRING
        jsr con_cr
        jmp bdos_EXIT
        
        ;
        ; Compute base address of level (op-x)
        ; leave result in tmp2l2
        ;
basead: lda mp          ; Mark pointer is default
        sta tmp2l2
        lda mp + 1
        sta tmp2l2 + 1
        lda op          ; check level
        and #$0F        ; isolate level
        beq bas2        ; if level = 0 then finished
        tax             ; x := level
bas1:   decr tmp2l2     ; offset for mark pointrer in stack
        ldy #$01        ; point to upper part of inirect MP
        lda (tmp2l2),y  ; high part
        pha             ; save on stack
        dey 
        lda (tmp2l2),Y  ; get low part
        sta tmp2l2
        pla
        sta tmp2l2 + 1  ; high part
        dex             ; level = level - 1
        bne bas1        ; not finished
bas2:   rts             ; ready 
;
;   
; Addget get a address of level X 16 bit
;
addget: jsr basead      ; get base address of proper level
        ldy #$01        ; get low part of address
        sec
        lda tmp2l2      ; PC points to high part
        sbc (pc),y      ; low part add
        sta tmp2l2      ; replace
        dey             ; get high part
        lda tmp2l2 + 1
        sbc (pc),y
        sta tmp2l2 + 1  ; tmp2l2 now points to address
        incr pc
addg1:  incr pc
        incr tmp2l2     ; subtract 1 from address because LCAP
                        ; this is correct for all calls
        rts             ; return
;
; Get small address of proper level (same as addget)
;
sadget: jsr basead
        sec
        ldy #0
        lda tmp2l2      ; get address pointer
        sbc (pc),y
        sta tmp2l2
        bcs addg1
        dec tmp2l2 + 1
        bcc addg1       ; always taken

;
; Extended jump table.
;
.macro emitxtab_entry op, val
        .byte \val\()@mos16\op
.endm

.macro emitxtab_entry_16 op, val
        .rept 16
                emitxtab_entry \op, \val
        .endr
.endm

.macro emitxtab op
        emitxtab_entry_16 \op, ldcis ; load small integer constant (0..15)
        emitxtab_entry_16 \op, ldas  ; load short address
        emitxtab_entry_16 \op, ldad  ; load address
        emitxtab_entry_16 \op, msto  ; mark stack without return bytes
        emitxtab_entry_16 \op, mstn  ; mark stack with return bytes
        emitxtab_entry_16 \op, lod1  ; load 1 byte data item on stack
        emitxtab_entry_16 \op, lod2  ; load 2 byte data item on stack
        emitxtab_entry_16 \op, str1  ; store 1 byte into memory
        emitxtab_entry_16 \op, str2  ; store 2 byte into memory
        emitxtab_entry \op, leq2     ; 2 bytes less than or equal test
        emitxtab_entry \op, mfor     ; for interpr processing
        emitxtab_entry \op, leqm     ; less or equal test for arrays
        emitxtab_entry \op, les2     ; less than test for 2-byte data items
        emitxtab_entry \op, leq8     ; is contained in test for sets
        emitxtab_entry \op, lesm     ; less test
        emitxtab_entry \op, equ2     ; equal test for 2 bytes
        emitxtab_entry \op, geq8     ; contains test for sets
        emitxtab_entry \op, equm     ; equal test for records and arrays
        emitxtab_entry \op, equ8     ; equal test for sets
        emitxtab_entry \op, ind1     ; indirectly load 1-byte data item
        emitxtab_entry \op, ind2     ; indirectly load 2-byte data item
        emitxtab_entry \op, ind8     ; indirectly load 8-byte data item
        emitxtab_entry \op, sto1     ; store 1 byte
        emitxtab_entry \op, sto2     ; store 2 byte
        emitxtab_entry \op, sto8     ; store 8 byte
        emitxtab_entry \op, ldc      ; load 2-byte constant
        emitxtab_entry \op, retp     ; return from procedure or function
        emitxtab_entry \op, adi      ; add integer
        emitxtab_entry \op, andb     ; boolean and
        emitxtab_entry \op, dif      ; set difference
        emitxtab_entry \op, dvi      ; integer divide
        emitxtab_entry \op, inn      ; test if element in set
        emitxtab_entry \op, int      ; set interaction
        emitxtab_entry \op, ior      ; inclusive or
        emitxtab_entry \op, mod      ; modulus function
        emitxtab_entry \op, mpi      ; integer multiply
        emitxtab_entry \op, ngi      ; negate integer
        emitxtab_entry \op, not      ; negate boolean
        emitxtab_entry \op, sbi      ; subtract integer
        emitxtab_entry \op, sgs      ; generate singleton set
        emitxtab_entry \op, uni      ; set union
        emitxtab_entry \op, lnc      ; load negative constant
        emitxtab_entry \op, fjp      ; false jump
        emitxtab_entry \op, ujp      ; unconditionally jump
        emitxtab_entry \op, decb     ; decrement
        emitxtab_entry \op, incb     ; increment
        emitxtab_entry \op, ent      ; enter block
        emitxtab_entry \op, cas      ; case statement processor
        emitxtab_entry \op, mov      ; move storage
        emitxtab_entry \op, dec1     ; decrement by 1
        emitxtab_entry \op, inc1     ; increment by 1
        emitxtab_entry \op, ldcs     ; load set constant (8 bytes)
        emitxtab_entry \op, cap      ; call assembly procedure
        emitxtab_entry \op, lca      ; load constant address
        emitxtab_entry \op, csp      ; call standard procedure
        emitxtab_entry \op, cup1     ; call user procedure simple
        emitxtab_entry \op, cup2     ; complex call user procedure
        emitxtab_entry \op, fix21    ; clean up stack after call to single
        emitxtab_entry \op, lns      ; load null set
        emitxtab_entry \op, sfa      ; set file handle
        emitxtab_entry \op, gfa      ; get file handle
        emitxtab_entry \op, mvb      ; move and blank
        emitxtab_entry \op, shl      ; shift left
        emitxtab_entry \op, shr      ; shift right
.endm

xtab_lo:
        emitxtab lo
xtab_hi:
        emitxtab hi

;
;Standard M-code procedure to start M-code interpretation,

mstart: .byte   $30         ; MST0 mark stack
        .byte   $BE,0       ; CUP1  0    call procedure 0
        .byte   $BD,$0B     ; CSP   11   Standard procedure  Stop 
;
; Start of Pascal-M code interpreter
;
; test if stack will overflow
;
tststk: sec         ; test if stack and heap will meet
        lda stack   
        sbc hp
        sta tmp2l2
        lda stack + 1
        sbc hp + 1
        bcs tst1x1      ; overflow already
ovfl:   ldx #>msg005    ; send message and fatal error exit
        lda #<msg005
        jmp string
tst1x1: bne interpr
        lda tmp2l2
        cmp #$30        ; reserve $30 on stack?
        bcc ovfl
;
; main interpr starts here
;
interpr:
#if 0                  // enable for tracing
        jsr writepc
        jsr writesp
#endif
#if 0                  // enable for bytecode breakpoints
        sec
        lda pc+0
        sbc progbase
        tay
        lda pc+1
        sbc progbase+1
        cmp #$3f        ; high
        bne xxx
        cpy #$2b        ; low
        bne xxx
        brk
xxx:
#endif
        ldx #0
        lda (pc,x)
        sta op
        incr pc
        cmp #$C7
        bcs notimp      ; opcode out of range
        tay
        lda xtab_lo, y
        sta tmp2l2
        lda xtab_hi, y
        sta tmp2l2+1
        jmp (tmp2l2)

notimp:
        ldx #>msg007
        lda #<msg007
        jmp string      ; not implemented message, fatal

;
; setup1 and setup2 are subroutines to setup 
;
; variables for various functions (ADD, SUBTR etc)
;
setup2: jsr pull2       ; get first operand
        sta tmp3l2 + 1
        sty tmp3l2
setup1: jsr pull2       ; next item goes into tmp2l2
        sta tmp2l2 + 1
        sty tmp2l2
        rts
;
; simple m-codes
;
; LDCS (0X) load small integer constant 
;
ldcis:  ldy op      ; load small scalar constant
        lda #0      ; push single byte value 0
        jsr push2
        jmp interpr
;
;
; LDA (1X YY) load short address
;
ldas:   jsr sadget      ; load small address
        lda tmp2l2 + 1  ; get high part
        ldy tmp2l2      ; low part
        jsr push2       ;   
        jmp tststk
;
; LDA (2X YY YY) load address
;
ldad:   jsr addget      ; load 16 bit address
        lda tmp2l2 + 1  ; get high part of indirect address
        ldy tmp2l2      ; lw part
        jsr push2
        jmp tststk
;
; MST0  (3X) mark stack without return bytes
;
msto:   jsr basead      ; get base address of proper level X
        lda stack       ; move stack pointer to mpsave
        sta mpsave
        lda stack + 1
        sta mpsave + 1
        lda tmp2l2 + 1  ; push base address
        ldy tmp2l2      ; as saved by basead
        jsr push2
        lda mp + 1      ; save mark pointer
        ldy mp
        jsr push2
        lda #0          ; push dummy for p counter save
        tay  
        jsr push2
        jmp tststk      ; test for overflow
;
; MSTN  (4X YY) mark stack with return bytes for function
;
mstn:   ldy #$0
        lda (pc),y      ; get operand (nr of bytes to fill)
        tay 
        incr pc         ; increment PC
mstn1:  lda #0
        jsr push        ; push a dummy onto stack
        dey 
        bne mstn1       ; not done yet
        jmp msto        ; now mark stack as normal
;
; LOD1 (5X YY) load 1 byte item onto stack
;
lod1:   jsr sadget      ; get item address in reserved stack
        ldx #0
        lda (tmp2l2,x)  ; load item
        tay             ; low part
        txa             ; push zero
        jsr push2       ; all items on stack are 16 bit
        jmp tststk
        ;
        ; LOD2 (6X YY) load 2 byte data item
        ;
lod2:   jsr sadget      ; get address in tmp2l2 of item
        ldx #0          ; index 0
        lda (tmp2l2,x)  ; low part
        tay             ; save A in Y
        incr tmp2l2     ; high part
        ldx #0
        lda (tmp2l2,x)  ; get high part
        jsr push2       ; push all

        #if 0
        lda #'='
        jsr bdos_CONOUT
        ldy #2
        lda (stack), y
        jsr phex2
        ldy #1
        lda (stack), y
        jsr phex2
        #endif
        
        jmp tststk      ; 
        ;
        ; STR1 (7X YY) store 1 byte data item
        ;
str1:   jsr sadget
        jsr pull2       ; get 16 bit with 8 valid bit item
        tya             ; low part, X is zero
        sta (tmp2l2,x)  ; store in memory
        jmp interpr
;
; STR2 (8X YY) store 2 byte data item in memory
;
str2:   jsr sadget      ; store 16 bits
        jsr pull2       ; high part in A
        pha
        tya             ; store low part first
        sta (tmp2l2,x)
        incr tmp2l2     ; decrement address on stack
        ldx #0
        pla             ; get high part
        sta (tmp2l2,x)  ; store high part
        jmp interpr
;
; indirect routines
;
; 90 LEQ2
;
leq2:   jsr cmp2        ; compare next to top with top
        bne false       ; false
true:   ldy #$01        ; true = 1
        bne leq2x2      ; always
false:  ldy #$00        ; false
leq2x2: lda #$00        ; dummy
        jsr push2       ; push boolean on stack
        jmp interpr
;
; FOR
;
mfor:   ldy #$01        ; point to first cell on stack
        lda (stack),y   ; test for init interpr cell
        bmi for1        ; been here before
        ora #$80        ; set been here 
        sta (stack),y
        jsr forin       ; init interpr cell
        jmp for5        ; process for interpr
for1:   ldy #$07        ; get address of cell in tmp2
        lda (stack),y
        sta tmp2l2
        iny
        lda (stack),y   
        sta tmp2l2 + 1
        ldy #0          ; get the interpr count
        lda (tmp2l2),y
        sta tmp3l2
        iny
        lda (stack),y   ; test for 1 or 2 bytes
        and #$01
        sta tmp3l2 + 1  ; init tmp3l2 =1 for zero
        beq for2
        lda (tmp2l2),y  ; get second byte
        sta tmp3l2 + 1
for2:   lda (stack),y   ; y is still 1
        and #$04        ; to or downto test
        bne for3        ; down
        incr tmp3l2
        jmp for4
for3:   decr tmp3l2
for4:   ldy #$00        ; save new interpr counter
        lda tmp3l2
        sta (tmp2l2),y
        iny
        lda (stack),y
        and #$01        ; 1 or 2 bytes to save?
        beq for5        ; 
        lda tmp3l2 + 1
        sta (tmp2l2),y  ; save second byte
for5:   ldy #$01            
        lda (stack),y
        and #$04        ; test to or downto
        bne for6        ; downto?
        sec
        ldy #03     ; point to end value
        lda (stack),y
        sbc tmp3l2
        iny
        lda (stack),y   ; 16 bit test
        sbc tmp3l2 + 1
        bmi forend
forlp:  ldy #$00
        lda (pc),y      ; get jump address in tmp2
        sta tmp2l2 + 1
        iny 
        lda (pc),y  
        sta tmp2l2
        jmp cas2        ; jump
for6:   sec         ; downto
        ldy #$03
        lda tmp3l2
        sbc (stack),y
        iny
        lda tmp3l2 + 1
        sbc (stack),y
        bpl forlp       ; do the jump
forend: clc
        lda stack
        adc #$08
        sta stack
        lda stack + 1
        adc #$00
        sta stack + 1   ; remove for table
        jsr incpc2      ; increment pc by 2
        jmp interpr
        ;
        ; 92 LEQM
        ;
leqm:   jsr compar
        lda #$00
        ldy tmp1l8
        dey 
        bpl leqm2
        ldy #$01
leqm1:  jsr push2
        jmp tststk
leqm2:  tay 
        beq leqm1
        ;
        ; LES2
les2:   
        jsr cmp2        ; same as leq2 without equal
        jmp false       ; minus test should have been catched
        ;
cmp2:   jsr setup2      ; first OP in tmp3, second in tmp2
        sec         
        lda tmp2l2
        sbc tmp3l2
        sta tmp2l2      ; save for equal test
        lda tmp2l2 + 1
        sbc tmp3l2 + 1
        bmi cmp2a       ; if less than (15 bits) 
        bne cmp2b       ; not equal high pat
        lda tmp2l2      ; possible high part equal
        rts
cmp2a:  pla             ; full return address
        pla
        jmp true
cmp2b:  pla
        pla
        jmp false
        ;
        ; 94 LEQ8
        ;
leq8:   ldy #$08        ; nr of set words and offset in set
        ldx #0  
        sty tmp2l2      ; tmp2l2 is count
        stx tmp3l2      ; test for end result
leq8a:  jsr pull        ; get a member
        and     (stack),y   ; delete non-interesting parts
        eor (stack),y   ; flip remaining bits
        beq leq8b       ; if all bits flipped
        inc tmp3l2      ; not al bits flipped not same
leq8b:  dec tmp2l2      ; we did the interpr again
        bne leq8a       ; repeat 8 times
        jsr pull2       ; second stack from set
        jsr pull2   
        jsr pull2   
        jsr pull2   
        lda tmp3l2
        bne leq8c
        jmp true      ; set was contained in
leq8c:  jmp false      ; not contained in
        ;
        ; 95 LESM
        ; 
lesm:   jsr compar
        lda #$00
        ldy tmp1l8
        bpl lesm2
        ldy #$01
lesm1:  jsr push2
        jmp tststk
lesm2:  tay
        beq lesm1
        ;
        ; 96 EQU2
        ;
equ2:   jsr setup2      ; compare tmp2 and tmp3
        lda tmp3l2      ; test lower part
        cmp tmp2l2
        bne equ2x1      
        lda tmp3l2 + 1
        cmp tmp2l2 + 1
        bne equ2x1      ; not equal
        jmp true      ; push 1
equ2x1: jmp false
        ;
        ; 97 GEQ8
        ;
geq8:   ldy #$08        ; offset n stack and count
        ldx #$00
        sty tmp2l2      ; read comment at ISTR 94
        stx tmp3l2
geq8a:  jsr pull
        sta tmp2l2 + 1
        lda (stack),y   ; get member to test
        and tmp2l2
        eor tmp2l2 + 1
        beq geq8b
        inc tmp3l2
geq8b:  dec tmp2l2
        bne geq8a
        jsr pull2
        jsr pull2
        jsr pull2
        jsr pull2
        lda tmp3l2
        bne geq8c
        jmp false
geq8c:  jmp false      ; send false
        ;
        ; 98 EQUM
        ;
equm:   jsr compar
        lda #$00
        ldy tmp1l8
        bne equm2
        iny
equm1:  jsr push2
        jmp tststk
equm2:  tay
        beq equm1
        ;
        ; 99 EQU8
        ;
equ8:   ldy #$08        ; 8 bytes to compare
        sty tmp2l2      ; use as count also
        ldx #$00
        stx tmp2l2 + 1  ; use as switch zero on end
equ8x1: jsr pull        ; get a char in A to compare
        cmp (stack),y   ; compare in stack
        beq equ8x2      ; if equal
        inc tmp2l2 + 1  ; not equal set switch
equ8x2: dec tmp2l2
        bne equ8x1
        jsr pull2       ; clean up stack
        jsr pull2
        jsr pull2
        jsr pull2
        lda tmp2l2 + 1
        bne equ8x3      ; if not equal
        jmp true       ; send 1
equ8x3: jmp false      ; send 0
        ;
        ; 9A IND1
        ;
ind1:   jsr setup1      ; get indirect address from stack
        ldy #$00        ; index
        lda (tmp2l2),y  ; get 1 byte operand
        tay
        lda #$00        ; dummy
        jsr push2   
        jmp interpr
        ;
        ; 9B IND2
        ;
ind2:   jsr setup1      ; get address to 16 byte indirect op
        ldx #$00
        lda (tmp2l2,x)
        tay         ; setup for push
        incr tmp2l2     ; increment pointer
        ldx #0
        lda (tmp2l2,x)
        jsr push2       ; push item onto stack
        jmp interpr
        ;
        ; 9C IND8
        ;
ind8:   jsr setup1      ; get indirect address
ind8x1: ldy #$07
ind8x2: lda (tmp2l2),y  ; linear move
        jsr push
        dey             ; point to upper part
        bpl ind8x2      ; repeat until 8 worrds done
        jmp tststk
        
#if CHECK_NULLS
writezero:
        ldx #>writezero_msg
        lda #<writezero_msg
        jmp string
writezero_msg:
        .asciz "Write to nil"
#endif

        ;
        ; 9D STO1
        ;
sto1:   jsr setup2
        #if CHECK_NULLS
                lda tmp2l2
                ora tmp2l2+1
                beq writezero
        #endif
        
        ldy #$00
        lda tmp3l2      ; op to store
        sta (tmp2l2),y
        jmp interpr
        ;
        ; 9E STO2
        ;
sto2:   jsr setup2      ; get 16 bit address in tmp3 and address
        #if CHECK_NULLS
                lda tmp2l2
                ora tmp2l2+1
                beq writezero
        #endif

        ldy #$00
        lda tmp3l2
        sta (tmp2l2), y
        iny
        lda tmp3l2 + 1  ; upper half
        sta (tmp2l2), y
        jmp interpr
        ;
        ; 9F STO8
        ;
sto8:   
        ldy #$09        ; add 10 to stackpointer to read add
        lda (stack),y   ; lower part of address
        sta tmp2l2
        iny 
        lda (stack),y
        sta tmp2l2 + 1
        
        #if CHECK_NULLS
                ora tmp2l2
                beq writezero
        #endif
        
        ldy #$00
sto8x1: jsr pull        ; get item from stack
        sta (tmp2l2),y  ; linear move
        iny
        cpy #$08        ; do 8 words
        bne sto8x1
        jsr pull2       ; and for final get address from stack
        jmp interpr
        ;
        ; A0 LDC
        ;
ldc:    lda (pc,x)      ; load 16 bit constant
        pha         ; save high part
        inc pc
        bne ldc1
        inc pc + 1
ldc1:   lda (pc,x)      ; get low part
        tay         ; ready for push
        inc pc
        bne ldc2
        inc pc + 1
ldc2:   pla         ; high part
        jsr push2       
        jmp tststk
        ;
        ; A1 RETP
        ;
retp:   lda mp      ; reset stackpointer
        sec
        sbc #$06
        sta stack
        lda mp + 1
        sbc #$00        ; setup stack 6 bytes away from MP
        sta stack + 1
        jsr pull2       ; get PC from stack
        sty pc
        sta pc + 1
        jsr     pull2       ; get Mark pointer
        sty mp
        sta mp + 1
        jsr pull2       ; get dummy mp base address from stack
        jmp interpr
        ;
        ; A2 ADI
        ;
adi:    jsr setup2      ; add 2 16 bit numbers
        clc
        lda tmp2l2
        adc tmp3l2      ; add low part
        tay         ; result to Y
        lda tmp2l2 + 1
        adc tmp3l2 + 1
        jsr push2
        jmp interpr
        ;
        ; A3 ANDB
        ;
andb:   jsr setup2      ; and for boolean
        lda tmp3l2
        and tmp2l2
        tay
        lda #$00        ; dummy
        jsr push2
        jmp interpr
        ; A4 DIF
        ;
dif:    ldy #$08
        sty tmp2l2      ; counter 8
dif1:   jsr pull
        and (stack),y
        eor (stack),y
        sta (stack),y
        dec tmp2l2
        bne dif1
        jmp interpr
        ;
        ; A5 DVI
        ;
dvi:    jsr mdset       ; setup for divide
        jsr divide
        lda tmp1l8 + 6  ; get sign of result
        and #$01
        beq dvi1        ; no correction
        lda tmp1l8 + 4
        eor #$FF
        sta tmp1l8 + 4
        lda tmp1l8 + 5
        eor #$FF
        sta tmp1l8 + 5
        incr tmp1l8 + 4
dvi1:   ldy tmp1l8 + 4
        lda tmp1l8 + 5
        jsr push2
        jmp interpr
        ;
        ; A6 INN
        ;
inn:    ldy #$00        ; get set from stack
inn1:   jsr pull
        sta tmp1l8,y
        iny
        cpy #$08        ; sets are 8 bytes
        bne inn1
        jsr pull2       ; get the bit to test
        tya 
        and #$07        ; bit on word
        tax
        tya
        lsr a
        lsr a
        lsr a
        tay         ; word nr offset in tmp1l8
        lda #$00        ; repeat
        sec         ;  shift bit in a
inn2:   ror a       ;
        dex         ; decr bit nr
        bpl inn2
        and tmp1l8,y    ; test bit
        beq inn3        ; if not set
        ldy #$01
        bne inn4
inn3:   ldy #$00        ; true
inn4:   lda #$00        ; dummmy for 16 bits
        jsr push2
        jmp interpr
        ;
        ; A7 INT
int:    ldy #$08
        sty tmp2l2
int1:   jsr pull
        and (stack),y
        sta (stack),y
        dec tmp2l2
        bne int1
        jmp interpr
        ;
        ; A8 IOR
        ;
ior:    jsr setup1
        ldy #$01
        lda (stack),y
        ora tmp2l2
        sta (stack),y
        jmp interpr
        ;
        ; A9 MOD
        ;
mod:    jsr mdset
        jsr divide
        lda tmp1l8 + 6
        and #$01
        beq mod1
        lda tmp1l8 + 2
        eor #$FF
        sta tmp1l8 + 2
        lda tmp1l8 + 3
        eor #$FF
        sta tmp1l8 + 3
        incr tmp1l8 + 2
mod1:   ldy tmp1l8 + 2
        lda tmp1l8 + 3
        jsr push2
        jmp interpr
        ;
        ; AA MPI
        ;
mpi:    jsr mdset
        jsr mply
        lda tmp1l8 + 6 
        and #$01
        beq mpi1
        lda tmp1l8 + 4
        eor #$FF
        sta tmp1l8 + 4
        lda tmp1l8 + 5
        eor #$FF
        sta tmp1l8 + 5
        incr tmp1l8 + 4
mpi1:   ldy tmp1l8 + 4
        lda tmp1l8 + 5
        jsr push2
        jmp interpr
        ;
        ; AB NGI
        ;
ngi:    jsr setup1      ; get number to complement
        lda tmp2l2
        eor #$FF
        sta tmp2l2
        lda tmp2l2 + 1
        eor #$FF
        sta tmp2l2 + 1
        incr tmp2l2     ; ones complement
        ldy tmp2l2
        lda tmp2l2 + 1
        jsr push2
        jmp interpr
        ;
        ; AC NOT
        ;
not:    ldy #$01        ; complement boolean on stack
        lda (stack),y
        eor #$01        ; only bit 0 to do
        sta (stack),y
        jmp interpr
        ;
        ; AD SBI
        ;
sbi:    jsr setup2      ; subtract two 16 bit numbers on stack
        sec         
        lda tmp2l2
        sbc tmp3l2
        tay         ; result low part in Y
        lda tmp2l2 + 1
        sbc tmp3l2 + 1
        jsr push2       ; result ok
        jmp interpr
        ;
        ; AE SGS
        ;
sgs:    ldx #$00        ; geneterate single bit set
        ldy #$07        ; clear tmp1l8
sgs1:   stx tmp1l8,y
        dey
        bpl sgs1
        jsr pull2       ; get bit number of set
        tya
        and #$07        ; get bit no
        tax
        tya
        lsr a
        lsr a
        lsr a
        tay         ; byte no in y
        lda #$00
        sec
sgs2:   ror a       ; shift the bit in
        dex
        bpl sgs2
        sta tmp1l8,y    ; now bit in word is formed
        ldy #$07            ; now push set onto stack
        ldx #$00            ; 
sgs3:   lda tmp1l8,y        ; high bit first
        jsr push
        dey
        bpl sgs3
        jmp tststk
        ;
        ; AF UNI
        ;
uni:    ldy #$08
        sty tmp2l2
uni1:   jsr pull
        ora (stack),y
        sta (stack),y
        dec tmp2l2
        bne uni1
        jmp interpr
        ; 
        ; B0 LNC
        ;
lnc:    ldy #$01
        lda (pc),y
        eor #$FF        ; complement
        sta tmp2l2
        dey
        lda (pc),y
        eor #$FF
        sta tmp2l2 + 1
        incr tmp2l2
        lda tmp2l2 + 1  ;
        jmp decx1       ; use common end
        ;
        ; B1 FJP
        ;
fjp:    jsr setup1      ; get boolean from stack
        lda tmp2l2
        beq ujp         ; false jump
        jsr incpc2      ; next 
        jmp interpr
        ; 
        ; B2 UJP
        ;
ujp:    ldy #$01
        lda (pc),Y
        sta tmp2l2
        dey
        lda (pc),Y
        sta tmp2l2 + 1
        jmp cas2        ; do jump via use common end
        ;
        ; B3 DECB
        ;
decb:   jsr setup1
        ldy #$01
        sec
        lda tmp2l2
        sbc (pc),y
        sta tmp2l2
        dey
        lda tmp2l2 + 1
        sbc (pc),y
decx1:  ldy tmp2l2
        jsr push2
        jsr incpc2
        jmp interpr
        ;
        ; B4 INCB
        ;
incb:   jsr setup1
        ldy #$01
        clc
        lda tmp2l2
        adc (pc),y
        sta tmp2l2
        dey 
        lda tmp2l2 + 1
        adc (pc),y
        jmp decx1
        ;
        ; B5 ENT
        ;
ent:    ldy #$01        ; index to low part of bytes
        lda stack       ; nr of bytes to reserve on stack
        sec
        sbc (pc),y
        sta stack
        dey
        lda stack + 1
        sbc (pc),y
        sta stack + 1   ; words are reserved now
        jsr incpc2
        jmp tststk      ; check if stack has room
        ;
        ; B6 CAS
        ;
cas:    jsr setup1      ; case nr
        ldy #$01
        sec 
        lda tmp2l2      ; test for less than
        sbc (pc),y
        sta tmp3l2      ; save as index
        dey
        lda tmp2l2 + 1
        sbc (pc),y
        sta tmp3l2 + 1
        bmi casex       ; less than minimum test for else clause
        ldy #$03        ; else is standardized to otherwise
        sec
        lda (pc),y      ; test for larger than max
        sbc tmp2l2
        dey
        lda (pc),y
        sbc tmp2l2 + 1 
        bmi casex       ; if larger than max
        asl tmp3l2      ; multiply by two for dual word index
        rol tmp3l2 + 1
        
        clc             ; compensate for six-byte header
        lda tmp3l2
        adc #6
        sta tmp3l2
        bcc cas1
        inc tmp3l2+1
cas1:
        clc
        lda pc
        adc tmp3l2
        sta tmp3l2
        lda pc+1
        adc tmp3l2+1
        sta tmp3l2+1    ; tmp3l2 is now the address of the jump word

        ldy #0
        lda (tmp3l2), y
        iny
        ora (tmp3l2), y
        beq casex       ; no target, do ELSE

        lda (tmp3l2), y
        sta tmp2l2
        dey
        lda (tmp3l2), y
        sta tmp2l2 + 1
        
cas2:   clc
        lda tmp2l2      ; adjust address in tmp2 with progbase
        adc progbase
        sta pc
        lda tmp2l2 + 1
        adc progbase + 1
        sta pc + 1
        jmp interpr

casex:  ldy #$05        ; test for otherwise
        lda (pc),y
        sta tmp2l2
        dey
        lda (pc),y
        sta tmp2l2 + 1
        
        ora tmp2l2
        bne cas2
        ldx #>caseindex_msg
        lda #<caseindex_msg
        jmp string
caseindex_msg: .asciz "Case index"
        ;
        ; B7 MOV
        ;
mov:    jsr mover
        jmp interpr
        ; 
        ; Helper which does a MOV. This is also used by MVB.
        ;
mover:  jsr setup2          ; tmp2l2 is to and tmp3l2 is from
        ldy #$00
        lda (pc),y
        sta tmp1l8 + 1
        incr pc
        lda (pc),y
        sta tmp1l8
        incr pc             ; pc is now next instruction
        lda tmp1l8          ; check for zero length moves
        ora tmp1l8+1
        beq mov2
mov1:   lda (tmp3l2),y      ;
        sta (tmp2l2),y      ; move the data
        incr tmp2l2         ; next from
        incr tmp3l2         ; next to
        decr tmp1l8         ; how many?
        lda tmp1l8
        ora tmp1l8 + 1
        bne mov1 
mov2:   rts
        ;
        ; B8 DEC1
        ;
dec1:   jsr setup1          ; get operand in tmp2l2
        decr tmp2l2         ; minus 1
dec1a:  ldy tmp2l2          ; setup for push of result
        lda tmp2l2 + 1
        jsr push2           ; onto stack
        jmp interpr
        ;
        ; B9 INC1
        ;
inc1:   jsr setup1
        incr tmp2l2
        jmp dec1a           ; push on stack
        ;
        ; BA LDCS
        ;
ldcs:   ldy #$07
ldcs1:  lda (pc),y          ; get char
        jsr push
        dey
        bpl ldcs1           ; if not 8 done interpr
        clc
        lda #$08            ; PC := pc + 8
        adc pc
        sta pc
        bcc ldcs2
        inc pc + 1
ldcs2:  jmp tststk          
        ; 
        ; BB CAP
        ;
cap:    ldx #$00
        lda (pc,x)
        sta tmp2l2 + 1
        incr pc
        lda (pc,x)
        sta tmp2l2
        incr pc
        jmp (tmp2l2)        ; jump to new address
        ;
        ; BC LCA
lca:    ldy #$00
        lda (pc),y          ; nr of bytes as string length
        pha
        incr pc
        lda pc + 1
        ldy pc          ; address of string on stack
        jsr push2
        clc
        pla
        adc pc          ; nr of bytes, add lenth to PC
        sta pc
        bcc lca1
        inc pc + 1
lca1:   jmp tststk
        ; 
        ; BD CSP
        ;
csp:    ldy #$00
        lda (pc),y          ; get csp number
        asl a           ; *2 for jump table index
        tay 
        incr pc
        
        lda csptab, y
        sta tmp2l2
        lda csptab+1, y
        sta tmp2l2+1
        jmp (tmp2l2)
        
        ;
        ; standard procedure table
csptab: .word   wri         ;  0 write integer
        .word   wrc         ;  1 write character
        .word   wrs         ;  2 write string
        .word   rdi         ;  3 read integer
        .word   rln         ;  4 read end of line
        .word   rdc         ;  5 read character
        .word   wln         ;  6 write end of line
        .word   new         ;  7 new pointer
        .word   eof         ;  8 check for end of file
        .word   rst         ;  9 reset heap pointer
        .word   eln         ;  a test if end of line
        .word   stp         ;  b stop pascal program
        .word   odd         ;  c check if number on stack is odd
        .word   rstf        ;  d reset file
        .word   rwrf        ;  e rewrite file
        .word   stsf        ;  f status file
        .word   clsf        ; 10 close file
        .word   asnf        ; 11 assign file
        .word   getparams   ; 12 get command line parameters
        ;
        ; BE CUP1
        ;
cup1:   lda mpsave          ;
        sta mp
        lda mpsave + 1
        sta mp + 1
        jmp cupgo
        ;
        ; BF CUP2
        ;
cup2:   jsr pull2           ; complex call with function room
        sty tmp2l2          ; nr of stack to reserve
        clc
        lda stack           ; stack room
        adc tmp2l2
        sta tmp2l2
        lda stack + 1
        adc #$00
        sta tmp2l2 + 1
        lda tmp2l2
        clc
        adc #$06            ; offset for markstack
        sta mp
        lda tmp2l2 + 1
        adc #$00
        sta mp + 1
cupgo:  ldy #$00
        lda (pc),y          ; get procedure number
        pha                 ; save on stack
        incr pc             ; pc := pc + 1
        sec
        lda mp              ; get right place to store PC
        sbc #$05
        sta tmp2l2
        lda mp + 1
        sbc #$00
        sta tmp2l2 + 1
        ldy #$01            ; index into mark package
        lda pc + 1          ; high part PC
        sta (tmp2l2),y      ; store in frame
        dey                 ; next ell
        lda pc
        sta (tmp2l2),y      ; low part pc
        pla                 ; index
        asl a               ; *2 as index for jumptable
        tax            
        lda prcbuf,x  
        clc
        adc #<(BASE+2)
        sta pc
        inx
        lda prcbuf,x        ; pc from table
        adc #>(BASE+2)
        sta pc + 1
        jmp interpr         ; jump to new procedure
        ;
        ; C0 FIX21
        ;
fix21:  jsr pull            ; get operand
        tay             ; put to correct position
        lda #$00            ; dummy zero
        jsr push2           ; for truncated functions
        jmp interpr
        ; 
        ; C1 LNS
        ;
lns:    ldy #$08
lnsx1:  lda #$00
        jsr push
        dey             ; interpr
        bne lnsx1
        jmp tststk
        ;
        ; C2 SFA
        ;
sfa:    jsr pull2               ; get file handle constant
        sta fa+1
        sty fa+0                ; store
        jmp interpr
        ;
        ; C3 GFA
        ;
gfa:    ldy fa      ; load file handle constant
        lda fa+1    ; push single byte value 0
        jsr push2
        jmp interpr
        ;
        ; C4 MVB
        ;
mvb:    jsr mover           ; performs a normal move
        ; leaves tmp2l2 to where the blanks should go
        ; and Y=0
        lda (pc),y
        sta tmp1l8 + 1
        incr pc
        lda (pc),y
        sta tmp1l8
        incr pc             ; pc is now next instruction; tmp1l8 contains the number of blanks
        jmp mvb2
mvb1:   lda #' '            ;
        sta (tmp2l2),y      ; move the data
        incr tmp2l2
        decr tmp1l8         ; how many?
mvb2:   lda tmp1l8
        ora tmp1l8+1
        bne mvb1
        jmp interpr
        ;
        ; C5 SHL
        ;
shl:    jsr setup2      ; shift left two 16-bit numbers on the stack
        lda tmp2l2
        ldx tmp3l2      ; shift amount
shl1:   beq shl2        ; do nothing if shift is zero
        asl a
        rol tmp2l2+1
        dex
        bne shl1
shl2:   tay             ; result low into Y
        lda tmp2l2+1
        jsr push2
        jmp interpr
        ;
        ; C6 SHR
        ;
shr:    jsr setup2      ; shift right two 16-bit numbers on the stack
        lda tmp2l2+1
        ldx tmp3l2      ; shift amount
shr1:   beq shl2        ; do nothing if shift is zero
        tay
        rol a
        tya
        ror a
        ror tmp2l2
        dex
        bne shr1
shr2:   ldy tmp2l2
        jsr push2
        jmp interpr

;
; end of m-code machine instructions
;
; Standard procedure handlers
;
; PROC 0 WRI
        ;
wri:    jsr setup2          ; tmp3 is length to write
        lda tmp2l2 + 1      ; tmp2 is intger to write
        sta tmp1l8 + 1      ; save for sign
        bpl wri1            ; not to be complemented
        eor #$FF
        sta tmp2l2 + 1
        lda tmp2l2
        eor #$FF            ; lower byte
        sta tmp2l2
        incr tmp2l2         ; form ones complement
wri1:   ldy #$05
wri1a:  ldx #$00
        stx tmp1l8 + 2, y
        dey
        bpl wri1a           ; clear six cells
        jsr cvdec           ; convert to decimal in tmp1l8 + 3 - 7
        lda tmp1l8 + 1
        bmi wri2            ; setup for output number
        ldy #$20            ; space
        sty tmp1l8 + 1
        sty tmp1l8 + 2
        lda tmp1l8 + 3      ; leading spaces
        bne wri3
        sty tmp1l8 + 3      ; insert space
        lda tmp1l8 + 4      ; leading spaces
        bne wri3
        sty tmp1l8 + 4      ; insert space
        lda tmp1l8 + 5      ; leading spaces
        bne wri3
        sty tmp1l8 + 5      ; insert space
        lda tmp1l8 + 6
        bne wri3
        sty tmp1l8 + 6      ; insert space
        jmp wri3
wri2:   ldx #$20            ; so far for positive numbers
        stx tmp1l8 + 1
        ldy #$2D            ; sign char
        sty tmp1l8 + 2
        lda tmp1l8 + 3
        bne wri3
        stx tmp1l8 + 2
        sty tmp1l8 + 3
        lda tmp1l8 + 4
        bne wri3
        stx tmp1l8 + 3
        sty tmp1l8 + 4
        lda tmp1l8 + 5
        bne wri3
        stx     tmp1l8 + 4
        sty tmp1l8 + 5
        lda tmp1l8 + 6
        bne wri3
        stx tmp1l8 + 5
        sty tmp1l8 + 6
wri3:   lda tmp1l8 + 7
        ora #$30            ; adjust to ascii
        sta tmp1l8 + 7
        lda tmp1l8 + 6
        cmp #$0A            ; higher bits?
        bcs wri4            ; finished
        ora #$30
        sta tmp1l8 + 6
        lda tmp1l8 + 5
        cmp #$0A            ; higher bits?
        bcs wri4            ; finished
        ora #$30
        sta tmp1l8 + 5
        lda tmp1l8 + 4
        cmp #$0A            ; higher bits?
        bcs wri4            ; finished
        ora #$30
        sta tmp1l8 + 4
        lda tmp1l8 + 3
        cmp #$0A    
        bcs wri4
        ora #$30
        sta tmp1l8 + 3
wri4:   sec             ; subtract length
        lda tmp3l2
        sbc #$06
        bmi wri5            ; less or equal?
        beq wri5
        tay             ; y is nr of leading spaces
wri4a:  lda #$20            ; blank
        jsr wrt
        dec tmp3l2
        dey
        bne wri4a           ; print blanks 
wri5:   ldy tmp3l2          ; nr of bytes to write
        beq wri6            ; finished?
        sec
        lda #tmp1l8 + 8     ; address of first to print
        sbc tmp3l2          ; subtract length of string
        sta tmp2l2          ;
        ldx #$00
        stx tmp2l2 + 1      ; high part zero, tmp3l8 is ZP
wri5a:  lda (tmp2l2,x)
        jsr wrt
        inc tmp2l2
        ldx #$00
        dey
        bne wri5a
wri6:   jmp interpr
;
; proc 1 WRC 
;
wrc:jsr pull2           ; nr of sapces
wrc1:   dey
        beq wrc2            ; y =1 of length = 1
        bmi wrc2            ; length is zero
        lda #$20            ; space
        jsr wrt         ;
        jmp wrc1            ; do all spaces
wrc2:   jsr pull2           ; get char and dummy
        tya 
        jsr wrt
        jmp interpr
;
; PROC 2 WRS
;
wrs:    jsr setup2          ; tmp2l2 contains actual length
        sec             ; and tmp2l2 actual length
        lda tmp2l2
        sbc tmp3l2          ; spaces := actual - specified
        tay
        bpl wrs1            ; no spaces
        lda tmp2l2
        beq wrs4            ; specified = 0 ?
        sta tmp3l2          ; overwrite actual
        bne wrs2            ; start printing
wrs1:   beq wrs2            ; nr of spaces = 0?
        lda #$20
        jsr wrt
        dey
        bne wrs1
wrs2:   jsr setup1          ; address of string
        ldy #0
wrs3:   dec tmp3l2
        bmi wrs4
        lda (tmp2l2),y      ; get char
        jsr wrt             ; print char
        iny
        jmp wrs3
wrs4:   jmp interpr
        ;
        ; PROC 3 RDI
        ;
        ; this procedure is not checking overflow
        ;
rdi:    lda #$00            ; int = 0
        sta tmp1l8
        sta tmp1l8 + 1      ;
        sta tmp1l8 + 2      ; sign = +
rdi1:   jsr getch           ; get a char
        cmp #$20            ; skip spaces
        beq rdi1
        cmp #$2b            ; + sign?
        beq rdi2
        cmp #$2d            ; - sign?
        bne rdi3
        inc tmp1l8 + 2      ; set to minus
rdi2:   jsr getch           
rdi3:   sec             ; 
        sbc #$30            ; between 0 and 9 ?
        bmi rdi4        
        cmp #$0a            
        bcs rdi4            
        sta tmp1l8 + 3      ; save number 
        jsr mul10           ; shift number in by adding + current number* 10        
        clc
        lda tmp1l8
        adc tmp1l8 + 3
        sta tmp1l8
        lda tmp1l8 + 1
        adc #$00            ; add to word
        sta tmp1l8 + 1
        jmp rdi2            ; get next part of integer
rdi4:   jsr setup1              
        ldy #$00
        lda tmp1l8  + 2     ; sign flag?
        beq rdi5            ; complemnet
        lda tmp1l8
        eor #$FF            
        sta tmp1l8
        lda tmp1l8 + 1
        eor #$FF
        sta tmp1l8 + 1
        incr tmp1l8
rdi5:   lda tmp1l8
        sta (tmp2l2),y
        iny
        lda tmp1l8 + 1
        sta (tmp2l2),y
        jmp interpr
        ;
        ; PROC 4 RLN
        ;
rln:    lda eolb            ; eol set?
        bne rln1            ; clear
        jsr getch           ; skip until eoln
        jmp rln
rln1:   lda #$00            ; clear eoln
        sta eolb
        jmp interpr
        ;
        ; PROC 5 RDC
        ;
rdc:    jsr setup1
        jsr getch
        ldy #$00
        sta (tmp2l2),y      ; store char
        jmp interpr
        ;
        ; PROC 6 WLN
wln:    lda #$80            ; why?
        jsr crlf
        jmp interpr
        ;
        ; PROC 7 NEW
        ;
new:    jsr setup2          ; tmp3 length of room wanted
        ldy #$00            ; tmp2  address to save old HP
        lda hp
        sta (tmp2l2),y      ; put hp in frame
        clc
        adc tmp3l2          ; add number of cells to hp
        sta hp
        lda hp + 1
        iny 
        sta (tmp2l2),y
        adc tmp3l2 + 1
        sta hp + 1  
        jmp tststk
        ;
        ; PROC 8 EOF
        ;
eof:    ldy eofb            ; end of file boolean
        lda #$00
        jsr push2
        jmp tststk
        ;
        ; PROC 9 RST
        ;
rst:    jsr pull2           ; get old heap pointer
        sta hp + 1
        sty hp
        jmp interpr 
        ;
        ; PROC A ELN
        ;
eln:    
        ldy eolb            ; get EOLN boolean
        lda #$00
        jsr push2           ; push EOLN boolean on stack
        jmp tststk
        ;
        ; PROC B STP
        ;
stp:    jmp bdos_EXIT       ; just stop
        ;
        ; TODO: new standard procedures 
;      12 : ODDM ;
;      13 : RSFRWW  ;
;      14 : RSFRWW  ;
;      15 : STT  ;
;      16 : CLS         
        ; routines
        ;
getch:  
        jsr rdt         ; read from input
        cmp #$20            ; printable?
        bcc getch2
        cmp #$7F
        beq getch           ; ignore rubout
        ldy #$00            ; no EOLN flag
getch1: sty eolb
        rts
getch2: cmp #$0D            ; CR, then fake space and EOLN true
        bne getch3          ; ignore other control chars except OF
        lda #$20
        ldy #$01
        bne getch1
getch3: cmp #$1a            ; CTRL/Z is EOF
        bne getch
        ldy #$01
        sty eofb            ; set eof boolean
        lda #$20            ; fake space
        bne getch1          ; return with eol true also
        ;
        ; PROC C ODD
        ;
        ; why push and pull, do it on the stack is faster?
        ;
odd:    jsr pull2           ; get integer from stack
        tya             ; bit 0?
        and #$01            ; pos or neg?
        tay 
        lda #$00            ; pos  = 1
        jsr push2           ; push boolean on stack
        jmp interpr
        ;
        ; PROC D reset file
        ;
rstf:   lda #0x00
        ldy #FCB_CR
        sta (fa), y
        ldy #FP_NEEDSFLUSH
        sta (fa), y
        
        lda #0x80
        ldy #FP_POS
        sta (fa), y

        lda fa
        ldx fa+1
        ldy #BDOS_OPEN_FILE
        jsr BDOS
        jmp interpr
        ;
        ; PROC E rewrite file
        ;
rwrf:   lda fa
        ldx fa+1
        ldy #BDOS_DELETE_FILE
        jsr BDOS

        lda #0x01
        ldy #FP_NEEDSFLUSH
        sta (fa), y
        
        lda #0x00
        ldy #FCB_CR
        sta (fa), y
        ldy #FP_POS
        sta (fa), y

        lda fa
        ldx fa+1
        ldy #BDOS_CREATE_FILE
        jsr BDOS
        jmp interpr
        ;
        ; PROC F status file
        ;
stsf:   lda #0
        tay
        jsr push2
        jmp interpr
        ;
        ; PROC 10 close file
        ;
clsf:   ldy #FP_NEEDSFLUSH
        lda (fa), y
        beq clsf1               ; file doesn't need flushing before close

        ldy #FP_POS
        lda (fa), y
        cmp #$80
        beq clsf1

        jsr setdma
        lda fa
        ldx fa+1
        ldy #BDOS_WRITE_SEQUENTIAL
        jsr BDOS

clsf1:  lda fa
        ldx fa+1
        ldy #BDOS_CLOSE_FILE
        jsr BDOS
        jmp interpr
        ;
        ; PROC 11 assign file
        ;
asnf:   jsr setup1              ; string in tmp2l2
        
        lda fa
        ldx fa+1
        ldy #BDOS_SET_DMA_ADDRESS
        jsr BDOS
        
        lda tmp2l2
        ldx tmp2l2+1
        ldy #BDOS_PARSEFILENAME
        jsr BDOS

        jmp interpr
        ;
        ; PROC 12 get command line parameters
        ;
getparams:
        jsr setup1              ; destination address -> tmp2l2
        ldx cmdline
        ldy #1
getparams1:
        lda cpm_cmdline, x
        sta (tmp2l2), y
        inx
        iny
        cpx cpm_cmdlinelen
        bne getparams1
        sec
        txa
        sbc cmdline
        ldy #0
        sta (tmp2l2), y
        jmp interpr
        ;
        ; MUL10 multiply tmp1l8 by 10
mul10:  asl tmp1l8
        rol tmp1l8 + 1
        lda tmp1l8
        sta tmp1l8 + 4
        lda tmp1l8 + 1
        sta tmp1l8 + 5
        asl tmp1l8 + 4
        rol tmp1l8 + 5
        asl tmp1l8 + 4
        rol tmp1l8 + 5      ; * 8
        clc
        lda tmp1l8          ; add 2 times and
        adc tmp1l8 + 4
        sta tmp1l8
        lda tmp1l8 + 1
        adc tmp1l8 +5
        sta tmp1l8 + 1
        rts
        ;
        ; CVDEC convert hex to decimal
        ; results in
        ; tmp1l8 + 3  10000 count 
        ; tmp1l8 + 4  1000 count
        ; tmp1l8 + 5  100 count
        ; tmp1l8 + 6  10 count
        ; tmp1l8 + 7  rest
cvdec:  sec
        lda tmp2l2
        sbc #$10            ; subtract 10000
        pha
        lda tmp2l2 + 1
        sbc #$27
        bcc cvdec2          ; still larger
        sta tmp2l2 + 1      
        pla
        sta tmp2l2
        inc     tmp1l8 + 3      ; increment 10000 count
        bne cvdec           ; interpr 
cvdec2: pla
cvdec3: sec
        lda tmp2l2          ; subtract 1000's
        sbc #$E8            
        pha
        lda tmp2l2 + 1
        sbc #$03
        bcc cvdec4
        sta tmp2l2 + 1
        pla
        sta tmp2l2
        inc tmp1l8 + 4      ; incremnent 1000 count
        bne cvdec3          ; interpr
cvdec4: pla
cvdec5: sec
        lda tmp2l2          ; subtract 100's
        sbc #$64            
        pha
        lda tmp2l2 + 1
        sbc #$00
        bcc cvdec6
        sta tmp2l2 + 1
        pla
        sta tmp2l2
        inc tmp1l8 + 5      ; incremnent 100 count
        bne cvdec5          ; interpr
cvdec6: pla             ; 10's
cvdec7: sec
        lda tmp2l2          ; subtract 100's
        sbc #$0A            
        bcc cvdec8
        sta tmp2l2
        inc tmp1l8 + 6      ; incremnent 10 count
        bne cvdec7          ; interpr
cvdec8: lda tmp2l2
        sta tmp1l8 + 7
        rts
        ;
        ; FORIN initialize FOR interpr
        ;
forin:  ldy #$05
        lda (stack),y
        sta tmp3l2          ; initial interpr count
        iny
        lda (stack),y
        sta tmp3l2 + 1
        iny
        lda (stack),y       ; initial interpr count to cell
        sta tmp2l2
        iny
        lda (stack),y
        sta tmp2l2 + 1
        ldy #$00            ; initial interpr count to cell
        lda tmp3l2 
        sta (tmp2l2),y      ; store initial count in cell
        iny
        lda (stack),y       ; test for 1 or 2 bytes
        and #$01
        beq forin1          ; one byte?
        lda tmp3l2 + 1
        sta (tmp2l2),y      ; save upper byte
forin1: rts
        ;
        ; MPLY multiply two integers
        ; call mdset first to setup 
mply:   ldy #$0F
mply1:  lsr tmp1l8 + 3      ; get lsbit
        ror tmp1l8 + 2
        bcc mply2           ; more?
        clc
        lda tmp1l8 
        adc tmp1l8 + 4
        sta     tmp1l8 + 4
        lda tmp1l8 + 1
        adc tmp1l8 + 5
        sta     tmp1l8 + 5
mply2:  asl tmp1l8
        rol tmp1l8 + 1
        dey
        bne mply1           ; interpr
        rts
        ;
        ; MDSET setup for multiply/divide
        ;
mdset:  jsr pull2           ; get divisor/multiplicant
        sty tmp1l8          ; in tmp1l8 word
        sta tmp1l8 + 1
        jsr pull2           ; get divedent/multiplier
        sty tmp1l8 + 2      ; in tmp1l8 + 2 word
        sta tmp1l8 + 3
        lda #$00            ; clear rest of tmp1l8 space
        sta tmp1l8 + 7      ; no of shifts in multiply
        sta tmp1l8 + 6      ; end sign 1 = neg, 2 is pos
        sta tmp1l8 + 4      ; clear end result
        sta tmp1l8 + 5      ; in tmp1l8 + 4 word
        lda tmp1l8 + 1      ; test sign
        bpl mdset1
        eor #$FF            ; convert to one's complement
        sta tmp1l8 + 1
        lda tmp1l8
        eor #$FF
        sta tmp1l8
        incr tmp1l8
        inc tmp1l8 + 6
mdset1: lda tmp1l8 + 3      ; test sign
        bpl mdset2
        eor #$FF            ; convert to one's complement
        sta tmp1l8 + 3
        lda tmp1l8 + 2
        eor #$FF
        sta tmp1l8 + 2
        incr tmp1l8 + 2
        inc tmp1l8 + 6      ; adjust end sign
mdset2: rts
        ;
        ; divide integers 
        ; multiple subtraction
        ; call mdset first to setup 
divide: ldy #$01            ; do it at least once 
div1:   sec 
        lda tmp1l8 + 2
        sbc tmp1l8
        lda tmp1l8 + 3
        sbc tmp1l8 + 1
        bcc div2            ; divisor is larger than divent
        iny
        asl tmp1l8
        rol tmp1l8 + 1
        cpy #$10            ; more than 16 times?
        bne div1
        lda #<msg008        ; divison by zero, stop
        ldx #>msg008
        jmp string
div2:   sty tmp1l8 + 7
div3:   sec
        lda tmp1l8 + 2
        sbc tmp1l8
        pha             ; save result
        lda tmp1l8 + 3
        sbc tmp1l8 + 1
        php             ; save status
        rol tmp1l8 + 4
        rol tmp1l8 + 5
        plp
        bcc     div4
        sta tmp1l8 + 3
        pla 
        sta tmp1l8 + 2
        jmp div5
div4:   pla
div5:   lsr tmp1l8 + 1
        ror tmp1l8
        dec tmp1l8 + 7
        bne div3
        rts
        ;
        ; COMPAR 
        ;
compar: jsr setup2          ; tmp3 is right side of compare
        ldy #$00
        lda (pc),y          ; no to compare
        sta tmp1l8 + 1
        incr pc
        lda (pc),y
        sta tmp1l8
        incr pc
compa1: sec
        lda (tmp2l2),y
        sbc (tmp3l2),y
        beq compa4          ; if still the same check end
        bpl compa2          ; if tmp2 smaller
        dey
        bne compa3
compa2: iny
compa3: sty tmp1l8          ; leave result
        rts
compa4: incr tmp2l2
        incr tmp3l2         ; next word to compare
        decr tmp1l8         ; length to compare
        lda tmp1l8
        bne compa1          ; done?
        lda tmp1l8 + 1
        bne compa1
        sty tmp1l8          ; leave result
        rts
;
; character in/out
;
; Read one char from TTY without the KIM hardware echo
;
rdt:	sty ytmp
        lda fa+1
        beq ttyin

        ldy #FP_POS
        lda (fa), y
        cmp #0x80
        bne rdt1

        jsr setdma
        lda fa
        ldx fa+1
        ldy #BDOS_READ_SEQUENTIAL
        jsr BDOS
        bcs rdeof
        
        lda #0
        ldy #FP_POS
        sta (fa), y
        
rdt1:   clc
        adc #FP_BUFFER
        tay
        lda (fa), y

        pha
        ldy #FP_POS
        lda (fa), y
        clc
        adc #1
        sta (fa), y
        pla

        ldy ytmp
        rts

rdeof:  lda #$1a
        ldy ytmp
        rts

ttyin:  jsr bdos_CONIN
        ldy ytmp
        rts
; 
; Write one char to TTY
;
wrt:	sty ytmp    
        tax                     ; char to write
        lda fa+1
        beq ttyout

        ldy #FP_POS
        lda (fa), y
        cmp #0x80
        bne wrt1

        txa
        pha

        jsr setdma
        lda fa
        ldx fa+1
        ldy #BDOS_WRITE_SEQUENTIAL
        jsr BDOS
        
        pla
        tax

        lda #0
        ldy #FP_POS
        sta (fa), y
        
wrt1:   clc
        adc #FP_BUFFER
        tay
        txa
        sta (fa), y
        ldy #FP_POS
        lda (fa), y
        clc
        adc #1
        sta (fa), y

        ldy ytmp
        rts

ttyout:
        txa
        cmp #CR
        bne ttyout1
        jsr bdos_CONOUT
        lda #LF
ttyout1:jsr bdos_CONOUT
        ldy ytmp
        rts

;
; Sets the CP/M DMA pointer to this file's buffer.

setdma: clc
        lda fa
        adc #FP_BUFFER
        ldx fa+1
        bcc setdma1
        inx
setdma1:
        ldy #BDOS_SET_DMA_ADDRESS
        jmp BDOS
;
; CRLF on output 
;
crlf:   lda #CR
        jsr wrt
        lda #LF
        jmp wrt
;
; Print hex byte to console
;
phex2:  sed
        tax
        and #$0f
        cmp #9+1
        adc #$30
        tay
        txa
        lsr
        lsr
        lsr
        lsr
        cmp #9+1
        adc #$30
        cld

        sty ytmp
        jsr bdos_CONOUT
        lda ytmp
        jmp bdos_CONOUT
;
; Emergency halt
;
string: jsr bdos_WRITESTRING
abend:  lda #<abend_msg
        ldx #>abend_msg
        jsr bdos_WRITESTRING

        jsr writepc

        lda #<crlf_msg
        ldx #>crlf_msg
        jsr bdos_WRITESTRING
        jmp bdos_EXIT

writepc: lda #' '
        jsr bdos_CONOUT
        sec
        lda pc
        sbc progbase
        pha
        lda pc+1
        sbc progbase+1

        jsr phex2
        pla
        jmp phex2

        lda #10
        jsr bdos_CONOUT
        lda #13
        jmp bdos_CONOUT

writesp: lda #'~'
        jsr bdos_CONOUT

        lda stack+1
        jsr phex2
        lda stack
        jmp phex2

con_cr:
        lda #<crlf_msg
        ldx #>crlf_msg
        jmp bdos_WRITESTRING

abend_msg: .asciz " at"
crlf_msg:  .byte 13, 10, 0
;
; messages
;
msg005: .asciz "Out of stack"
msg007: .asciz "Not implemented"
msg008: .asciz "Div by zero"

