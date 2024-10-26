; This is the jump table layout used to communicate between the BIOS and the
; supervisor. It has to be kept in sync with the jump table definition in
; main.asm.

JUMP_BIOS_SELDSK = 0x00ff00+(0*3)
JUMP_BIOS_SETDMA = 0x00ff00+(1*3)
JUMP_BIOS_SETSEC = 0x00ff00+(2*3)
JUMP_BIOS_READ   = 0x00ff00+(3*3)
JUMP_BIOS_WRITE  = 0x00ff00+(4*3)
JUMP_TTY         = 0x00ff00+(5*3)
JUMP_SCREEN      = 0x00ff00+(6*3)
