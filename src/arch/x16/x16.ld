MEMORY {
    zp1 : ORIGIN = 0x22, LENGTH = 0x80 - 0x22
	zp2 : ORIGIN = 0xa9, LENGTH = 0x100 - 0xa9
	basic (rw) : ORIGIN = 0x7ff, LENGTH = 0x800
    ram (rw) : ORIGIN = 0xa000, LENGTH = 0x2000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__ZP1_START__ = .;
		__ZP1_END__ = 0xff;

		__ZP0_START__ = 0x22;
		__ZP0_END__ = 0x80;
	} >zp2

	.loader : {
		*(loader)
	} >basic

	.text : {
		__bios_data_start = LOADADDR(.text);
		__bios_data_end = __bios_data_start + __bios_end - __bios_start;
		__bios_start = .;
		*(.text .text.*)
	} >ram AT>basic

	.data : {
		*(.data .data.* .rodata .rodata.*)
		__bios_end = .;
	} >ram AT>basic

	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);

		__TPA1_START__ = .;
		__TPA1_END__   = 0xc000;

		__TPA0_START__ = 0x0400;
		__TPA0_END__   = 0x9f00;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(basic)
}

