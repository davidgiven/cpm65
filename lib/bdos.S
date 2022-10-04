#include "cpm65_llvm.inc"
#include "zif_llvm.inc"

.macro bdos name, func
	zproc \name
		ldy #\func
		jmp BDOS
	zendproc
.endm

bdos bdos_SETDMA,      BDOS_SET_DMA_ADDRESS
bdos bdos_CONOUT,      BDOS_CONSOLE_OUTPUT
bdos bdos_WRITESTRING, BDOS_WRITE_STRING

