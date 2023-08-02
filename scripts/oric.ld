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
	.head : {
		*(sector1) 
		. = ALIGN(256);
	} >jasminboot AT>initram

	.head : {
		*(sector2) 
		. = ALIGN(256);
		*(sector3)
		. = ALIGN(256);
	} >microdiscboot AT>initram

	INCLUDE "scripts/oric-common.ld"
}

OUTPUT_FORMAT {
	TRIM(initram)
}

