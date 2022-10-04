#include "cpm65_llvm.inc"
#include "zif_llvm.inc"

ZEROPAGE
__fcb: .fill 2

; Preserves XA.
zproc xfcb_clear
	pha
	lda #0
	;ldy #xfcb::s2   ; this one is actually cleared by the BDOS
	;sta (__fcb), y

	ldy #FCB_EX
	lda #0
	zrepeat
		sta (__fcb), y
		iny
		cpy #FCB_R2+1
	zuntil_eq

	pla
	rts
zendproc

zproc xfcb_prepare
	sta __fcb+0
	stx __fcb+1
	ldy #XFCB_US
	lda (__fcb), y
	ldy #BDOS_GET_SET_USER_NUMBER
	jsr BDOS
	lda __fcb+0
	ldx __fcb+1
	rts
zendproc

zproc xfcb_open
	jsr xfcb_prepare
	jsr xfcb_clear
	ldy #BDOS_OPEN_FILE
	jmp BDOS
zendproc

zproc xfcb_readsequential
	jsr xfcb_prepare
	ldy #BDOS_READ_SEQUENTIAL
	jmp BDOS
zendproc

zproc xfcb_writesequential
	jsr xfcb_prepare
	ldy #BDOS_WRITE_SEQUENTIAL
	jmp BDOS
zendproc


