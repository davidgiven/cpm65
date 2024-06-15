MEMORY {
    zp : ORIGIN = 0x00, LENGTH = 0xef
    ram (rw) : ORIGIN = 0x2000, LENGTH = 0xde00
	reloram (rw) : ORIGIN = 0x200, LENGTH = 0x1200
    usrram (rw) : ORIGIN = 0xc000, LENGTH = 0x2000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__ZEROPAGE_START__ = .;
		__ZEROPAGE_END__ = 0xef;
	} >zp

	.loader : {
		*(loader)
	} >usrram

	.text : {
		__bios_data_start = LOADADDR(.text);
		__bios_data_end = __bios_data_start + __bios_end - __bios_start;
		__bios_start = .;
		*(.text .text.*)
	} >reloram AT>usrram

	.data : {
		*(.data .data.* .rodata .rodata.*)
		__bios_end = .;
	} >reloram AT>usrram

	.noinit (NOLOAD) : {
		*(.bss .bss.*)
		*(.noinit .noinit.*)
		. = ALIGN(256);

		__TPA_START__ = .;
		__TPA_END__   = 0xfe00;
	} >reloram
}

OUTPUT_FORMAT {
	TRIM(reloram)
}

DISK_BUFFER = 0xfe00;

