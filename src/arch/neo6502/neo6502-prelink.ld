/* This performs a fake link, so that we can see how big the BIOS is going to
 * be, so it can get placed properly at the end of memory in the real link.
 * Sigh, ld. */

MEMORY {
    zp : ORIGIN = 0, LENGTH = 0xff
	initram : ORIGIN = 0x8000, LENGTH = 0x4000
	hiram : ORIGIN = 0xc000, LENGTH = 0x4000
}

SECTIONS {
	INCLUDE "src/arch/neo6502/neo6502-common.ld"
}

