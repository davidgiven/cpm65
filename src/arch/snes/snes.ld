MEMORY {
    zp : ORIGIN = 6, LENGTH = 0x100-6
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

	.bss (NOLOAD) : {
		*loader.o(.bss .bss.*)
		*loader.o(.noinit .noinit.*)
	} >loader

	.text : {
		BIOS_EXEC_ADDR = .;
		*(.text .text.*);
		*(.data .data.*)
		BIOS_END_ADDR = .;
	} >bios AT>loader
	 
	.bss (NOLOAD) : {
		*(.bss .bss.*)
		*(.noinit .noinit.*)
		. = ALIGN(0x100);
		__TPA_START__ = .;
		__TPA_END__ = 0xff00;
	} >bios
}

OUTPUT_FORMAT {
	TRIM(loader)
}

