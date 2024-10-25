MEMORY {
    zp : ORIGIN = 0, LENGTH = 0x100
	stack : ORIGIN = 0x100, LENGTH = 0x100
	bios : ORIGIN = 0x200, LENGTH = 0x7e00
	loader : ORIGIN = 0x8000, LENGTH = 0x8000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__ZEROPAGE_START__ = .;
		__ZEROPAGE_END__ = 0xff;
	} >zp

	.text : {
		*(loader)
		*loader.o(.text .text.*)
		BIOS_LOAD_ADDR = .;
	} >loader

	.text : {
		BIOS_EXEC_ADDR = .;
		*bios.o(.text .text.* .data .data.*)
		. = ALIGN(0x100);
		BIOS_END_ADDR = .;
	} >bios AT>loader
}

OUTPUT_FORMAT {
	TRIM(loader)
}

