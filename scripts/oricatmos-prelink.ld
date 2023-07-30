/* This performs a fake link, so that we can see how big the BIOS is going to
 * be, so it can get placed properly at the end of memory in the real link.
 * Sigh, ld. */

MEMORY {
    zp : ORIGIN = 0, LENGTH = 0xff
    loram (rw) : ORIGIN = 0x400, LENGTH = 0xb100
	hiram (rw) : ORIGIN = 0xc000, LENGTH = 0x4000
	initram (rw) : ORIGIN = 0x400, LENGTH = 0xb000
	midram (rw) : ORIGIN = 0xb800, LENGTH = 0x380

	jasminboot (rw) : ORIGIN = 0x0400, LENGTH = 0x0100
	microdiscboot (rw) : ORIGIN = 0x9800, LENGTH = 0x0200
}

SECTIONS {
	/DISCARD/ : {
		*(sector1)
		*(sector2)
		*(sector3)
	}

	INCLUDE "scripts/oricatmos-common.ld"
}
