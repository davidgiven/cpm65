MEMORY {
    zp : ORIGIN = 0, LENGTH = 0xff
	initram : ORIGIN = 0x8000, LENGTH = 0x4000
	hiram : ORIGIN = 0xc000, LENGTH = 0x4000
}

SECTIONS {
	INCLUDE "src/arch/neo6502/neo6502-common.ld"
}

OUTPUT_FORMAT {
	TRIM(initram)
}

